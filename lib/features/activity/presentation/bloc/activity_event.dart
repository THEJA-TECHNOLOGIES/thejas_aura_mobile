import 'package:freezed_annotation/freezed_annotation.dart';

part 'activity_event.freezed.dart';

@freezed
abstract class ActivityEvent with _$ActivityEvent {
  const factory ActivityEvent.started({@Default(false) bool isLogsMode}) =
      _ActivityStarted;
  const factory ActivityEvent.initialPageRequested() =
      _ActivityInitialPageRequested;
  const factory ActivityEvent.loadMoreRequested() = _ActivityLoadMoreRequested;
  const factory ActivityEvent.refreshRequested() = _ActivityRefreshRequested;
  const factory ActivityEvent.outcomeFilterChanged(String outcome) =
      _ActivityOutcomeFilterChanged;
  const factory ActivityEvent.timeWindowFilterChanged(int? timeWindowMillis) =
      _ActivityTimeWindowFilterChanged;
  const factory ActivityEvent.searchQueryChanged(String query) =
      _ActivitySearchQueryChanged;
  const factory ActivityEvent.appResumed() = _ActivityAppResumed;
  const factory ActivityEvent.domainBlockToggled({
    required String domain,
    required bool isBlocked,
  }) = _ActivityDomainBlockToggled;
  const factory ActivityEvent.actionErrorDismissed() =
      _ActivityActionErrorDismissed;
}
