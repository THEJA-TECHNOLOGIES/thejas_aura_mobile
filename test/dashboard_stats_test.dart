import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theja_aura/core/services/aura_activity_service.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';
import 'package:theja_aura/features/dashboard/data/repositories/dashboard_repository.dart';
import 'package:theja_aura/features/dashboard/domain/models/dashboard_stats.dart';

class FakeTunnelService extends Fake implements AuraTunnelService {
  @override
  Stream<TunnelStatus> get statusStream => Stream.value(TunnelStatus.connected);

  @override
  Future<TunnelStatus> getStatus() async => TunnelStatus.connected;

  @override
  Future<void> startTunnel() async {}

  @override
  Future<void> stopTunnel() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const activityChannel = MethodChannel('com.thejatech.aura/activity');
  late AuraActivityService activityService;
  late FakeTunnelService tunnelService;
  late DashboardRepository repository;
  late List<MethodCall> methodCalls;

  // Simulated in-memory DNS activity records
  // 3 requests for google.com, 2 for youtube.com, 1 for example.com
  final List<Map<String, dynamic>> simulatedRecords = [
    {
      'id': 1,
      'domain': 'google.com',
      'timestamp': 1000,
      'queryType': 'A',
      'outcome': 'blocked',
      'matchedSource': 'custom',
    },
    {
      'id': 2,
      'domain': 'google.com',
      'timestamp': 2000,
      'queryType': 'A',
      'outcome': 'blocked',
      'matchedSource': 'custom',
    },
    {
      'id': 3,
      'domain': 'google.com',
      'timestamp': 3000,
      'queryType': 'AAAA',
      'outcome': 'allowed',
      'matchedSource': 'none',
    },
    {
      'id': 4,
      'domain': 'youtube.com',
      'timestamp': 4000,
      'queryType': 'A',
      'outcome': 'blocked',
      'matchedSource': 'custom',
    },
    {
      'id': 5,
      'domain': 'youtube.com',
      'timestamp': 5000,
      'queryType': 'A',
      'outcome': 'blocked',
      'matchedSource': 'custom',
    },
    {
      'id': 6,
      'domain': 'example.com',
      'timestamp': 6000,
      'queryType': 'A',
      'outcome': 'allowed',
      'matchedSource': 'none',
    },
  ];

  setUp(() {
    methodCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(activityChannel, (MethodCall call) async {
      methodCalls.add(call);

      switch (call.method) {
        case 'initializeDatabase':
          return {'ready': true, 'databaseFileName': 'dns_activity.sqlite'};

        case 'getDashboardStats':
          final args = call.arguments as Map<dynamic, dynamic>? ?? {};
          final timeWindow = (args['timeWindowMillis'] as num?)?.toInt() ?? 0;

          // If timeWindow <= 0, genuine all-time query without timestamp restrictions
          final filtered = timeWindow <= 0
              ? simulatedRecords
              : simulatedRecords.where((r) {
                  // In actual SQLite: timestamp >= (endTime - timeWindow)
                  // For the test setup, treat positive window as filtered
                  return (r['timestamp'] as int) >= 3000;
                }).toList();

          final totalQueries = filtered.length;
          final totalBlocked =
              filtered.where((r) => r['outcome'] == 'blocked').length;
          final totalAllowed =
              filtered.where((r) => r['outcome'] == 'allowed').length;
          final uniqueDomainsTotal =
              filtered.map((r) => r['domain'] as String).toSet().length;
          final uniqueBlockedDomains = filtered
              .where((r) => r['outcome'] == 'blocked')
              .map((r) => r['domain'] as String)
              .toSet()
              .length;

          return {
            'timeWindowMillis': timeWindow,
            'startTime': timeWindow <= 0 ? 0 : 3000,
            'endTime': 6000,
            'totalQueries': totalQueries,
            'totalBlocked': totalBlocked,
            'totalAllowed': totalAllowed,
            'totalFailed': 0,
            'uniqueBlockedDomains': uniqueBlockedDomains,
            'uniqueDomainsTotal': uniqueDomainsTotal,
          };

        default:
          return null;
      }
    });

    activityService = AuraActivityService();
    tunnelService = FakeTunnelService();
    repository = DashboardRepository(tunnelService, activityService);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(activityChannel, null);
  });

  group('Dashboard All-Time Logs Statistic', () {
    test(
      'counts all persisted DNS activity log records (including repeated requests) and preserves unique-domain count',
      () async {
        final DashboardStats stats = await repository.getDashboardStats();

        // 1. Verify All-Time Logs count = 6 (google.com x 3, youtube.com x 2, example.com x 1)
        expect(
          stats.totalBlockedDomains,
          6,
          reason: 'All-Time Logs must count all persisted records (COUNT(*))',
        );
        expect(
          stats.allTimeLogs,
          6,
          reason: 'allTimeLogs getter must equal totalBlockedDomains',
        );

        // 2. Verify unique domains count = 3 (google.com, youtube.com, example.com)
        expect(
          stats.uniqueDomainsTotal,
          3,
          reason: 'Unique domains count must measure distinct domain values (COUNT(DISTINCT domain))',
        );

        // 3. Verify unique blocked domains count = 2 (google.com, youtube.com)
        expect(
          stats.uniqueBlockedDomains,
          2,
          reason: 'Unique blocked domains must measure distinct blocked domains',
        );

        // 4. Verify native call passed timeWindowMillis: 0 for unbounded all-time query
        final statCalls =
            methodCalls.where((c) => c.method == 'getDashboardStats').toList();
        expect(statCalls.length, 3);
        final allTimeCall = statCalls.firstWhere(
          (c) => (c.arguments as Map)['timeWindowMillis'] == 0,
        );
        expect(allTimeCall, isNotNull);
      },
    );
  });
}
