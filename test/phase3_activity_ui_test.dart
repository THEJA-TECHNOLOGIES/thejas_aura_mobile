import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theja_aura/main.dart';
import 'package:theja_aura/screens/aura_activity_screen.dart';
import 'package:theja_aura/services/aura_activity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuraActivity Models & Service Unit Tests', () {
    test('DnsActivityRecord correctly parses valid and boundary maps', () {
      final map = <String, dynamic>{
        'id': 42,
        'timestamp': 1700000000000,
        'domain': 'ads.example.com',
        'queryType': 'A',
        'outcome': 'blocked',
        'matchedSource': 'default',
        'matchedRuleId': 'ads.example.com',
        'matchedCategories': ['Ads', 'Trackers'],
        'reason': 'Blocked by Ads',
        'appIdentifier': null,
        'appName': null,
      };

      final record = DnsActivityRecord.fromMap(map);
      expect(record.id, 42);
      expect(record.timestamp, 1700000000000);
      expect(record.domain, 'ads.example.com');
      expect(record.queryType, 'A');
      expect(record.outcome, 'blocked');
      expect(record.matchedSource, 'default');
      expect(record.matchedRuleId, 'ads.example.com');
      expect(record.matchedCategories, ['Ads', 'Trackers']);
      expect(record.reason, 'Blocked by Ads');
      expect(record.appIdentifier, isNull);
      expect(record.appName, isNull);
      expect(record.isBlocked, isTrue);
      expect(record.isAllowed, isFalse);
      expect(record.isFailed, isFalse);
    });

    test('PaginatedActivityResult parses page data and cursors', () {
      final map = <String, dynamic>{
        'records': [
          {
            'id': 1,
            'timestamp': 1000,
            'domain': 'example.com',
            'queryType': 'A',
            'outcome': 'allowed',
          }
        ],
        'hasMore': true,
        'nextCursorTimestamp': 1000,
        'nextCursorId': 1,
      };

      final result = PaginatedActivityResult.fromMap(map);
      expect(result.records.length, 1);
      expect(result.hasMore, isTrue);
      expect(result.nextCursorTimestamp, 1000);
      expect(result.nextCursorId, 1);
    });

    test('DashboardStatsData parses aggregates correctly', () {
      final map = <String, dynamic>{
        'timeWindowMillis': 86400000,
        'startTime': 1000,
        'endTime': 87400000,
        'totalQueries': 500,
        'totalBlocked': 120,
        'totalAllowed': 375,
        'totalFailed': 5,
        'uniqueBlockedDomains': 25,
        'uniqueDomainsTotal': 80,
      };

      final stats = DashboardStatsData.fromMap(map);
      expect(stats.totalQueries, 500);
      expect(stats.totalBlocked, 120);
      expect(stats.totalAllowed, 375);
      expect(stats.totalFailed, 5);
      expect(stats.uniqueBlockedDomains, 25);
      expect(stats.uniqueDomainsTotal, 80);
      expect(stats.blockPercentage, closeTo(24.0, 0.1));
    });

    test('TopBlockedDomainItem parses ranking maps', () {
      final map = <String, dynamic>{'domain': 'doubleclick.net', 'count': 42};
      final item = TopBlockedDomainItem.fromMap(map);
      expect(item.domain, 'doubleclick.net');
      expect(item.count, 42);
    });
  });

  group('AuraActivityScreen Widget Tests', () {
    const MethodChannel activityChannel =
        MethodChannel('com.thejatech.aura/activity');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(activityChannel, null);
    });

    testWidgets('Renders activity records and handles outcome filter chip tap',
        (WidgetTester tester) async {
      String? recordedOutcomeFilter;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(activityChannel, (MethodCall call) async {
        if (call.method == 'getActivity') {
          final args = call.arguments as Map<dynamic, dynamic>? ?? {};
          recordedOutcomeFilter = args['outcome'] as String?;

          return <String, dynamic>{
            'records': [
              {
                'id': 101,
                'timestamp': DateTime.now().millisecondsSinceEpoch - 5000,
                'domain': 'telemetry.apple.com',
                'queryType': 'HTTPS',
                'outcome': 'allowed',
                'reason': 'Allowed: No blocking rule matched',
              },
              {
                'id': 100,
                'timestamp': DateTime.now().millisecondsSinceEpoch - 10000,
                'domain': 'ads.doubleclick.net',
                'queryType': 'A',
                'outcome': 'blocked',
                'matchedSource': 'default',
                'matchedCategories': ['Ads'],
                'reason': 'Blocked by Ads',
              },
            ],
            'hasMore': false,
            'nextCursorTimestamp': null,
            'nextCursorId': null,
          };
        }
        return null;
      });

      await tester.pumpWidget(
        const MaterialApp(home: AuraActivityScreen()),
      );
      await tester.pumpAndSettle();

      // Verify records are rendered
      expect(find.text('telemetry.apple.com'), findsOneWidget);
      expect(find.text('ads.doubleclick.net'), findsOneWidget);
      expect(find.text('Blocked by Ads'), findsOneWidget);

      // Tap the "Blocked" filter chip
      await tester.tap(find.widgetWithText(ChoiceChip, 'Blocked'));
      await tester.pumpAndSettle();

      expect(recordedOutcomeFilter, 'blocked');
    });

    testWidgets('Displays empty state when no activity records exist',
        (WidgetTester tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(activityChannel, (MethodCall call) async {
        if (call.method == 'getActivity') {
          return <String, dynamic>{
            'records': <dynamic>[],
            'hasMore': false,
            'nextCursorTimestamp': null,
            'nextCursorId': null,
          };
        }
        return null;
      });

      await tester.pumpWidget(
        const MaterialApp(home: AuraActivityScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('No DNS activity recorded yet'), findsOneWidget);
    });

    testWidgets('Displays error state with retry on failure',
        (WidgetTester tester) async {
      var callCount = 0;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(activityChannel, (MethodCall call) async {
        if (call.method == 'getActivity') {
          callCount++;
          if (callCount == 1) {
            throw PlatformException(
              code: 'DATABASE_NOT_FOUND',
              message: 'Activity database file not found in App Group container.',
            );
          }
          return <String, dynamic>{
            'records': [
              {
                'id': 1,
                'timestamp': DateTime.now().millisecondsSinceEpoch,
                'domain': 'recovered.com',
                'queryType': 'A',
                'outcome': 'allowed',
              }
            ],
            'hasMore': false,
          };
        }
        return null;
      });

      await tester.pumpWidget(
        const MaterialApp(home: AuraActivityScreen()),
      );
      await tester.pumpAndSettle();

      // Error message shown
      expect(find.textContaining('Failed to load activity'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // Tap Retry
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('recovered.com'), findsOneWidget);
    });

    testWidgets('Search input debounces and queries specific domain',
        (WidgetTester tester) async {
      String? searchedDomain;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(activityChannel, (MethodCall call) async {
        if (call.method == 'getActivity') {
          final args = call.arguments as Map<dynamic, dynamic>? ?? {};
          searchedDomain = args['searchDomain'] as String?;
          return <String, dynamic>{
            'records': <dynamic>[],
            'hasMore': false,
          };
        }
        return null;
      });

      await tester.pumpWidget(
        const MaterialApp(home: AuraActivityScreen()),
      );
      await tester.pumpAndSettle();

      // Enter search term
      await tester.enterText(
          find.byType(TextField), 'google');
      // Wait for debounce (300ms)
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(searchedDomain, 'google');
    });
  });

  group('Dashboard Activity Section Widget Tests', () {
    const MethodChannel controlChannel =
        MethodChannel('com.thejatech.aura/tunnel_control');
    const MethodChannel activityChannel =
        MethodChannel('com.thejatech.aura/activity');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(activityChannel, null);
    });

    testWidgets('Dashboard renders activity aggregates, switches window, and navigates to log screen',
        (WidgetTester tester) async {
      int? requestedWindow;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (MethodCall call) async {
        if (call.method == 'getStatus') return 'connected';
        if (call.method == 'getRules') return <dynamic>[];
        if (call.method == 'syncRules') return true;
        return null;
      });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(activityChannel, (MethodCall call) async {
        if (call.method == 'getDashboardStats') {
          final args = call.arguments as Map<dynamic, dynamic>? ?? {};
          requestedWindow = args['timeWindowMillis'] as int?;

          return <String, dynamic>{
            'timeWindowMillis': requestedWindow ?? 86400000,
            'startTime': 0,
            'endTime': requestedWindow ?? 86400000,
            'totalQueries': 1250,
            'totalBlocked': 342,
            'totalAllowed': 908,
            'totalFailed': 0,
            'uniqueBlockedDomains': 28,
            'uniqueDomainsTotal': 140,
          };
        }
        if (call.method == 'getTopBlockedDomains') {
          return <dynamic>[
            {'domain': 'tracker.analytics.net', 'count': 120},
            {'domain': 'adservice.google.com', 'count': 85},
          ];
        }
        if (call.method == 'getActivity') {
          return <String, dynamic>{
            'records': <dynamic>[],
            'hasMore': false,
          };
        }
        return null;
      });

      await tester.pumpWidget(const AuraApp());
      await tester.pumpAndSettle();

      // Check stats cards render
      expect(find.text('Firewall Activity'), findsOneWidget);
      expect(find.text('342'), findsOneWidget);
      expect(find.text('28 unique domains'), findsOneWidget);
      expect(find.text('908'), findsOneWidget);
      expect(find.text('1250 total requests'), findsOneWidget);
      expect(find.text('tracker.analytics.net'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);

      // Switch time window to 7d
      await tester.ensureVisible(find.text('7d'));
      await tester.tap(find.text('7d'));
      await tester.pumpAndSettle();
      expect(requestedWindow, 7 * 86400000);

      // Tap "View Logs" button
      await tester.ensureVisible(find.text('View Logs'));
      await tester.tap(find.text('View Logs'));
      await tester.pumpAndSettle();

      // Should have navigated to AuraActivityScreen
      expect(find.text('DNS Activity Log'), findsOneWidget);
    });
  });
}
