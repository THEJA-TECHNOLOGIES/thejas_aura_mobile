import 'package:theja_aura/core/services/aura_activity_service.dart';

abstract class IActivityRepository {
  Future<PaginatedActivityResult> getActivity({
    int limit = 25,
    int? cursorTimestamp,
    int? cursorId,
    String? outcome,
    String? searchDomain,
    int? startTime,
  });

  Future<bool> initializeDatabase({bool force = false});

  Future<bool> checkpoint();

  Future<DashboardStatsData> getDashboardStats({required int timeWindowMillis});
}
