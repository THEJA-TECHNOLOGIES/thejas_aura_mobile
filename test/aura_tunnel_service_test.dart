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
  });
}
