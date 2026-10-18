class DashboardStats {
  final int blockedToday;
  final int blockedThisWeek;
  final int totalBlockedDomains;
  final int? uniqueBlockedDomains;
  final int? uniqueDomainsTotal;

  const DashboardStats({
    required this.blockedToday,
    required this.blockedThisWeek,
    required this.totalBlockedDomains,
    this.uniqueBlockedDomains,
    this.uniqueDomainsTotal,
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
          uniqueDomainsTotal == other.uniqueDomainsTotal;

  @override
  int get hashCode => Object.hash(
        blockedToday,
        blockedThisWeek,
        totalBlockedDomains,
        uniqueBlockedDomains,
        uniqueDomainsTotal,
      );
}
