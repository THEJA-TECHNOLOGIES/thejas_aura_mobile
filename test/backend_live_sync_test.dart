import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:theja_aura/core/config/app_config.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';
import 'package:theja_aura/features/blocklist/data/datasources/blocklist_api_client.dart';
import 'package:theja_aura/features/blocklist/data/repositories/blocklist_sync_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // Disables Flutter test HTTP interceptor

  const controlChannel = MethodChannel('com.thejatech.aura/tunnel_control');
  Map<String, dynamic>? installedRelease;

  setUp(() {
    HttpOverrides.global = null;
    installedRelease = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(controlChannel, (MethodCall call) async {
          if (call.method == 'getInstalledRelease') {
            return installedRelease;
          }
          if (call.method == 'installBlocklistRelease') {
            final args = call.arguments as Map;
            installedRelease = {
              'version': args['version'],
              'files': (args['files'] as Map).map(
                (k, v) => MapEntry(k.toString(), '/mock/path/$k'),
              ),
              'reloaded': true,
            };
            return {
              'success': true,
              'version': args['version'],
              'files': installedRelease!['files'],
              'reloaded': true,
            };
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(controlChannel, null);
  });

  test('End-to-End Live Sync against Spring Boot backend on localhost:8080', () async {
    final realClient = http.Client();
    try {
      // 1. Check if backend is reachable
      final healthUri = Uri.parse('http://127.0.0.1:8080/api/public/blocklist/manifest');
      final healthCheck = await realClient.get(healthUri).timeout(const Duration(seconds: 5));
      if (healthCheck.statusCode != 200) {
        fail('Backend at $healthUri responded with ${healthCheck.statusCode}');
      }

      // 2. Configure AppConfig pointing to live backend
      final config = AppConfig(apiBaseUrl: Uri.parse('http://127.0.0.1:8080'));
      final apiClient = BlocklistApiClient(config, realClient);
      final tunnelService = AuraTunnelService();
      final repository = BlocklistSyncRepository(apiClient, tunnelService);

      // 3. Execute synchronization
      final result = await repository.sync(force: true);

      // 4. Verify synchronization results against actual backend responses
      expect(result.isSuccess, isTrue);
      expect(result.isUpdated, isTrue);
      expect(result.version, equals('6ad193313259a32fe8debeb9'));
      expect(result.isCategoryEndpointsMissing, isFalse);
      expect(result.installedCategories, containsAll(['ADS', 'TRACKERS', 'ANALYTICS', 'MALWARE', 'SOCIAL']));
      expect(result.unsupportedCategories, isEmpty);

      // 5. Verify installed release metadata
      final release = await repository.getInstalledRelease();
      expect(release, isNotNull);
      expect(release!.version, equals('6ad193313259a32fe8debeb9'));
      expect(release.categoryFiles.containsKey('ads.txt'), isTrue);
      expect(release.categoryFiles.containsKey('trackers.txt'), isTrue);
      expect(release.categoryFiles.containsKey('analytics.txt'), isTrue);
      expect(release.categoryFiles.containsKey('malware.txt'), isTrue);
      expect(release.categoryFiles.containsKey('social.txt'), isTrue);
      expect(release.categoryDomainCounts['ads'], equals(192771));
      expect(release.categoryDomainCounts['trackers'], equals(34));
      expect(release.categoryDomainCounts['analytics'], equals(0));
      expect(release.categoryDomainCounts['malware'], equals(437));
      expect(release.categoryDomainCounts['social'], equals(0));

      // 6. Verify second sync without force reports up-to-date
      final secondSync = await repository.sync();
      expect(secondSync.isSuccess, isTrue);
      expect(secondSync.isUpdated, isFalse);
      expect(secondSync.version, equals('6ad193313259a32fe8debeb9'));
    } finally {
      realClient.close();
    }
  });
}
