import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theja_aura/main.dart';
import 'package:theja_aura/screens/aura_rules_screen.dart';
import 'package:theja_aura/services/aura_tunnel_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel controlChannel =
      MethodChannel('com.thejatech.aura/tunnel_control');
  const MethodChannel activityChannel =
      MethodChannel('com.thejatech.aura/activity');

  group('AuraTunnelService Phase 4 Unit Tests', () {
    final List<MethodCall> calls = [];
    late AuraTunnelService service;

    setUp(() {
      calls.clear();
      service = AuraTunnelService();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, null);
    });

    test('validateDomain calls native validator and returns normalized domain',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (MethodCall call) async {
        calls.add(call);
        if (call.method == 'validateDomain') {
          return 'normalized-example.com';
        }
        return null;
      });

      final result =
          await service.validateDomain('  HTTPS://NORMALIZED-EXAMPLE.COM/  ');
      expect(result, 'normalized-example.com');
      expect(calls.length, 1);
      expect(calls.first.method, 'validateDomain');
      expect(calls.first.arguments, {'domain': '  HTTPS://NORMALIZED-EXAMPLE.COM/  '});
    });

    test('validateDomain parses structured error into AuraRuleException',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (MethodCall call) async {
        if (call.method == 'validateDomain') {
          throw PlatformException(
            code: 'PUBLIC_SUFFIX',
            message: "Cannot block public suffix 'github.io'.",
            details: {
              'code': 'PUBLIC_SUFFIX',
              'domain': 'github.io',
              'message': "Cannot block public suffix 'github.io'.",
            },
          );
        }
        return null;
      });

      expect(
        () => service.validateDomain('github.io'),
        throwsA(
          isA<AuraRuleException>()
              .having((e) => e.code, 'code', 'PUBLIC_SUFFIX')
              .having((e) => e.message, 'message',
                  "Cannot block public suffix 'github.io'."),
        ),
      );
    });

    test('addRule invokes native bridge and parses returned AuraRuleItem',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (MethodCall call) async {
        calls.add(call);
        if (call.method == 'addRule') {
          return {
            'id': 'rule-123',
            'domain': 'adservice.google.com',
            'isBlocked': true,
            'isEnabled': true,
          };
        }
        return null;
      });

      final rule = await service.addRule(
        domain: 'adservice.google.com',
        isBlocked: true,
        isEnabled: true,
      );

      expect(rule.id, 'rule-123');
      expect(rule.domain, 'adservice.google.com');
      expect(rule.isBlocked, isTrue);
      expect(rule.isEnabled, isTrue);
      expect(calls.length, 1);
      expect(calls.first.method, 'addRule');
    });

    test('updateRule, toggleRule, and deleteRule invoke expected methods',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (MethodCall call) async {
        calls.add(call);
        if (call.method == 'updateRule') {
          return {
            'id': 'rule-1',
            'domain': 'updated.com',
            'isBlocked': false,
            'isEnabled': true,
          };
        }
        if (call.method == 'toggleRule') {
          return {
            'id': 'rule-1',
            'domain': 'updated.com',
            'isBlocked': false,
            'isEnabled': false,
          };
        }
        if (call.method == 'deleteRule') {
          return {
            'id': 'rule-1',
            'domain': 'updated.com',
            'isBlocked': false,
            'isEnabled': false,
          };
        }
        return null;
      });

      final updated = await service.updateRule(
        id: 'rule-1',
        domain: 'updated.com',
        isBlocked: false,
        isEnabled: true,
      );
      expect(updated.domain, 'updated.com');
      expect(updated.isBlocked, isFalse);

      final toggled = await service.toggleRule('rule-1', false);
      expect(toggled.isEnabled, isFalse);

      final deleted = await service.deleteRule('rule-1');
      expect(deleted.id, 'rule-1');

      expect(calls.length, 3);
      expect(calls[0].method, 'updateRule');
      expect(calls[1].method, 'toggleRule');
      expect(calls[2].method, 'deleteRule');
    });

    test('getCategories and setCategoryPreference interact correctly with bridge',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (MethodCall call) async {
        calls.add(call);
        if (call.method == 'getCategories') {
          return {'Ads': true, 'Trackers': true, 'Analytics': false};
        }
        if (call.method == 'setCategoryPreference') {
          return {'Ads': true, 'Trackers': false, 'Analytics': false};
        }
        return null;
      });

      final cats = await service.getCategories();
      expect(cats['Ads'], isTrue);
      expect(cats['Trackers'], isTrue);
      expect(cats['Analytics'], isFalse);

      final updated = await service.setCategoryPreference('Trackers', false);
      expect(updated['Trackers'], isFalse);

      expect(calls.length, 2);
      expect(calls[0].method, 'getCategories');
      expect(calls[1].method, 'setCategoryPreference');
      expect(calls[1].arguments, {'category': 'Trackers', 'isEnabled': false});
    });
  });

  group('AuraRulesScreen Widget Tests', () {
    late List<AuraRuleItem> currentRules;

    setUp(() {
      currentRules = [
        const AuraRuleItem(
          id: 'rule-block-1',
          domain: 'bad-tracker.com',
          isEnabled: true,
          isBlocked: true,
        ),
        const AuraRuleItem(
          id: 'rule-allow-1',
          domain: 'work-portal.internal',
          isEnabled: true,
          isBlocked: false,
        ),
      ];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (MethodCall call) async {
        if (call.method == 'getRules') {
          return currentRules.map((r) => r.toMap()).toList();
        }
        if (call.method == 'validateDomain') {
          final domain = (call.arguments as Map)['domain'] as String;
          if (domain == 'github.io') {
            throw PlatformException(
              code: 'PUBLIC_SUFFIX',
              message: "Cannot block public suffix 'github.io'.",
            );
          }
          if (domain == '1.1.1.1') {
            throw PlatformException(
              code: 'IP_ADDRESS',
              message: 'IP addresses cannot be used as firewall rules.',
            );
          }
          return domain.toLowerCase().trim();
        }
        if (call.method == 'addRule') {
          final args = call.arguments as Map;
          final newRule = AuraRuleItem(
            id: 'rule-${args['domain']}',
            domain: args['domain'] as String,
            isBlocked: args['isBlocked'] as bool,
            isEnabled: args['isEnabled'] as bool? ?? true,
          );
          currentRules.add(newRule);
          return newRule.toMap();
        }
        if (call.method == 'toggleRule') {
          final args = call.arguments as Map;
          final id = args['id'] as String;
          final isEnabled = args['isEnabled'] as bool;
          final index = currentRules.indexWhere((r) => r.id == id);
          if (index != -1) {
            final updated = currentRules[index].copyWith(isEnabled: isEnabled);
            currentRules[index] = updated;
            return updated.toMap();
          }
          throw PlatformException(code: 'RULE_NOT_FOUND', message: 'Not found');
        }
        if (call.method == 'deleteRule') {
          final args = call.arguments as Map;
          final id = args['id'] as String;
          final index = currentRules.indexWhere((r) => r.id == id);
          if (index != -1) {
            final deleted = currentRules.removeAt(index);
            return deleted.toMap();
          }
          throw PlatformException(code: 'RULE_NOT_FOUND', message: 'Not found');
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, null);
    });

    testWidgets('Renders Blocklist and Allowlist tabs with respective rules',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: AuraRulesScreen()),
      );
      await tester.pumpAndSettle();

      // Blocklist tab is active by default
      expect(find.text('Firewall Rules'), findsOneWidget);
      expect(find.text('bad-tracker.com'), findsOneWidget);
      expect(find.text('work-portal.internal'), findsNothing);

      // Switch to Allowlist tab
      await tester.tap(find.text('Allowlist (1)'));
      await tester.pumpAndSettle();

      expect(find.text('work-portal.internal'), findsOneWidget);
      expect(find.text('bad-tracker.com'), findsNothing);
    });

    testWidgets('Add Rule Dialog validates and displays inline error on PSL rejection',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: AuraRulesScreen()),
      );
      await tester.pumpAndSettle();

      // Open Add Rule dialog
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Add Block Rule'), findsOneWidget);

      // Enter invalid PSL domain
      await tester.enterText(find.byType(TextField), 'github.io');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add Rule'));
      await tester.pumpAndSettle();

      // Should display error message
      expect(find.text("Cannot block public suffix 'github.io'."), findsOneWidget);

      // Enter IP address
      await tester.enterText(find.byType(TextField), '1.1.1.1');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add Rule'));
      await tester.pumpAndSettle();

      expect(find.text('IP addresses cannot be used as firewall rules.'), findsOneWidget);

      // Enter valid domain
      await tester.enterText(find.byType(TextField), 'adserver.com');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add Rule'));
      await tester.pumpAndSettle();

      // Dialog closed and new rule added to blocklist
      expect(find.text('Add Block Rule'), findsNothing);
      expect(find.text('adserver.com'), findsOneWidget);
    });

    testWidgets('Toggle rule switch calls service and updates state',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: AuraRulesScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('bad-tracker.com'), findsOneWidget);
      final switchFinder = find.byType(Switch).first;

      // Toggle off
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(currentRules.first.isEnabled, isFalse);
    });

    testWidgets('Delete rule displays confirmation and removes item',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: AuraRulesScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('bad-tracker.com'), findsOneWidget);

      // Tap delete icon
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();

      // Confirm dialog appears
      expect(find.text('Delete Rule'), findsOneWidget);
      expect(find.text('Are you sure you want to delete the rule for "bad-tracker.com"?'), findsOneWidget);

      // Tap Delete
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Rule is deleted
      expect(find.text('bad-tracker.com'), findsNothing);
      expect(find.text('No custom block rules'), findsOneWidget);
    });
  });

  group('Dashboard Category Controls Widget Tests', () {
    Map<String, bool> categoryState = {
      'Ads': true,
      'Trackers': true,
      'Analytics': true,
    };

    setUp(() {
      categoryState = {
        'Ads': true,
        'Trackers': true,
        'Analytics': true,
      };

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, (MethodCall call) async {
        if (call.method == 'getStatus') return 'connected';
        if (call.method == 'getRules') {
          return [
            {
              'id': 'rule-1',
              'domain': 'googleads.g.doubleclick.net',
              'isEnabled': true,
              'isBlocked': true,
            }
          ];
        }
        if (call.method == 'getCategories') return categoryState;
        if (call.method == 'setCategoryPreference') {
          final args = call.arguments as Map;
          final cat = args['category'] as String;
          final enabled = args['isEnabled'] as bool;
          categoryState[cat] = enabled;
          return categoryState;
        }
        if (call.method == 'syncRules') return true;
        return null;
      });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(activityChannel, (MethodCall call) async {
        if (call.method == 'getDashboardStats') {
          return <String, dynamic>{
            'timeWindowMillis': 86400000,
            'startTime': 0,
            'endTime': 86400000,
            'totalQueries': 100,
            'totalBlocked': 25,
            'totalAllowed': 75,
            'totalFailed': 0,
            'uniqueBlockedDomains': 5,
            'uniqueDomainsTotal': 30,
          };
        }
        if (call.method == 'getTopBlockedDomains') return <dynamic>[];
        if (call.method == 'getActivity') {
          return {'records': <dynamic>[], 'hasMore': false};
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(activityChannel, null);
    });

    testWidgets('Dashboard renders categories and toggles preference',
        (WidgetTester tester) async {
      await tester.pumpWidget(const AuraApp());
      await tester.pumpAndSettle();

      // Find Protection Categories Card
      expect(find.text('Default Protection Categories'), findsOneWidget);
      expect(find.text('Ads'), findsOneWidget);
      expect(find.text('Trackers'), findsOneWidget);
      expect(find.text('Analytics'), findsOneWidget);

      // Verify category switches exist
      expect(find.byType(Switch), findsWidgets);

      // Toggle Ads category switch
      final adsText = find.text('Ads');
      await tester.ensureVisible(adsText);
      final adsSwitch = find.byType(Switch).first;
      await tester.ensureVisible(adsSwitch);

      await tester.tap(adsSwitch);
      await tester.pumpAndSettle();

      // State should have updated
      expect(categoryState['Ads'], isFalse);
    });

    testWidgets('Dashboard custom rules card navigates to AuraRulesScreen',
        (WidgetTester tester) async {
      await tester.pumpWidget(const AuraApp());
      await tester.pumpAndSettle();

      // Find "Manage Rules" button in Custom Rules Card
      final manageRulesButton = find.text('Manage Rules');
      await tester.ensureVisible(manageRulesButton);
      await tester.tap(manageRulesButton);
      await tester.pumpAndSettle();

      // Should have pushed AuraRulesScreen
      expect(find.text('Firewall Rules'), findsOneWidget);
      expect(find.text('Allowlist (0)'), findsOneWidget);
    });
  });
}
