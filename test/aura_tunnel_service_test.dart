import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theja_aura/services/aura_tunnel_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel controlChannel =
      MethodChannel('com.thejatech.aura/tunnel_control');

  group('AuraRuleItem Tests', () {
    test('AuraRuleItem serialization to map', () {
      const item =
          AuraRuleItem(domain: 'google.com', isEnabled: true, isBlocked: true);
      final map = item.toMap();

      expect(map['domain'], 'google.com');
      expect(map['isEnabled'], true);
      expect(map['isBlocked'], true);
    });

    test('AuraRuleItem deserialization from map', () {
      final map = {
        'domain': 'tracker.com',
        'isEnabled': false,
        'isBlocked': true
      };
      final item = AuraRuleItem.fromMap(map);

      expect(item.domain, 'tracker.com');
      expect(item.isEnabled, false);
      expect(item.isBlocked, true);
    });
  });

  group('TunnelStatus Tests', () {
    test('TunnelStatus parsing', () {
      expect(TunnelStatus.fromString('connected'), TunnelStatus.connected);
      expect(TunnelStatus.fromString('connecting'), TunnelStatus.connecting);
      expect(TunnelStatus.fromString('disconnected'), TunnelStatus.disconnected);
      expect(TunnelStatus.fromString('unknown_state'), TunnelStatus.invalid);
    });
  });

  group('AuraTunnelService MethodChannel Contract Tests', () {
    final List<MethodCall> log = <MethodCall>[];
    late AuraTunnelService service;

    setUp(() {
      log.clear();
      service = AuraTunnelService();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel, null);
    });

    test('syncRules and startTunnel invoke separate method calls in sequence',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel,
              (MethodCall methodCall) async {
        log.add(methodCall);
        if (methodCall.method == 'syncRules') {
          return true;
        }
        if (methodCall.method == 'startTunnel') {
          return null;
        }
        return null;
      });

      final synced = await service.syncRules(const [
        AuraRuleItem(domain: 'google.com', isEnabled: true, isBlocked: true),
      ]);
      await service.startTunnel();

      expect(synced, isTrue);
      expect(log.length, 2);
      expect(log[0].method, 'syncRules');
      expect(log[1].method, 'startTunnel');
    });

    test('startTunnel preserves structured native NSError details on failure',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel,
              (MethodCall methodCall) async {
        if (methodCall.method == 'startTunnel') {
          throw PlatformException(
            code: 'START_FAILED',
            message:
                '[loadAllFromPreferences] NEConfigurationErrorDomain (code 11): IPC failed',
            details: {
              'stage': 'loadAllFromPreferences',
              'domain': 'NEConfigurationErrorDomain',
              'code': 11,
              'localizedDescription': 'IPC failed',
              'isSimulator': true,
            },
          );
        }
        return null;
      });

      expect(
        () => service.startTunnel(),
        throwsA(
          isA<PlatformException>()
              .having((e) => e.code, 'code', 'START_FAILED')
              .having(
                  (e) => e.message, 'message', contains('loadAllFromPreferences'))
              .having((e) => (e.details as Map)['domain'], 'domain',
                  'NEConfigurationErrorDomain')
              .having((e) => (e.details as Map)['code'], 'code', 11),
        ),
      );
    });

    test('reloadRules is a separate operation with its own error reporting',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel,
              (MethodCall methodCall) async {
        log.add(methodCall);
        if (methodCall.method == 'reloadRules') {
          throw PlatformException(
            code: 'RELOAD_RULES_FAILED',
            message:
                '[sendProviderMessage] AuraTunnelManager (code -1): Extension returned nil response to reload_rules message',
            details: {
              'stage': 'sendProviderMessage',
              'domain': 'AuraTunnelManager',
              'code': -1,
            },
          );
        }
        return null;
      });

      expect(
        () => service.reloadRules(),
        throwsA(
          isA<PlatformException>()
              .having((e) => e.code, 'code', 'RELOAD_RULES_FAILED')
              .having(
                  (e) => e.message, 'message', contains('sendProviderMessage')),
        ),
      );
    });

    test('getRules parses rule items from native platform response',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel,
              (MethodCall methodCall) async {
        log.add(methodCall);
        if (methodCall.method == 'getRules') {
          return [
            {
              'domain': 'custom-domain.com',
              'isEnabled': true,
              'isBlocked': true,
            },
            {
              'domain': 'whitelist-domain.org',
              'isEnabled': false,
              'isBlocked': false,
            }
          ];
        }
        return null;
      });

      final rules = await service.getRules();
      expect(rules, isNotNull);
      expect(rules!.length, 2);
      expect(rules[0].domain, 'custom-domain.com');
      expect(rules[0].isEnabled, isTrue);
      expect(rules[0].isBlocked, isTrue);
      expect(rules[1].domain, 'whitelist-domain.org');
      expect(rules[1].isEnabled, isFalse);
      expect(rules[1].isBlocked, isFalse);
    });

    test('getRules returns null on native error so disk is not overwritten',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel,
              (MethodCall methodCall) async {
        if (methodCall.method == 'getRules') {
          throw PlatformException(
            code: 'LOAD_RULES_FAILED',
            message: 'Malformed or unrecognized rules JSON schema',
          );
        }
        return null;
      });

      final rules = await service.getRules();
      expect(rules, isNull);
    });

    test('rapid consecutive syncRules invocations serialize and complete cleanly',
        () async {
      int syncCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel,
              (MethodCall methodCall) async {
        if (methodCall.method == 'syncRules') {
          syncCount++;
          return true;
        }
        return null;
      });

      final results = await Future.wait([
        service.syncRules([
          const AuraRuleItem(domain: 'rule1.com', isEnabled: true, isBlocked: true),
        ]),
        service.syncRules([
          const AuraRuleItem(domain: 'rule2.com', isEnabled: true, isBlocked: true),
        ]),
        service.syncRules([
          const AuraRuleItem(domain: 'rule3.com', isEnabled: false, isBlocked: true),
        ]),
      ]);

      expect(results, [true, true, true]);
      expect(syncCount, 3);
    });

    test('stop/start lifecycle preserves rules and verifies call sequence',
        () async {
      final List<String> callSequence = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(controlChannel,
              (MethodCall methodCall) async {
        callSequence.add(methodCall.method);
        if (methodCall.method == 'syncRules') return true;
        if (methodCall.method == 'stopTunnel') return null;
        if (methodCall.method == 'startTunnel') return null;
        return null;
      });

      const initialRules = [
        AuraRuleItem(domain: 'persistent.com', isEnabled: true, isBlocked: true),
        AuraRuleItem(domain: 'allow.com', isEnabled: true, isBlocked: false),
      ];

      // 1. Initial sync & start
      await service.syncRules(initialRules);
      await service.startTunnel();

      // 2. Stop tunnel
      await service.stopTunnel();

      // 3. Restart tunnel with preserved rules
      await service.syncRules(initialRules);
      await service.startTunnel();

      expect(callSequence, [
        'syncRules',
        'startTunnel',
        'stopTunnel',
        'syncRules',
        'startTunnel',
      ]);
    });
  });
}
