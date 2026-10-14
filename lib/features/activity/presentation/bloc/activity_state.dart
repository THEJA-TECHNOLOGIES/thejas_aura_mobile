import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:theja_aura/core/services/aura_activity_service.dart';

part 'activity_state.freezed.dart';

@freezed
abstract class ActivityState with _$ActivityState {
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
  }) = _ActivityState;
}
