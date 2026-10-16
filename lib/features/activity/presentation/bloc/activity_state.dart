import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:theja_aura/core/services/aura_activity_service.dart';
import 'package:theja_aura/core/services/aura_domain_evaluator.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';

part 'activity_state.freezed.dart';

@freezed
abstract class ActivityState with _$ActivityState {
  const ActivityState._();

  const factory ActivityState({
    @Default([]) List<DnsActivityRecord> records,
    @Default(false) bool isLoading,
    @Default(false) bool isLoadingMore,
    @Default(false) bool hasMore,
    int? nextCursorTimestamp,
    int? nextCursorId,
    String? errorMessage,
    @Default('all') String selectedOutcome,
    int? selectedTimeWindowMillis,
    @Default('') String searchQuery,
    @Default(false) bool isLogsMode,
    @Default({}) Map<String, bool> effectiveBlockedState,
    @Default({}) Set<String> pendingDomainToggles,
    @Default([]) List<AuraRuleItem> customRules,
    @Default({}) Set<String> disabledDefaultDomains,
    @Default({}) Map<String, bool> categoryPreferences,
    String? actionError,
  }) = _ActivityState;

  /// Returns whether a domain is currently effectively blocked.
  /// Checks explicit effective state map first, evaluates against current rules,
  /// or falls back to record's outcome if rules are not yet ready.
  bool isDomainBlocked(String domain, [DnsActivityRecord? record]) {
    final normalized = AuraDomainEvaluator.normalizeDomain(domain);
    if (effectiveBlockedState.containsKey(normalized)) {
      return effectiveBlockedState[normalized]!;
    }
    DnsActivityRecord? matched = record;
    if (matched == null) {
      for (final r in records) {
        if (AuraDomainEvaluator.normalizeDomain(r.domain) == normalized) {
          matched = r;
          break;
        }
      }
    }
    return AuraDomainEvaluator.isEffectivelyBlocked(
      domain: normalized,
      customRules: customRules,
      disabledDefaultDomains: disabledDefaultDomains,
      categoryPreferences: categoryPreferences,
      fallback: matched?.isBlocked ?? false,
    );
  }
}
