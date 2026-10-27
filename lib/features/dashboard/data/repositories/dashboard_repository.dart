import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:theja_aura/core/services/aura_activity_service.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';

import '../../domain/models/dashboard_stats.dart';
import '../../domain/repositories/i_dashboard_repository.dart';
import '../../presentation/pages/widgets/bar_chart/individual_bar.dart';

@LazySingleton(as: IDashboardRepository)
class DashboardRepository implements IDashboardRepository {
  final AuraTunnelService _tunnelService;
  final AuraActivityService _activityService;

  DashboardRepository(this._tunnelService, this._activityService);

  @override
  Stream<TunnelStatus> get tunnelStatusStream => _tunnelService.statusStream;

  @override
  Future<TunnelStatus> getTunnelStatus() => _tunnelService.getStatus();

  @override
  Future<void> startTunnel() => _tunnelService.startTunnel();

  @override
  Future<void> stopTunnel() => _tunnelService.stopTunnel();

  @override
  Future<DashboardStats> getDashboardStats() async {
    final now = DateTime.now();

    // 1. Blocked Today: start of local calendar day
    final startOfToday = DateTime(now.year, now.month, now.day);
    final millisToday = now.difference(startOfToday).inMilliseconds;

    // 2. Blocked This Week: start of local calendar week (Monday)
    final startOfWeek = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final millisThisWeek = now.difference(startOfWeek).inMilliseconds;

    // 3. All-Time Logs: total persisted DNS activity log records across all retained history
    // Passing 0 requests an unbounded all-time query without date restrictions.
    const millisAllTime = 0;

    // 4. Rolling 7 calendar days ending today (inclusive)
    final startOf7Days = DateTime(
      startOfToday.year,
      startOfToday.month,
      startOfToday.day - 6,
    );
    final startOf7DaysMillis = startOf7Days.millisecondsSinceEpoch;
    final endOfRangeMillis = now.millisecondsSinceEpoch;

    final results = await Future.wait([
      _activityService.getDashboardStats(timeWindowMillis: millisToday),
      _activityService.getDashboardStats(timeWindowMillis: millisThisWeek),
      _activityService.getDashboardStats(timeWindowMillis: millisAllTime),
      _activityService.getDailyBlockedActivity(
        startTime: startOf7DaysMillis,
        endTime: endOfRangeMillis,
      ),
    ]);

    final dailyRawList = results[3] as List<Map<String, dynamic>>;
    final dailyMap = <String, int>{};
    for (final entry in dailyRawList) {
      final day = entry['day'] as String?;
      final count = (entry['count'] as num?)?.toInt() ?? 0;
      if (day != null) {
        dailyMap[day] = count;
      }
    }

    final dailySeries = <IndividualBar>[];
    for (int i = 0; i < 7; i++) {
      final dayDate = DateTime(
        startOfToday.year,
        startOfToday.month,
        startOfToday.day - (6 - i),
      );
      final key =
          '${dayDate.year.toString().padLeft(4, '0')}-${dayDate.month.toString().padLeft(2, '0')}-${dayDate.day.toString().padLeft(2, '0')}';
      dailySeries.add(
        IndividualBar(
          timestamp: dayDate,
          blockedCount: dailyMap[key] ?? 0,
        ),
      );
    }

    final statsToday = results[0] as DashboardStatsData;
    final statsThisWeek = results[1] as DashboardStatsData;
    final statsAllTime = results[2] as DashboardStatsData;

    return DashboardStats(
      blockedToday: statsToday.totalBlocked,
      blockedThisWeek: statsThisWeek.totalBlocked,
      totalBlockedDomains: statsAllTime.totalQueries,
      uniqueBlockedDomains: statsAllTime.uniqueBlockedDomains,
      uniqueDomainsTotal: statsAllTime.uniqueDomainsTotal,
      dailyBlockedActivity: dailySeries,
    );
  }

  @override
  Future<String> getTunnelDiagnostics() => _tunnelService.getDiagnostics();

  @override
  Future<bool> clearTunnelDiagnostics() => _tunnelService.clearDiagnostics();

  @override
  Future<VpnPolicy> getVpnPolicy() => _tunnelService.getVpnPolicy();

  @override
  Future<void> pauseTunnel(Duration duration) =>
      _tunnelService.pauseTunnel(duration);

  @override
  Future<void> shutdownTunnel() => _tunnelService.shutdownTunnel();

  @override
  Future<bool> isAlwaysOnActive() => _tunnelService.isAlwaysOnActive();

  @override
  Future<void> openVpnSettings() => _tunnelService.openVpnSettings();
}
