class IndividualBar {
  final DateTime timestamp;
  final int blockedCount;

  const IndividualBar({required this.timestamp, required this.blockedCount});

  /// Numeric X-axis position used by fl_chart.
  int get x => timestamp.millisecondsSinceEpoch;

  /// Numeric Y-axis value representing blocked domains.
  double get y => blockedCount.toDouble();
}
