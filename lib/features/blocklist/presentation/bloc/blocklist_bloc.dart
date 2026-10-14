import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';

import '../../domain/repositories/i_blocklist_repository.dart';
import 'blocklist_event.dart';
import 'blocklist_state.dart';

export 'blocklist_event.dart';
export 'blocklist_state.dart';

@injectable
class BlocklistBloc extends Bloc<BlocklistEvent, BlocklistState> {
  final IBlocklistRepository _repository;
  int _activeRuleRequestId = 0;

  BlocklistBloc(this._repository) : super(const BlocklistState()) {
    on<BlocklistEvent>((event, emit) async {
      await event.when(
        started: () => _onStarted(emit),
        defaultDomainOverridesRefreshRequested: () =>
            _fetchDefaultDomainOverrides(emit),
        customRulesRefreshRequested: () => _fetchCustomRules(emit),
        defaultDomainToggled: (domain, isEnabled) =>
            _onDefaultDomainToggled(domain, isEnabled, emit),
        customRuleToggled: (rule) => _onCustomRuleToggled(rule, emit),
        customRuleDeleteRequested: (id, completer) =>
            _onCustomRuleDeleteRequested(id, completer, emit),
        customRuleAddRequested: (domain, isBlocked, completer) =>
            _onCustomRuleAddRequested(domain, isBlocked, completer, emit),
        actionErrorDismissed: () async => _onActionErrorDismissed(emit),
      );
    });
  }

  Future<void> _onStarted(Emitter<BlocklistState> emit) async {
    await Future.wait([
      _fetchDefaultDomainOverrides(emit),
      _fetchCustomRules(emit),
    ]);
  }

  Future<void> _fetchDefaultDomainOverrides(
    Emitter<BlocklistState> emit,
  ) async {
    emit(state.copyWith(isLoadingOverrides: true, overridesError: null));

    try {
      final overrides = await _repository.getDefaultDomainOverrides();
      emit(
        state.copyWith(
          disabledDefaultDomains: overrides,
          isLoadingOverrides: false,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isLoadingOverrides: false,
          overridesError: 'Failed to load default domain overrides: $e',
        ),
      );
    }
  }

  Future<void> _fetchCustomRules(Emitter<BlocklistState> emit) async {
    final int requestId = ++_activeRuleRequestId;
    emit(state.copyWith(isLoadingRules: true, rulesError: null));

    try {
      final rules = await _repository.getRules();
      if (requestId != _activeRuleRequestId) return;

      if (rules == null) {
        emit(
          state.copyWith(
            isLoadingRules: false,
            rulesError: 'Failed to read firewall rules from storage.',
          ),
        );
        return;
      }

      emit(state.copyWith(customRules: rules, isLoadingRules: false));
    } catch (e) {
      if (requestId != _activeRuleRequestId) return;
      emit(
        state.copyWith(
          isLoadingRules: false,
          rulesError: 'Failed to load rules: $e',
        ),
      );
    }
  }

  Future<void> _onDefaultDomainToggled(
    String domain,
    bool isEnabled,
    Emitter<BlocklistState> emit,
  ) async {
    final previousOverrides = Set<String>.from(state.disabledDefaultDomains);
    final updated = Set<String>.from(state.disabledDefaultDomains);
    if (isEnabled) {
      updated.remove(domain);
    } else {
      updated.add(domain);
    }

    emit(state.copyWith(disabledDefaultDomains: updated, actionError: null));

    try {
      final resultSet = await _repository.toggleDefaultDomain(
        domain: domain,
        isEnabled: isEnabled,
      );
      emit(state.copyWith(disabledDefaultDomains: resultSet));
    } catch (e) {
      emit(
        state.copyWith(
          disabledDefaultDomains: previousOverrides,
          actionError: 'Failed to update domain preference: $e',
        ),
      );
    }
  }

  Future<void> _onCustomRuleToggled(
    AuraRuleItem rule,
    Emitter<BlocklistState> emit,
  ) async {
    final previousRules = List<AuraRuleItem>.from(state.customRules);

    try {
      final updated = await _repository.toggleRule(rule.id, !rule.isEnabled);
      final updatedRules = List<AuraRuleItem>.from(state.customRules);
      final index = updatedRules.indexWhere((r) => r.id == rule.id);
      if (index != -1) {
        updatedRules[index] = updated;
      }
      emit(state.copyWith(customRules: updatedRules));
    } catch (e) {
      emit(
        state.copyWith(
          customRules: previousRules,
          actionError: 'Failed to update rule: $e',
        ),
      );
    }
  }

  Future<void> _onCustomRuleDeleteRequested(
    String id,
    Completer<bool>? completer,
    Emitter<BlocklistState> emit,
  ) async {
    final previousRules = List<AuraRuleItem>.from(state.customRules);
    final updatedRules = state.customRules.where((r) => r.id != id).toList();
    emit(state.copyWith(customRules: updatedRules));

    try {
      await _repository.deleteRule(id);
      completer?.complete(true);
    } catch (e) {
      emit(
        state.copyWith(
          customRules: previousRules,
          actionError: 'Failed to delete rule: $e',
        ),
      );
      completer?.complete(false);
    }
  }

  Future<void> _onCustomRuleAddRequested(
    String domain,
    bool isBlocked,
    Completer<bool>? completer,
    Emitter<BlocklistState> emit,
  ) async {
    try {
      final newRule = await _repository.addRule(
        domain: domain,
        isBlocked: isBlocked,
        isEnabled: true,
      );
      final updatedRules = List<AuraRuleItem>.from(state.customRules);
      updatedRules.removeWhere((r) => r.id == newRule.id);
      updatedRules.insert(0, newRule);
      emit(state.copyWith(customRules: updatedRules));
      completer?.complete(true);
    } catch (e) {
      emit(state.copyWith(actionError: 'Failed to add rule: $e'));
      completer?.complete(false);
    }
  }

  void _onActionErrorDismissed(Emitter<BlocklistState> emit) {
    emit(state.copyWith(actionError: null));
  }

  Future<bool> validateDomain(String domain) async {
    await _repository.validateDomain(domain);
    return true;
  }

  Future<bool> addRule({required String domain, required bool isBlocked}) {
    final completer = Completer<bool>();
    add(
      BlocklistEvent.customRuleAddRequested(
        domain: domain,
        isBlocked: isBlocked,
        completer: completer,
      ),
    );
    return completer.future;
  }

  Future<bool> deleteRule(String id) {
    final completer = Completer<bool>();
    add(BlocklistEvent.customRuleDeleteRequested(id: id, completer: completer));
    return completer.future;
  }
}
