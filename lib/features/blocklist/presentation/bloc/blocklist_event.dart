import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';

part 'blocklist_event.freezed.dart';

@freezed
abstract class BlocklistEvent with _$BlocklistEvent {
  const factory BlocklistEvent.started() = _BlocklistStarted;
  const factory BlocklistEvent.defaultDomainOverridesRefreshRequested() =
      _BlocklistDefaultDomainOverridesRefreshRequested;
  const factory BlocklistEvent.customRulesRefreshRequested() =
      _BlocklistCustomRulesRefreshRequested;
  const factory BlocklistEvent.defaultDomainToggled({
    required String domain,
    required bool isEnabled,
  }) = _BlocklistDefaultDomainToggled;
  const factory BlocklistEvent.customRuleToggled(AuraRuleItem rule) =
      _BlocklistCustomRuleToggled;
  const factory BlocklistEvent.customRuleDeleteRequested({
    required String id,
    Completer<bool>? completer,
  }) = _BlocklistCustomRuleDeleteRequested;
  const factory BlocklistEvent.customRuleAddRequested({
    required String domain,
    required bool isBlocked,
    Completer<bool>? completer,
  }) = _BlocklistCustomRuleAddRequested;
  const factory BlocklistEvent.actionErrorDismissed() =
      _BlocklistActionErrorDismissed;
}
