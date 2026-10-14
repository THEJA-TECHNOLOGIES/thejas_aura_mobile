class DashboardStats {
  final int blockedToday;
  final int blockedThisWeek;
  final int totalBlockedDomains;

  const DashboardStats({
    required this.blockedToday,
    required this.blockedThisWeek,
    required this.totalBlockedDomains,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DashboardStats &&
          runtimeType == other.runtimeType &&
          blockedToday == other.blockedToday &&
          blockedThisWeek == other.blockedThisWeek &&
          totalBlockedDomains == other.totalBlockedDomains;

  @override
  int get hashCode =>
      Object.hash(blockedToday, blockedThisWeek, totalBlockedDomains);
}
