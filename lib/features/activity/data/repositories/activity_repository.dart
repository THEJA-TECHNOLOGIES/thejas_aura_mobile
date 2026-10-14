import 'package:injectable/injectable.dart';
import 'package:theja_aura/core/services/aura_activity_service.dart';

import '../../domain/repositories/i_activity_repository.dart';

@LazySingleton(as: IActivityRepository)
class ActivityRepository implements IActivityRepository {
  final AuraActivityService _activityService;

  ActivityRepository(this._activityService);

  @override
  Future<PaginatedActivityResult> getActivity({
    int limit = 25,
    int? cursorTimestamp,
    int? cursorId,
    String? outcome,
    String? searchDomain,
    int? startTime,
  }) {
    return _activityService.getActivity(
      limit: limit,
      cursorTimestamp: cursorTimestamp,
      cursorId: cursorId,
      outcome: outcome,
      searchDomain: searchDomain,
      startTime: startTime,
    );
  }

  @override
  Future<bool> checkpoint() {
    return _activityService.checkpoint();
  }

  @override
  Future<DashboardStatsData> getDashboardStats({
    required int timeWindowMillis,
  }) {
    return _activityService.getDashboardStats(
      timeWindowMillis: timeWindowMillis,
    );
  }
}
