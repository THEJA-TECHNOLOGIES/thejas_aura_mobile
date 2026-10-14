import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theja_aura/main.dart';
import 'package:theja_aura/screens/aura_activity_screen.dart';
import 'package:theja_aura/screens/aura_blocklist_screen.dart';
import 'package:theja_aura/core/DI/injection.dart';
import 'package:theja_aura/features/blocklist/presentation/bloc/blocklist_bloc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    if (!getIt.isRegistered<BlocklistBloc>()) {
      await configureDependencies();
    }
  });

  const MethodChannel controlChannel = MethodChannel(
    'com.thejatech.aura/tunnel_control',
  );
  const MethodChannel activityChannel = MethodChannel(
    'com.thejatech.aura/activity',
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(controlChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(activityChannel, null);
  });

  group('Home Screen UI Restructuring & CTAs', () {
    testWidgets(
      'Home screen displays firewall control, 3 CTAs, and 3 statistics',
      (WidgetTester tester) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(controlChannel, (MethodCall call) async {
              if (call.method == 'getStatus') return 'disconnected';
              if (call.method == 'getRules') return <dynamic>[];
              return null;
            });

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(activityChannel, (MethodCall call) async {
              if (call.method == 'getDashboardStats') {
                return <String, dynamic>{
                  'timeWindowMillis': 86400000,
                  'startTime': 0,
                  'endTime': 86400000,
                  'totalQueries': 500,
                  'totalBlocked': 123,
                  'totalAllowed': 377,
                  'totalFailed': 0,
                  'uniqueBlockedDomains': 45,
                  'uniqueDomainsTotal': 120,
                };
              }
              return null;
            });

        await tester.pumpWidget(const AuraApp());
        await tester.pumpAndSettle();

        // Section A: Firewall status
        expect(find.text('Protection Disabled'), findsOneWidget);
        expect(find.text('DISABLED'), findsOneWidget);
        expect(find.text('Enable Firewall'), findsOneWidget);

        // Section B: 3 CTA Buttons in exact order
        expect(find.text('Logs'), findsOneWidget);
        expect(find.text('Live Activity'), findsOneWidget);
        expect(find.text('Blocklist'), findsOneWidget);

        // Section C: 3 Statistics Chips
        expect(find.text('Firewall Statistics'), findsOneWidget);
        expect(find.text('Blocked Today'), findsOneWidget);
        expect(find.text('Blocked This Week'), findsOneWidget);
        expect(find.text('Total Blocked Domains'), findsOneWidget);
        expect(find.text('123'), findsNWidgets(2));
        expect(find.text('45'), findsOneWidget);

        // Ensure no obsolete metrics or selectable chips
        expect(find.text('Allowed Queries'), findsNothing);
        expect(find.text('24h'), findsNothing);
        expect(find.text('7d'), findsNothing);
        expect(find.text('30d'), findsNothing);
      },
    );

    testWidgets('Firewall enable/disable toggling and error handling', (
      WidgetTester tester,
    ) async {
      String currentStatus = 'disconnected';
      bool shouldFail = false;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (MethodCall call) async {
            if (call.method == 'getStatus') return currentStatus;
            if (call.method == 'getRules') return <dynamic>[];
            if (call.method == 'startTunnel') {
              if (shouldFail) {
                throw PlatformException(
                  code: 'START_ERROR',
                  message: 'Failed to start tunnel.',
                );
              }
              currentStatus = 'connected';
              return null;
            }
            return null;
          });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(activityChannel, (MethodCall call) async {
            if (call.method == 'getDashboardStats') {
              return <String, dynamic>{
                'timeWindowMillis': 86400000,
                'startTime': 0,
                'endTime': 86400000,
                'totalQueries': 0,
                'totalBlocked': 0,
                'totalAllowed': 0,
                'totalFailed': 0,
                'uniqueBlockedDomains': 0,
                'uniqueDomainsTotal': 0,
              };
            }
            return null;
          });

      await tester.pumpWidget(const AuraApp());
      await tester.pumpAndSettle();

      // Trigger failure
      shouldFail = true;
      await tester.tap(find.text('Enable Firewall'));
      await tester.pumpAndSettle();

      // Error snackbar should be displayed
      expect(find.textContaining('Tunnel Action Failed'), findsOneWidget);
    });

    testWidgets('Home stats error state displays retry button', (
      WidgetTester tester,
    ) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (MethodCall call) async {
            if (call.method == 'getStatus') return 'disconnected';
            return null;
          });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(activityChannel, (MethodCall call) async {
            if (call.method == 'getDashboardStats') {
              throw PlatformException(
                code: 'STATS_ERROR',
                message: 'DB locked',
              );
            }
            return null;
          });

      await tester.pumpWidget(const AuraApp());
      await tester.pumpAndSettle();

      expect(find.text('Activity stats unavailable'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('Logs Screen (Blocked Only)', () {
    testWidgets(
      'Logs mode queries only blocked events and displays domain + timestamp',
      (WidgetTester tester) async {
        String? queriedOutcome;

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(activityChannel, (MethodCall call) async {
              if (call.method == 'getActivity') {
                final args = call.arguments as Map<dynamic, dynamic>? ?? {};
                queriedOutcome = args['outcome'] as String?;

                return <String, dynamic>{
                  'records': <dynamic>[
                    {
                      'id': 1,
                      'domain': 'ads.evilcorp.com',
                      'timestamp': 1700000000000,
                      'queryType': 'A',
                      'outcome': 'blocked',
                      'matchedSource': 'default',
                    },
                  ],
                  'hasMore': false,
                };
              }
              return null;
            });

        await tester.pumpWidget(
          const MaterialApp(home: AuraActivityScreen(isLogsMode: true)),
        );
        await tester.pumpAndSettle();

        expect(find.text('Blocked DNS Logs'), findsOneWidget);
        expect(queriedOutcome, 'blocked');
        expect(find.text('ads.evilcorp.com'), findsOneWidget);
        expect(find.text('BLOCKED'), findsOneWidget);

        // Outcome filter chips should not be shown in Logs mode
        expect(find.text('All Outcomes'), findsNothing);
        expect(find.text('Allowed'), findsNothing);
      },
    );

    testWidgets('Logs empty state displays appropriate message', (
      WidgetTester tester,
    ) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(activityChannel, (MethodCall call) async {
            if (call.method == 'getActivity') {
              return {'records': <dynamic>[], 'hasMore': false};
            }
            return null;
          });

      await tester.pumpWidget(
        const MaterialApp(home: AuraActivityScreen(isLogsMode: true)),
      );
      await tester.pumpAndSettle();

      expect(find.text('No blocked events recorded yet'), findsOneWidget);
    });
  });

  group('Live Activity Screen (All Outcomes)', () {
    testWidgets('Live Activity mode displays all events and outcome filters', (
      WidgetTester tester,
    ) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(activityChannel, (MethodCall call) async {
            if (call.method == 'getActivity') {
              return <String, dynamic>{
                'records': <dynamic>[
                  {
                    'id': 1,
                    'domain': 'apple.com',
                    'timestamp': 1700000000000,
                    'queryType': 'A',
                    'outcome': 'allowed',
                    'matchedSource': 'none',
                  },
                  {
                    'id': 2,
                    'domain': 'tracker.com',
                    'timestamp': 1700000001000,
                    'queryType': 'A',
                    'outcome': 'blocked',
                    'matchedSource': 'default',
                  },
                ],
                'hasMore': false,
              };
            }
            return null;
          });

      await tester.pumpWidget(
        const MaterialApp(home: AuraActivityScreen(isLogsMode: false)),
      );
      await tester.pumpAndSettle();

      expect(find.text('DNS Activity Log'), findsOneWidget);
      expect(find.text('All Outcomes'), findsOneWidget);
      expect(find.text('Blocked'), findsOneWidget);
      expect(find.text('Allowed'), findsOneWidget);
      expect(find.text('apple.com'), findsOneWidget);
      expect(find.text('tracker.com'), findsOneWidget);
    });
  });

  group('Blocklist Screen Tabs and Operations', () {
    testWidgets('Blocklist Custom Domains tab add, toggle, and delete flow', (
      WidgetTester tester,
    ) async {
      final List<Map<String, dynamic>> rules = [
        {
          'id': 'rule-1',
          'domain': 'custom-block.com',
          'isBlocked': true,
          'isEnabled': true,
        },
      ];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (MethodCall call) async {
            if (call.method == 'getCategories') {
              return {'Ads': true, 'Trackers': true, 'Analytics': true};
            }
            if (call.method == 'getRules') {
              return rules;
            }
            if (call.method == 'toggleRule') {
              final args = call.arguments as Map;
              final isEnabled = args['isEnabled'] as bool;
              return {
                'id': 'rule-1',
                'domain': 'custom-block.com',
                'isBlocked': true,
                'isEnabled': isEnabled,
              };
            }
            if (call.method == 'deleteRule') {
              return {
                'id': 'rule-1',
                'domain': 'custom-block.com',
                'isBlocked': true,
                'isEnabled': true,
              };
            }
            if (call.method == 'validateDomain') {
              return 'new-blocked.com';
            }
            if (call.method == 'addRule') {
              return {
                'id': 'rule-2',
                'domain': 'new-blocked.com',
                'isBlocked': true,
                'isEnabled': true,
              };
            }
            return null;
          });

      await tester.pumpWidget(const MaterialApp(home: AuraBlocklistScreen()));
      await tester.pumpAndSettle();

      // Switch to Custom Domains tab
      await tester.tap(find.text('Custom Domains'));
      await tester.pumpAndSettle();

      expect(find.text('custom-block.com'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);

      // Toggle rule
      final ruleSwitch = find.byType(Switch).first;
      await tester.tap(ruleSwitch);
      await tester.pumpAndSettle();

      // Delete rule: tap delete button -> confirmation dialog -> cancel -> stays
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.text('Delete Rule'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('custom-block.com'), findsOneWidget);

      // Delete rule: tap delete button -> confirm -> deleted
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('custom-block.com'), findsNothing);

      // Add rule flow
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Add Block Rule'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'new-blocked.com');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Add Rule'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('new-blocked.com'), findsOneWidget);
    });

    testWidgets('Blocklist empty custom rules state shows Add Rule button', (
      WidgetTester tester,
    ) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (MethodCall call) async {
            if (call.method == 'getCategories') {
              return {'Ads': true, 'Trackers': true, 'Analytics': true};
            }
            if (call.method == 'getRules') {
              return <dynamic>[];
            }
            return null;
          });

      await tester.pumpWidget(const MaterialApp(home: AuraBlocklistScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Custom Domains'));
      await tester.pumpAndSettle();

      expect(find.text('No Custom Domains'), findsOneWidget);
      expect(find.text('Add Rule'), findsOneWidget);
    });
  });
}
