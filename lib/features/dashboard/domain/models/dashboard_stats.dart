import 'package:flutter/foundation.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/bar_chart/individual_bar.dart';

class DashboardStats {
  final int blockedToday;
  final int blockedThisWeek;
  final int totalBlockedDomains;
  final int? uniqueBlockedDomains;
  final int? uniqueDomainsTotal;
  final List<IndividualBar> dailyBlockedActivity;

  const DashboardStats({
    required this.blockedToday,
    required this.blockedThisWeek,
    required this.totalBlockedDomains,
    this.uniqueBlockedDomains,
    this.uniqueDomainsTotal,
    this.dailyBlockedActivity = const [],
  });

  /// Alias for the all-time persisted activity logs count.
  int get allTimeLogs => totalBlockedDomains;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DashboardStats &&
          runtimeType == other.runtimeType &&
          blockedToday == other.blockedToday &&
          blockedThisWeek == other.blockedThisWeek &&
          totalBlockedDomains == other.totalBlockedDomains &&
          uniqueBlockedDomains == other.uniqueBlockedDomains &&
          uniqueDomainsTotal == other.uniqueDomainsTotal &&
          listEquals(dailyBlockedActivity, other.dailyBlockedActivity);

  @override
  int get hashCode => Object.hash(
        blockedToday,
        blockedThisWeek,
        totalBlockedDomains,
        uniqueBlockedDomains,
        uniqueDomainsTotal,
        Object.hashAll(dailyBlockedActivity),
      );
}
