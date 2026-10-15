import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theja_aura/core/services/aura_activity_service.dart';
import 'package:theja_aura/features/activity/data/repositories/activity_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const activityChannel = MethodChannel('com.thejatech.aura/activity');
  late AuraActivityService service;
  late ActivityRepository repository;
  late List<MethodCall> methodCalls;

  setUp(() {
    methodCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(activityChannel, (MethodCall call) async {
          methodCalls.add(call);

          switch (call.method) {
            case 'initializeDatabase':
              return {'ready': true, 'databaseFileName': 'dns_activity.sqlite'};
            case 'getDashboardStats':
              return {
                'timeWindowMillis': 86400000,
                'startTime': 0,
                'endTime': 1000,
                'totalQueries': 0,
                'totalBlocked': 0,
                'totalAllowed': 0,
                'totalFailed': 0,
                'uniqueBlockedDomains': 0,
                'uniqueDomainsTotal': 0,
              };
            case 'getActivity':
              return {'records': [], 'hasMore': false};
            case 'getTopBlockedDomains':
              return [];
            case 'checkpoint':
              return true;
            default:
              return null;
          }
        });

    service = AuraActivityService();
    repository = ActivityRepository(service);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(activityChannel, null);
  });

  group('AuraActivityService Database Bootstrap', () {
    test(
      'initializeDatabase calls native platform channel and marks ready',
      () async {
        expect(service.isDatabaseReady, isFalse);

        final result = await service.initializeDatabase();

        expect(result, isTrue);
        expect(service.isDatabaseReady, isTrue);
        expect(
          methodCalls.where((c) => c.method == 'initializeDatabase').length,
          1,
        );
      },
    );

    test(
      'initializeDatabase deduplicates simultaneous concurrent invocations',
      () async {
        expect(service.isDatabaseReady, isFalse);

        final futures = await Future.wait([
          service.initializeDatabase(),
          service.initializeDatabase(),
          service.initializeDatabase(),
        ]);

        expect(futures, [true, true, true]);
        expect(service.isDatabaseReady, isTrue);
        // Native channel must be called exactly once due to in-flight deduplication
        expect(
          methodCalls.where((c) => c.method == 'initializeDatabase').length,
          1,
        );
      },
    );

    test('subsequent initializeDatabase calls return true immediately without invoking channel again', () async {
      await service.initializeDatabase();
      expect(
        methodCalls.where((c) => c.method == 'initializeDatabase').length,
        1,
      );

      final secondResult = await service.initializeDatabase();
      expect(secondResult, isTrue);
      expect(
        methodCalls.where((c) => c.method == 'initializeDatabase').length,
        1,
      );
    });

    test('force=true invokes channel again even if already ready', () async {
      await service.initializeDatabase();
      expect(
        methodCalls.where((c) => c.method == 'initializeDatabase').length,
        1,
      );

      final forcedResult = await service.initializeDatabase(force: true);
      expect(forcedResult, isTrue);
      expect(
        methodCalls.where((c) => c.method == 'initializeDatabase').length,
        2,
      );
    });

    test(
      'queries automatically trigger initializeDatabase if not yet ready',
      () async {
        expect(service.isDatabaseReady, isFalse);

        final stats = await service.getDashboardStats();

        expect(stats.totalQueries, 0);
        expect(stats.totalBlocked, 0);
        expect(stats.totalAllowed, 0);
        expect(service.isDatabaseReady, isTrue);

        // Verify that initializeDatabase was invoked before getDashboardStats
        expect(methodCalls.length, 2);
        expect(methodCalls[0].method, 'initializeDatabase');
        expect(methodCalls[1].method, 'getDashboardStats');
      },
    );

    test('getActivity automatically triggers initializeDatabase', () async {
      expect(service.isDatabaseReady, isFalse);

      final result = await service.getActivity(limit: 10);

      expect(result.records, isEmpty);
      expect(result.hasMore, isFalse);
      expect(service.isDatabaseReady, isTrue);

      expect(methodCalls[0].method, 'initializeDatabase');
      expect(methodCalls[1].method, 'getActivity');
    });
  });

  group('ActivityRepository initializeDatabase', () {
    test(
      'ActivityRepository.initializeDatabase delegates to AuraActivityService',
      () async {
        final res = await repository.initializeDatabase();
        expect(res, isTrue);
        expect(service.isDatabaseReady, isTrue);
        expect(
          methodCalls.where((c) => c.method == 'initializeDatabase').length,
          1,
        );
      },
    );
  });
}
