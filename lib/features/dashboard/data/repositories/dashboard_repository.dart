import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:theja_aura/core/services/aura_activity_service.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';

import '../../domain/models/dashboard_stats.dart';
import '../../domain/repositories/i_dashboard_repository.dart';

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

    final results = await Future.wait([
      _activityService.getDashboardStats(timeWindowMillis: millisToday),
      _activityService.getDashboardStats(timeWindowMillis: millisThisWeek),
      _activityService.getDashboardStats(timeWindowMillis: millisAllTime),
    ]);

    return DashboardStats(
      blockedToday: results[0].totalBlocked,
      blockedThisWeek: results[1].totalBlocked,
      totalBlockedDomains: results[2].totalQueries,
      uniqueBlockedDomains: results[2].uniqueBlockedDomains,
      uniqueDomainsTotal: results[2].uniqueDomainsTotal,
    );
  }
}
