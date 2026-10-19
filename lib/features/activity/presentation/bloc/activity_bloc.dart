import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:theja_aura/core/services/aura_activity_service.dart';
import 'package:theja_aura/core/services/aura_domain_evaluator.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';
import 'package:theja_aura/features/blocklist/domain/repositories/i_blocklist_repository.dart';

import '../../domain/repositories/i_activity_repository.dart';
import 'activity_event.dart';
import 'activity_state.dart';

export 'activity_event.dart';
export 'activity_state.dart';

@injectable
class ActivityBloc extends Bloc<ActivityEvent, ActivityState> {
  final IActivityRepository _repository;
  final IBlocklistRepository _blocklistRepository;
  int _activeRequestId = 0;
  Timer? _searchDebounceTimer;

  ActivityBloc(this._repository, this._blocklistRepository)
    : super(const ActivityState()) {
    on<ActivityEvent>((event, emit) async {
      await event.when(
        started: (isLogsMode) => _onStarted(isLogsMode, emit),
        initialPageRequested: () => _onInitialPageRequested(emit),
        loadMoreRequested: () => _onLoadMoreRequested(emit),
        refreshRequested: () => _onRefreshRequested(emit),
        outcomeFilterChanged: (outcome) => _onOutcomeChanged(outcome, emit),
        timeWindowFilterChanged: (timeWindowMillis) =>
            _onTimeWindowChanged(timeWindowMillis, emit),
        searchQueryChanged: (query) => _onSearchChanged(query, emit),
        appResumed: () => _onAppResumed(emit),
        domainBlockToggled: (domain, isBlocked) =>
            _onDomainBlockToggled(domain, isBlocked, emit),
        actionErrorDismissed: () => _onActionErrorDismissed(emit),
      );
    });
  }

  int? get _startTimeForFilter {
    if (state.selectedTimeWindowMillis == null) return null;
    return DateTime.now().toUtc().millisecondsSinceEpoch -
        state.selectedTimeWindowMillis!;
  }

  Future<void> _fetchRuleData(Emitter<ActivityState> emit) async {
    try {
      final results = await Future.wait([
        _blocklistRepository.getRules(),
        _blocklistRepository.getDefaultDomainOverrides(),
        _blocklistRepository.getCategories(),
      ]);

      final rules = results[0] as List<AuraRuleItem>? ?? state.customRules;
      final overrides =
          results[1] as Set<String>? ?? state.disabledDefaultDomains;
      final prefs =
          results[2] as Map<String, bool>? ?? state.categoryPreferences;

      emit(
        state.copyWith(
          customRules: rules,
          disabledDefaultDomains: overrides,
          categoryPreferences: prefs,
        ),
      );
    } catch (_) {
      // Retain existing state on background rule fetch failure
    }
  }

  Map<String, bool> _computeEffectiveBlockedForRecords(
    List records, {
    List<AuraRuleItem>? rules,
    Set<String>? overrides,
    Map<String, bool>? prefs,
  }) {
    final activeRules = rules ?? state.customRules;
    final activeOverrides = overrides ?? state.disabledDefaultDomains;
    final activePrefs = prefs ?? state.categoryPreferences;

    final effectiveMap = <String, bool>{};
    for (final record in records) {
      final domain = record.domain as String;
      final norm = AuraDomainEvaluator.normalizeDomain(domain);
      effectiveMap[norm] = AuraDomainEvaluator.isEffectivelyBlocked(
        domain: norm,
        customRules: activeRules,
        disabledDefaultDomains: activeOverrides,
        categoryPreferences: activePrefs,
        fallback: record.isBlocked as bool? ?? false,
      );
    }
    return effectiveMap;
  }

  Future<void> _onStarted(bool isLogsMode, Emitter<ActivityState> emit) async {
    emit(
      state.copyWith(
        isLogsMode: isLogsMode,
        selectedOutcome: isLogsMode ? 'blocked' : 'all',
      ),
    );
    await _fetchRuleData(emit);
    await _fetchInitialPage(emit);
  }

  Future<void> _onInitialPageRequested(Emitter<ActivityState> emit) async {
    await _fetchInitialPage(emit);
  }

  Future<void> _fetchInitialPage(Emitter<ActivityState> emit) async {
    final int requestId = ++_activeRequestId;
    emit(state.copyWith(isLoading: true, errorMessage: null));

    final outcomeQuery = state.isLogsMode
        ? 'blocked'
        : (state.selectedOutcome == 'all' ? null : state.selectedOutcome);

    try {
      final result = await _repository.getActivity(
        limit: 25,
        outcome: outcomeQuery,
        searchDomain: state.searchQuery.isEmpty ? null : state.searchQuery,
        startTime: _startTimeForFilter,
      );

      if (requestId != _activeRequestId) return;

      final effectiveMap = _computeEffectiveBlockedForRecords(result.records);

      emit(
        state.copyWith(
          records: [
            ...result.records,
            // DnsActivityRecord(
            //   id: 4657,
            //   domain: "domain kdjfvidf jdf kjdfdkjfnjd fknvndfnkdfkdnlkfnvlkdnvflkndvlkndl",
            //   timestamp: 233546,
            //   queryType: "AAAA",
            //   outcome: "outcome",
            //   matchedSource: "matchedSource",
            // ),
          ],
          effectiveBlockedState: {
            ...state.effectiveBlockedState,
            ...effectiveMap,
          },
          hasMore: result.hasMore,
          nextCursorTimestamp: result.nextCursorTimestamp,
          nextCursorId: result.nextCursorId,
          isLoading: false,
        ),
      );
    } catch (e) {
      if (requestId != _activeRequestId) return;
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to load activity: $e',
        ),
      );
    }
  }

  Future<void> _onLoadMoreRequested(Emitter<ActivityState> emit) async {
    if (!state.hasMore ||
        state.isLoadingMore ||
        state.nextCursorTimestamp == null ||
        state.nextCursorId == null) {
      return;
    }

    final int requestId = _activeRequestId;
    emit(state.copyWith(isLoadingMore: true));

    final outcomeQuery = state.isLogsMode
        ? 'blocked'
        : (state.selectedOutcome == 'all' ? null : state.selectedOutcome);

    try {
      final result = await _repository.getActivity(
        limit: 25,
        cursorTimestamp: state.nextCursorTimestamp,
        cursorId: state.nextCursorId,
        outcome: outcomeQuery,
        searchDomain: state.searchQuery.isEmpty ? null : state.searchQuery,
        startTime: _startTimeForFilter,
      );

      if (requestId != _activeRequestId) return;

      final effectiveMap = _computeEffectiveBlockedForRecords(result.records);

      emit(
        state.copyWith(
          records: [...state.records, ...result.records],
          effectiveBlockedState: {
            ...state.effectiveBlockedState,
            ...effectiveMap,
          },
          hasMore: result.hasMore,
          nextCursorTimestamp: result.nextCursorTimestamp,
          nextCursorId: result.nextCursorId,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      if (requestId != _activeRequestId) return;
      emit(state.copyWith(isLoadingMore: false));
    }
  }

  Future<void> _onDomainBlockToggled(
    String domain,
    bool requestedBlocked,
    Emitter<ActivityState> emit,
  ) async {
    final normalized = AuraDomainEvaluator.normalizeDomain(domain);
    if (normalized.isEmpty) return;

    // Prevent rapid repeated clicks or concurrent conflicting updates for the same domain
    if (state.pendingDomainToggles.contains(normalized)) return;

    final currentBlocked = state.isDomainBlocked(normalized);
    if (currentBlocked == requestedBlocked) return;

    // 1. Optimistic update
    final previousEffective = Map<String, bool>.from(
      state.effectiveBlockedState,
    );
    final updatedEffective = Map<String, bool>.from(
      state.effectiveBlockedState,
    );
    updatedEffective[normalized] = requestedBlocked;

    final pending = Set<String>.from(state.pendingDomainToggles)
      ..add(normalized);
    emit(
      state.copyWith(
        effectiveBlockedState: updatedEffective,
        pendingDomainToggles: pending,
        actionError: null,
      ),
    );

    try {
      if (requestedBlocked) {
        // User wants to BLOCK the domain
        await _applyBlockDomain(normalized);
      } else {
        // User wants to ALLOW/UNBLOCK the domain
        await _applyAllowDomain(normalized);
      }

      // Re-fetch fresh rules and overrides from persistence
      final rules = await _blocklistRepository.getRules() ?? state.customRules;
      final overrides = await _blocklistRepository.getDefaultDomainOverrides();
      final prefs = await _blocklistRepository.getCategories();

      // Recalculate effective state for the updated domain and existing records
      final newEffective = Map<String, bool>.from(state.effectiveBlockedState);
      newEffective[normalized] = AuraDomainEvaluator.isEffectivelyBlocked(
        domain: normalized,
        customRules: rules,
        disabledDefaultDomains: overrides,
        categoryPreferences: prefs,
      );

      final updatedPending = Set<String>.from(state.pendingDomainToggles)
        ..remove(normalized);

      emit(
        state.copyWith(
          customRules: rules,
          disabledDefaultDomains: overrides,
          categoryPreferences: prefs,
          effectiveBlockedState: newEffective,
          pendingDomainToggles: updatedPending,
        ),
      );
    } catch (e) {
      // Rollback optimistic update on failure
      final updatedPending = Set<String>.from(state.pendingDomainToggles)
        ..remove(normalized);

      emit(
        state.copyWith(
          effectiveBlockedState: previousEffective,
          pendingDomainToggles: updatedPending,
          actionError: 'Failed to update domain preference: $e',
        ),
      );
    }
  }

  Future<void> _applyBlockDomain(String normalized) async {
    // 1. If an active custom ALLOW rule exists for this domain, remove it
    final existingAllowRule = state.customRules.firstWhereOrNull(
      (r) =>
          AuraDomainEvaluator.normalizeDomain(r.domain) == normalized &&
          !r.isBlocked &&
          r.isEnabled,
    );
    if (existingAllowRule != null) {
      await _blocklistRepository.deleteRule(existingAllowRule.id);
    }

    // 2. If it was disabled in default domain overrides, re-enable it
    if (state.disabledDefaultDomains.contains(normalized)) {
      await _blocklistRepository.toggleDefaultDomain(
        domain: normalized,
        isEnabled: true,
      );
    }

    // Refresh rules to check if domain is now effectively blocked
    final currentRules =
        await _blocklistRepository.getRules() ?? state.customRules;
    final currentOverrides = await _blocklistRepository
        .getDefaultDomainOverrides();
    final currentPrefs = state.categoryPreferences;

    final isNowBlocked = AuraDomainEvaluator.isEffectivelyBlocked(
      domain: normalized,
      customRules: currentRules,
      disabledDefaultDomains: currentOverrides,
      categoryPreferences: currentPrefs,
    );

    if (!isNowBlocked) {
      // Add custom BLOCK rule
      await _blocklistRepository.addRule(domain: normalized, isBlocked: true);
    }
  }

  Future<void> _applyAllowDomain(String normalized) async {
    // 1. If an exact custom BLOCK rule exists for this domain, delete it
    final existingBlockRule = state.customRules.firstWhereOrNull(
      (r) =>
          AuraDomainEvaluator.normalizeDomain(r.domain) == normalized &&
          r.isBlocked,
    );
    if (existingBlockRule != null) {
      await _blocklistRepository.deleteRule(existingBlockRule.id);
    }

    // 2. Disable it in default domain overrides in case it is part of an active category
    try {
      await _blocklistRepository.toggleDefaultDomain(
        domain: normalized,
        isEnabled: false,
      );
    } catch (_) {}

    // Check if it is STILL effectively blocked (e.g. matched by parent category domain or parent custom rule)
    final currentRules =
        await _blocklistRepository.getRules() ?? state.customRules;
    final currentOverrides = await _blocklistRepository
        .getDefaultDomainOverrides();
    final currentPrefs = state.categoryPreferences;

    final stillBlocked = AuraDomainEvaluator.isEffectivelyBlocked(
      domain: normalized,
      customRules: currentRules,
      disabledDefaultDomains: currentOverrides,
      categoryPreferences: currentPrefs,
    );

    if (stillBlocked) {
      // Must add a custom ALLOW override to bypass category or parent blocking
      await _blocklistRepository.addRule(domain: normalized, isBlocked: false);
    }
  }

  Future<void> _onActionErrorDismissed(Emitter<ActivityState> emit) async {
    emit(state.copyWith(actionError: null));
  }

  Future<void> _onOutcomeChanged(
    String outcome,
    Emitter<ActivityState> emit,
  ) async {
    if (state.selectedOutcome == outcome) return;
    emit(state.copyWith(selectedOutcome: outcome));
    await _fetchInitialPage(emit);
  }

  Future<void> _onTimeWindowChanged(
    int? timeWindowMillis,
    Emitter<ActivityState> emit,
  ) async {
    if (state.selectedTimeWindowMillis == timeWindowMillis) return;
    emit(state.copyWith(selectedTimeWindowMillis: timeWindowMillis));
    await _fetchInitialPage(emit);
  }

  Future<void> _onSearchChanged(
    String query,
    Emitter<ActivityState> emit,
  ) async {
    final trimmed = query.trim();
    if (state.searchQuery == trimmed) return;

    emit(state.copyWith(searchQuery: trimmed));
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 350), () {
      add(const ActivityEvent.initialPageRequested());
    });
  }

  Future<void> _onRefreshRequested(Emitter<ActivityState> emit) async {
    await _fetchRuleData(emit);
    await _fetchInitialPage(emit);
  }

  Future<void> _onAppResumed(Emitter<ActivityState> emit) async {
    await _fetchRuleData(emit);
    await _fetchInitialPage(emit);
  }

  @override
  Future<void> close() {
    _searchDebounceTimer?.cancel();
    return super.close();
  }
}

extension _IterableFirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T element) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
