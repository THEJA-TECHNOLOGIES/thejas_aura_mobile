import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:theja_aura/core/config/app_config.dart';
import 'package:theja_aura/core/services/aura_activity_service.dart';
import 'package:theja_aura/core/services/aura_default_categories.dart';
import 'package:theja_aura/core/services/aura_domain_evaluator.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';
import 'package:theja_aura/features/blocklist/data/datasources/blocklist_api_client.dart';
import 'package:theja_aura/features/blocklist/data/repositories/blocklist_repository.dart';
import 'package:theja_aura/features/blocklist/data/repositories/blocklist_sync_repository.dart';
import 'package:theja_aura/features/blocklist/domain/models/blocklist_manifest.dart';
import 'package:theja_aura/features/blocklist/domain/repositories/i_blocklist_sync_repository.dart';
import 'package:theja_aura/features/blocklist/domain/services/blocklist_validator.dart';
import 'package:theja_aura/features/blocklist/presentation/bloc/blocklist_sync_cubit.dart';

/// Test HTTP Client allowing mock responses for any URL.
class MockHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.Request request) handler;

  MockHttpClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final httpRequest = request as http.Request;
    final response = await handler(httpRequest);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const controlChannel = MethodChannel('com.thejatech.aura/tunnel_control');
  const activityChannel = MethodChannel('com.thejatech.aura/activity');

  late List<MethodCall> recordedControlCalls;
  late List<MethodCall> recordedActivityCalls;
  Map<String, dynamic>? mockInstalledReleaseResponse;
  Map<String, dynamic> mockInstallReleaseResponse = {
    'success': true,
    'version': '2026.10.15-01',
    'files': {'domains.txt': '/tmp/domains.txt'},
    'reloaded': true,
  };
  bool shouldNativeInstallFail = false;
  List<Map<String, dynamic>>? mockReleaseCategoriesResponse;
  Map<String, List<String>> mockCategoryDomainsResponse = {};
  List<Map<String, dynamic>> mockRulesResponse = [];
  List<String> mockOverridesResponse = [];
  Map<String, bool> mockPreferencesResponse = {
    'Ads': true,
    'Trackers': true,
    'Analytics': true,
  };

  setUp(() {
    recordedControlCalls = [];
    recordedActivityCalls = [];
    mockInstalledReleaseResponse = null;
    shouldNativeInstallFail = false;
    mockReleaseCategoriesResponse = null;
    mockCategoryDomainsResponse = {};
    mockRulesResponse = [];
    mockOverridesResponse = [];
    mockPreferencesResponse = {
      'Ads': true,
      'Trackers': true,
      'Analytics': true,
    };

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(controlChannel, (MethodCall call) async {
          recordedControlCalls.add(call);

          switch (call.method) {
            case 'getInstalledRelease':
              return mockInstalledReleaseResponse;
            case 'installBlocklistRelease':
              if (shouldNativeInstallFail) {
                throw PlatformException(
                  code: 'DISK_FULL',
                  message: 'App Group container out of space',
                );
              }
              final args = call.arguments as Map;
              return {
                'success': true,
                'version': args['version'],
                'files': (args['files'] as Map).map(
                  (k, v) => MapEntry(k.toString(), '/path/$k'),
                ),
                'reloaded': mockInstallReleaseResponse['reloaded'] ?? true,
              };
            case 'clearInstalledRelease':
              return true;
            case 'getStatus':
              return 'connected';
            case 'getReleaseCategories':
              return mockReleaseCategoriesResponse;
            case 'getCategoryDomains':
              final cat = (call.arguments as Map?)?['category'] as String?;
              return mockCategoryDomainsResponse[cat] ?? <String>[];
            case 'getRules':
              return mockRulesResponse;
            case 'getDefaultDomainOverrides':
              return mockOverridesResponse;
            case 'getCategories':
              return mockPreferencesResponse;
            default:
              return null;
          }
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(activityChannel, (MethodCall call) async {
          recordedActivityCalls.add(call);
          if (call.method == 'initializeDatabase') {
            return {'ready': true, 'databaseFileName': 'dns_activity.sqlite'};
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

  // =========================================================================
  // Scenario 1: Environment URL Selection and Endpoint Construction
  // =========================================================================
  group('Scenario 1: Environment URL Selection and Endpoint Construction', () {
    test('Default fallback URL is valid and properly formatted', () {
      final config = AppConfig(
        apiBaseUrl: Uri.parse(AppConfig.defaultLocalUrl),
      );
      expect(config.apiBaseUrl.toString(), equals('http://127.0.0.1:8080'));
    });

    test('Validates custom base URLs and strips trailing slashes', () {
      final uri1 = AppConfig.validateBaseUrl('http://192.168.1.50:8080/');
      expect(uri1.toString(), equals('http://192.168.1.50:8080'));

      final uri2 = AppConfig.validateBaseUrl('https://api.thejatech.com///');
      expect(uri2.toString(), equals('https://api.thejatech.com'));
    });

    test('Rejects invalid schemes and malformed URLs', () {
      expect(
        () => AppConfig.validateBaseUrl('ftp://example.com'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => AppConfig.validateBaseUrl('not-a-url'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => AppConfig.validateBaseUrl('http:///no-host'),
        throwsA(isA<FormatException>()),
      );
    });

    test('Resolves relative manifest endpoints against base URL', () {
      final config = AppConfig(apiBaseUrl: Uri.parse('http://127.0.0.1:8080'));
      final resolved = config.resolveManifestUrl(
        '/api/public/blocklist/manifest',
      );
      expect(
        resolved.toString(),
        equals('http://127.0.0.1:8080/api/public/blocklist/manifest'),
      );
    });

    test('Rejects untrusted external hosts from manifest destinations', () {
      final config = AppConfig(apiBaseUrl: Uri.parse('http://127.0.0.1:8080'));
      expect(
        () =>
            config.resolveManifestUrl('http://malicious-host.com/domains.txt'),
        throwsA(isA<SecurityException>()),
      );
    });
  });

  // =========================================================================
  // Scenario 2: Manifest Deserialization
  // =========================================================================
  group('Scenario 2: Manifest Deserialization', () {
    test('Deserializes real backend sample payload accurately', () {
      final jsonSample = {
        'version': '2026.10.15-01',
        'updatedAt': '2026-10-15T12:00:00Z',
        'domainCount': 45000,
        'files': {
          'hosts': '/api/public/blocklist/hosts.txt',
          'domains': '/api/public/blocklist/domains.txt',
        },
      };

      final manifest = BlocklistManifest.fromJson(jsonSample);
      expect(manifest.version, equals('2026.10.15-01'));
      expect(manifest.updatedAt, equals(DateTime.utc(2026, 10, 15, 12, 0, 0)));
      expect(manifest.domainCount, equals(45000));
      expect(
        manifest.files['domains'],
        equals('/api/public/blocklist/domains.txt'),
      );
      expect(
        manifest.files['hosts'],
        equals('/api/public/blocklist/hosts.txt'),
      );
      expect(manifest.categories, isNull);
    });

    test('Deserializes manifest with categories and checksums', () {
      final jsonWithCategories = {
        'version': '2026.10.16-01',
        'updatedAt': '2026-10-16T08:00:00Z',
        'domainCount': 35000,
        'checksum':
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        'files': {
          'categories/ads': '/api/public/blocklist/categories/ads/domains.txt',
        },
        'categories': {
          'ads': {
            'name': 'Ads',
            'domainCount': 15000,
            'domainsUrl': '/api/public/blocklist/categories/ads/domains.txt',
            'checksum': 'abc123sha256',
          },
        },
      };

      final manifest = BlocklistManifest.fromJson(jsonWithCategories);
      expect(manifest.categories, isNotNull);
      expect(manifest.categories!['ads']?.name, equals('Ads'));
      expect(manifest.categories!['ads']?.domainCount, equals(15000));
      expect(manifest.checksum, isNotNull);
    });

    test('Defensively handles minimal and missing fields', () {
      final minimalJson = {
        'version': 'v1',
        'updatedAt': '2026-10-15T00:00:00Z',
      };

      final manifest = BlocklistManifest.fromJson(minimalJson);
      expect(manifest.version, equals('v1'));
      expect(manifest.domainCount, equals(0));
      expect(manifest.files, isEmpty);
      expect(manifest.categories, isNull);
    });
  });

  // =========================================================================
  // Scenario 3: First-Install Download of Required Categories
  // =========================================================================
  group('Scenario 3: First-Install Download of Required Categories', () {
    test(
      'Downloads and installs initial release with actual backend manifest categories',
      () async {
        final config = AppConfig(
          apiBaseUrl: Uri.parse('http://127.0.0.1:8080'),
        );
        const manifestJson = '''
      {
        "version": "6ad193313259a32fe8debeb9",
        "updatedAt": "2026-10-16T03:08:20.255Z",
        "domainCount": 253998,
        "files": {
          "hosts": "/api/public/blocklist/hosts.txt",
          "domains": "/api/public/blocklist/domains.txt"
        },
        "categories": {
          "ADS": {
            "domainCount": 192771,
            "files": {
              "hosts": "/api/public/blocklist/categories/ads/hosts.txt",
              "domains": "/api/public/blocklist/categories/ads/domains.txt"
            }
          },
          "TRACKERS": {
            "domainCount": 34,
            "files": {
              "hosts": "/api/public/blocklist/categories/trackers/hosts.txt",
              "domains": "/api/public/blocklist/categories/trackers/domains.txt"
            }
          },
          "ANALYTICS": {
            "domainCount": 0,
            "files": {
              "hosts": "/api/public/blocklist/categories/analytics/hosts.txt",
              "domains": "/api/public/blocklist/categories/analytics/domains.txt"
            }
          },
          "MALWARE": {
            "domainCount": 437,
            "files": {
              "hosts": "/api/public/blocklist/categories/malware/hosts.txt",
              "domains": "/api/public/blocklist/categories/malware/domains.txt"
            }
          },
          "SOCIAL": {
            "domainCount": 0,
            "files": {
              "hosts": "/api/public/blocklist/categories/social/hosts.txt",
              "domains": "/api/public/blocklist/categories/social/domains.txt"
            }
          }
        }
      }
      ''';

        const adsContent = '''
# PrivacyShield compiled blocklist - Category: ADS
# Version: 6ad193313259a32fe8debeb9
0.avmarket.rs
0.myikas.com
adservice.google.com
''';

        const trackersContent = '''
# PrivacyShield compiled blocklist - Category: TRACKERS
# Version: 6ad193313259a32fe8debeb9
adjust.io
appsflyer.com
crashlytics.com
''';

        const analyticsContent = '''
# PrivacyShield compiled blocklist - Category: ANALYTICS
# Version: 6ad193313259a32fe8debeb9
# Updated: 2026-10-16T03:00:16.276041Z
# Domains: 0
''';

        const malwareContent = '''
# PrivacyShield compiled blocklist - Category: MALWARE
# Version: 6ad193313259a32fe8debeb9
bad-trojan.xyz
malicious-site.com
''';

        const socialContent = '''
# PrivacyShield compiled blocklist - Category: SOCIAL
# Version: 6ad193313259a32fe8debeb9
# Domains: 0
''';

        final httpClient = MockHttpClient((request) async {
          if (request.url.path == '/api/public/blocklist/manifest') {
            return http.Response(
              manifestJson,
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path ==
              '/api/public/blocklist/categories/ads/domains.txt') {
            return http.Response(
              adsContent,
              200,
              headers: {'content-type': 'text/plain'},
            );
          }
          if (request.url.path ==
              '/api/public/blocklist/categories/trackers/domains.txt') {
            return http.Response(
              trackersContent,
              200,
              headers: {'content-type': 'text/plain'},
            );
          }
          if (request.url.path ==
              '/api/public/blocklist/categories/analytics/domains.txt') {
            return http.Response(
              analyticsContent,
              200,
              headers: {'content-type': 'text/plain'},
            );
          }
          if (request.url.path ==
              '/api/public/blocklist/categories/malware/domains.txt') {
            return http.Response(
              malwareContent,
              200,
              headers: {'content-type': 'text/plain'},
            );
          }
          if (request.url.path ==
              '/api/public/blocklist/categories/social/domains.txt') {
            return http.Response(
              socialContent,
              200,
              headers: {'content-type': 'text/plain'},
            );
          }
          return http.Response('Not Found: ${request.url.path}', 404);
        });

        final apiClient = BlocklistApiClient(config, httpClient);
        final tunnelService = AuraTunnelService();
        final repository = BlocklistSyncRepository(apiClient, tunnelService);

        final statusEvents = <BlocklistSyncStatus>[];
        repository.statusStream.listen(statusEvents.add);

        final result = await repository.sync();
        await pumpEventQueue();

        expect(result.isSuccess, isTrue);
        expect(result.isUpdated, isTrue);
        expect(result.version, equals('6ad193313259a32fe8debeb9'));
        expect(result.isCategoryEndpointsMissing, isFalse);
        expect(result.isChecksumVerified, isFalse);
        expect(
          result.installedCategories,
          containsAll(['ADS', 'TRACKERS', 'ANALYTICS', 'MALWARE', 'SOCIAL']),
        );
        expect(
          result.unsupportedCategories,
          isEmpty,
        );

        // Verify native install was called
        expect(
          recordedControlCalls.any(
            (c) => c.method == 'installBlocklistRelease',
          ),
          isTrue,
        );

        final installCall = recordedControlCalls.firstWhere(
          (c) => c.method == 'installBlocklistRelease',
        );
        final args = installCall.arguments as Map;
        expect(args['version'], equals('6ad193313259a32fe8debeb9'));
        final files = args['files'] as Map;
        // Verify real downloaded files were passed to native layer
        expect(files.containsKey('ads.txt'), isTrue);
        expect(files.containsKey('trackers.txt'), isTrue);
        expect(files.containsKey('analytics.txt'), isTrue);
        expect(files.containsKey('malware.txt'), isTrue);
        expect(files.containsKey('social.txt'), isTrue);
        expect((files['ads.txt'] as String).contains('0.avmarket.rs'), isTrue);
        expect((files['trackers.txt'] as String).contains('adjust.io'), isTrue);
        expect((files['malware.txt'] as String).contains('bad-trojan.xyz'), isTrue);
        // Header-only empty category file installed
        expect(
          (files['analytics.txt'] as String).contains('# Domains: 0'),
          isTrue,
        );

        // Verify status transitions
        expect(
          statusEvents.any((s) => s.state == SyncState.checkingForUpdates),
          isTrue,
        );
        expect(
          statusEvents.any((s) => s.state == SyncState.downloading),
          isTrue,
        );
        expect(
          statusEvents.any((s) => s.state == SyncState.validating),
          isTrue,
        );
        expect(
          statusEvents.any((s) => s.state == SyncState.installing),
          isTrue,
        );
        expect(statusEvents.any((s) => s.state == SyncState.updated), isTrue);
      },
    );
  });

  // =========================================================================
  // Scenario 4: Unchanged Version Skips Category Downloads
  // =========================================================================
  group('Scenario 4: Unchanged Version Skips Category Downloads', () {
    test('304 Not Modified skips file download and emits upToDate', () async {
      mockInstalledReleaseResponse = {
        'version': '2026.10.15-01',
        'installedAt': '2026-10-15T12:00:00Z',
        'domainCount': 45000,
        'files': {'domains.txt': '/path/domains.txt'},
        'etag': '2026.10.15-01',
      };

      int manifestRequests = 0;
      int domainRequests = 0;

      final httpClient = MockHttpClient((request) async {
        if (request.url.path == '/api/public/blocklist/manifest') {
          manifestRequests++;
          if (request.headers['if-none-match'] == '2026.10.15-01') {
            return http.Response('', 304);
          }
        }
        if (request.url.path == '/api/public/blocklist/domains.txt') {
          domainRequests++;
          return http.Response('domain.com\n', 200);
        }
        return http.Response('Not Found', 404);
      });

      final config = AppConfig(apiBaseUrl: Uri.parse('http://127.0.0.1:8080'));
      final apiClient = BlocklistApiClient(config, httpClient);
      final tunnelService = AuraTunnelService();
      final repository = BlocklistSyncRepository(apiClient, tunnelService);

      final result = await repository.sync();

      expect(result.isSuccess, isTrue);
      expect(result.isUpdated, isFalse);
      expect(result.version, equals('2026.10.15-01'));
      expect(manifestRequests, equals(1));
      expect(domainRequests, equals(0));
      expect(
        recordedControlCalls.any((c) => c.method == 'installBlocklistRelease'),
        isFalse,
      );
    });

    test(
      'Same version in 200 response with healthy local files skips downloads',
      () async {
        mockInstalledReleaseResponse = {
          'version': '2026.10.15-01',
          'installedAt': '2026-10-15T12:00:00Z',
          'domainCount': 45000,
          'files': {'domains.txt': '/path/domains.txt'},
        };

        int domainDownloads = 0;
        final httpClient = MockHttpClient((request) async {
          if (request.url.path == '/api/public/blocklist/manifest') {
            return http.Response(
              '{"version": "2026.10.15-01", "updatedAt": "2026-10-15T12:00:00Z", "domainCount": 45000, "files": {"domains": "/api/public/blocklist/domains.txt"}}',
              200,
            );
          }
          if (request.url.path == '/api/public/blocklist/domains.txt') {
            domainDownloads++;
            return http.Response('domain.com\n', 200);
          }
          return http.Response('Not Found', 404);
        });

        final config = AppConfig(
          apiBaseUrl: Uri.parse('http://127.0.0.1:8080'),
        );
        final apiClient = BlocklistApiClient(config, httpClient);
        final tunnelService = AuraTunnelService();
        final repository = BlocklistSyncRepository(apiClient, tunnelService);

        final result = await repository.sync();

        expect(result.isSuccess, isTrue);
        expect(result.isUpdated, isFalse);
        expect(domainDownloads, equals(0));
      },
    );
  });

  // =========================================================================
  // Scenario 5: Changed Version Triggers a New Release Download
  // =========================================================================
  group('Scenario 5: Changed Version Triggers a New Release Download', () {
    test(
      'New version triggers download, validation, and native installation',
      () async {
        mockInstalledReleaseResponse = {
          'version': '2026.10.14-01',
          'installedAt': '2026-10-14T10:00:00Z',
          'domainCount': 40000,
          'files': {'domains.txt': '/old/domains.txt'},
        };

        const newManifest = '''
      {
        "version": "2026.10.15-01",
        "updatedAt": "2026-10-15T12:00:00Z",
        "domainCount": 42000,
        "files": {
          "domains": "/api/public/blocklist/domains.txt"
        }
      }
      ''';

        final httpClient = MockHttpClient((request) async {
          if (request.url.path == '/api/public/blocklist/manifest') {
            return http.Response(newManifest, 200);
          }
          if (request.url.path == '/api/public/blocklist/domains.txt') {
            return http.Response('new-tracker.com\nnew-ad.com\n', 200);
          }
          return http.Response('Not Found', 404);
        });

        final config = AppConfig(
          apiBaseUrl: Uri.parse('http://127.0.0.1:8080'),
        );
        final apiClient = BlocklistApiClient(config, httpClient);
        final tunnelService = AuraTunnelService();
        final repository = BlocklistSyncRepository(apiClient, tunnelService);

        final result = await repository.sync();

        expect(result.isSuccess, isTrue);
        expect(result.isUpdated, isTrue);
        expect(result.version, equals('2026.10.15-01'));
        expect(
          recordedControlCalls.any(
            (c) => c.method == 'installBlocklistRelease',
          ),
          isTrue,
        );
      },
    );
  });

  // =========================================================================
  // Scenario 6: Missing or Corrupt Local Files Trigger Safe Repair
  // =========================================================================
  group('Scenario 6: Missing or Corrupt Local Files Trigger Safe Repair', () {
    test(
      'Same version re-downloads files if local file list is empty',
      () async {
        mockInstalledReleaseResponse = {
          'version': '2026.10.15-01',
          'installedAt': '2026-10-15T12:00:00Z',
          'domainCount': 45000,
          'files': <String, dynamic>{}, // Corrupted / missing files
        };

        int domainDownloads = 0;
        final httpClient = MockHttpClient((request) async {
          if (request.url.path == '/api/public/blocklist/manifest') {
            return http.Response(
              '{"version": "2026.10.15-01", "updatedAt": "2026-10-15T12:00:00Z", "domainCount": 45000, "files": {"domains": "/api/public/blocklist/domains.txt"}}',
              200,
            );
          }
          if (request.url.path == '/api/public/blocklist/domains.txt') {
            domainDownloads++;
            return http.Response('domain1.com\ndomain2.com\n', 200);
          }
          return http.Response('Not Found', 404);
        });

        final config = AppConfig(
          apiBaseUrl: Uri.parse('http://127.0.0.1:8080'),
        );
        final apiClient = BlocklistApiClient(config, httpClient);
        final tunnelService = AuraTunnelService();
        final repository = BlocklistSyncRepository(apiClient, tunnelService);

        final result = await repository.sync();

        expect(result.isSuccess, isTrue);
        expect(result.isUpdated, isTrue);
        expect(domainDownloads, equals(1));
        expect(
          recordedControlCalls.any(
            (c) => c.method == 'installBlocklistRelease',
          ),
          isTrue,
        );
      },
    );
  });

  // =========================================================================
  // Scenario 7: Checksum Mismatch Rejects a Release
  // =========================================================================
  group('Scenario 7: Checksum Mismatch Rejects a Release', () {
    test('Aborts installation and fails when file checksum does not match manifest', () async {
      const corruptContent = 'bad-content-without-matching-hash\n';
      final manifestJson = jsonEncode({
        'version': '2026.10.15-01',
        'updatedAt': '2026-10-15T12:00:00Z',
        'domainCount': 1,
        'checksum': 'expected_sha256_hash_that_does_not_match',
        'files': {'domains': '/api/public/blocklist/domains.txt'},
      });

      final httpClient = MockHttpClient((request) async {
        if (request.url.path == '/api/public/blocklist/manifest') {
          return http.Response(manifestJson, 200);
        }
        if (request.url.path == '/api/public/blocklist/domains.txt') {
          return http.Response(corruptContent, 200);
        }
        return http.Response('Not Found', 404);
      });

      final config = AppConfig(apiBaseUrl: Uri.parse('http://127.0.0.1:8080'));
      final apiClient = BlocklistApiClient(config, httpClient);
      final tunnelService = AuraTunnelService();
      final repository = BlocklistSyncRepository(apiClient, tunnelService);

      final result = await repository.sync();

      expect(result.isSuccess, isFalse);
      expect(result.error, contains('ChecksumMismatchException'));
      // Verify native install was NEVER called
      expect(
        recordedControlCalls.any((c) => c.method == 'installBlocklistRelease'),
        isFalse,
      );
    });
  });

  // =========================================================================
  // Scenario 8: Failed Download Preserves the Old Release
  // =========================================================================
  group('Scenario 8: Failed Download Preserves the Old Release', () {
    test(
      'HTTP 500 error on file download retains previous release metadata',
      () async {
        mockInstalledReleaseResponse = {
          'version': '2026.10.14-01',
          'installedAt': '2026-10-14T10:00:00Z',
          'domainCount': 40000,
          'files': {'domains.txt': '/old/domains.txt'},
        };

        final httpClient = MockHttpClient((request) async {
          if (request.url.path == '/api/public/blocklist/manifest') {
            return http.Response(
              '{"version": "2026.10.15-01", "updatedAt": "2026-10-15T12:00:00Z", "domainCount": 42000, "files": {"domains": "/api/public/blocklist/domains.txt"}}',
              200,
            );
          }
          if (request.url.path == '/api/public/blocklist/domains.txt') {
            return http.Response('Internal Server Error', 500);
          }
          return http.Response('Not Found', 404);
        });

        final config = AppConfig(
          apiBaseUrl: Uri.parse('http://127.0.0.1:8080'),
        );
        final apiClient = BlocklistApiClient(config, httpClient);
        final tunnelService = AuraTunnelService();
        final repository = BlocklistSyncRepository(apiClient, tunnelService);

        final result = await repository.sync();

        expect(result.isSuccess, isFalse);
        expect(result.error, contains('500'));
        expect(result.installedRelease?.version, equals('2026.10.14-01'));
        expect(
          recordedControlCalls.any(
            (c) => c.method == 'installBlocklistRelease',
          ),
          isFalse,
        );
      },
    );
  });

  // =========================================================================
  // Scenario 9: Partial Installation Never Becomes Active
  // =========================================================================
  group('Scenario 9: Partial Installation Never Becomes Active', () {
    test(
      'Validation failure on downloaded content aborts installation',
      () async {
        // Content containing binary null byte
        const invalidContent = 'good-domain.com\n\u0000corrupt-binary\n';

        final httpClient = MockHttpClient((request) async {
          if (request.url.path == '/api/public/blocklist/manifest') {
            return http.Response(
              '{"version": "2026.10.15-01", "updatedAt": "2026-10-15T12:00:00Z", "domainCount": 2, "files": {"domains": "/api/public/blocklist/domains.txt"}}',
              200,
            );
          }
          if (request.url.path == '/api/public/blocklist/domains.txt') {
            return http.Response(invalidContent, 200);
          }
          return http.Response('Not Found', 404);
        });

        final config = AppConfig(
          apiBaseUrl: Uri.parse('http://127.0.0.1:8080'),
        );
        final apiClient = BlocklistApiClient(config, httpClient);
        final tunnelService = AuraTunnelService();
        final repository = BlocklistSyncRepository(apiClient, tunnelService);

        final result = await repository.sync();

        expect(result.isSuccess, isFalse);
        expect(result.error, contains('NULL bytes'));
        expect(
          recordedControlCalls.any(
            (c) => c.method == 'installBlocklistRelease',
          ),
          isFalse,
        );
      },
    );
  });

  // =========================================================================
  // Scenario 10: Native Installation Success and Failure
  // =========================================================================
  group('Scenario 10: Native Installation Success and Failure', () {
    test(
      'Native channel failure is handled gracefully without crashing',
      () async {
        shouldNativeInstallFail = true;

        final httpClient = MockHttpClient((request) async {
          if (request.url.path == '/api/public/blocklist/manifest') {
            return http.Response(
              '{"version": "2026.10.15-01", "updatedAt": "2026-10-15T12:00:00Z", "domainCount": 2, "files": {"domains": "/api/public/blocklist/domains.txt"}}',
              200,
            );
          }
          if (request.url.path == '/api/public/blocklist/domains.txt') {
            return http.Response('domain1.com\ndomain2.com\n', 200);
          }
          return http.Response('Not Found', 404);
        });

        final config = AppConfig(
          apiBaseUrl: Uri.parse('http://127.0.0.1:8080'),
        );
        final apiClient = BlocklistApiClient(config, httpClient);
        final tunnelService = AuraTunnelService();
        final repository = BlocklistSyncRepository(apiClient, tunnelService);

        final result = await repository.sync();

        expect(result.isSuccess, isFalse);
        expect(result.error, contains('DISK_FULL'));
        expect(repository.currentStatus.state, equals(SyncState.failed));
      },
    );
  });

  // =========================================================================
  // Scenario 11: Firewall Refresh Behavior When Protection Enabled or Disabled
  // =========================================================================
  group('Scenario 11: Firewall Refresh Behavior When Protection Enabled or Disabled', () {
    test(
      'Reports activeFirewallReloaded = true when tunnel was live',
      () async {
        mockInstallReleaseResponse['reloaded'] = true;

        final httpClient = MockHttpClient((request) async {
          if (request.url.path == '/api/public/blocklist/manifest') {
            return http.Response(
              '{"version": "2026.10.15-01", "updatedAt": "2026-10-15T12:00:00Z", "domainCount": 1, "files": {"domains": "/api/public/blocklist/domains.txt"}}',
              200,
            );
          }
          if (request.url.path == '/api/public/blocklist/domains.txt') {
            return http.Response('domain1.com\n', 200);
          }
          return http.Response('Not Found', 404);
        });

        final config = AppConfig(
          apiBaseUrl: Uri.parse('http://127.0.0.1:8080'),
        );
        final apiClient = BlocklistApiClient(config, httpClient);
        final tunnelService = AuraTunnelService();
        final repository = BlocklistSyncRepository(apiClient, tunnelService);

        final result = await repository.sync();
        expect(result.isSuccess, isTrue);
        expect(result.activeFirewallReloaded, isTrue);
      },
    );

    test(
      'Reports activeFirewallReloaded = false when tunnel was inactive',
      () async {
        mockInstallReleaseResponse['reloaded'] = false;

        final httpClient = MockHttpClient((request) async {
          if (request.url.path == '/api/public/blocklist/manifest') {
            return http.Response(
              '{"version": "2026.10.15-01", "updatedAt": "2026-10-15T12:00:00Z", "domainCount": 1, "files": {"domains": "/api/public/blocklist/domains.txt"}}',
              200,
            );
          }
          if (request.url.path == '/api/public/blocklist/domains.txt') {
            return http.Response('domain1.com\n', 200);
          }
          return http.Response('Not Found', 404);
        });

        final config = AppConfig(
          apiBaseUrl: Uri.parse('http://127.0.0.1:8080'),
        );
        final apiClient = BlocklistApiClient(config, httpClient);
        final tunnelService = AuraTunnelService();
        final repository = BlocklistSyncRepository(apiClient, tunnelService);

        final result = await repository.sync();
        expect(result.isSuccess, isTrue);
        expect(result.activeFirewallReloaded, isFalse);
      },
    );
  });

  // =========================================================================
  // Scenario 12: Concurrent Synchronization Attempts (Deduplication)
  // =========================================================================
  group('Scenario 12: Concurrent Synchronization Attempts (Deduplication)', () {
    test(
      'Coalesces simultaneous sync invocations onto single in-flight operation',
      () async {
        int manifestCallCount = 0;
        final completer = Completer<http.Response>();

        final httpClient = MockHttpClient((request) async {
          if (request.url.path == '/api/public/blocklist/manifest') {
            manifestCallCount++;
            return completer.future;
          }
          if (request.url.path == '/api/public/blocklist/domains.txt') {
            return http.Response('domain.com\n', 200);
          }
          return http.Response('Not Found', 404);
        });

        final config = AppConfig(
          apiBaseUrl: Uri.parse('http://127.0.0.1:8080'),
        );
        final apiClient = BlocklistApiClient(config, httpClient);
        final tunnelService = AuraTunnelService();
        final repository = BlocklistSyncRepository(apiClient, tunnelService);

        // Trigger two concurrent syncs
        final future1 = repository.sync();
        final future2 = repository.sync();

        // Deduplication: both callers receive the exact same in-flight future
        expect(identical(future1, future2), isTrue);

        // Complete the response
        completer.complete(
          http.Response(
            '{"version": "2026.10.15-01", "updatedAt": "2026-10-15T12:00:00Z", "domainCount": 1, "files": {"domains": "/api/public/blocklist/domains.txt"}}',
            200,
          ),
        );

        final results = await Future.wait([future1, future2]);

        expect(results[0].version, equals('2026.10.15-01'));
        expect(results[1].version, equals('2026.10.15-01'));
        expect(manifestCallCount, equals(1));
      },
    );
  });

  // =========================================================================
  // Scenario 13: Offline Startup With an Installed Release
  // =========================================================================
  group('Scenario 13: Offline Startup With an Installed Release', () {
    test(
      'Network error retains local release and cubit preserves installed state',
      () async {
        mockInstalledReleaseResponse = {
          'version': '2026.10.14-01',
          'installedAt': '2026-10-14T10:00:00Z',
          'domainCount': 40000,
          'files': {'domains.txt': '/old/domains.txt'},
        };

        final httpClient = MockHttpClient((request) async {
          throw const SocketException('No Internet connection');
        });

        final config = AppConfig(
          apiBaseUrl: Uri.parse('http://127.0.0.1:8080'),
        );
        final apiClient = BlocklistApiClient(config, httpClient);
        final tunnelService = AuraTunnelService();
        final repository = BlocklistSyncRepository(apiClient, tunnelService);
        final cubit = BlocklistSyncCubit(repository);

        // Give cubit time to initialize release
        await pumpEventQueue();

        final result = await cubit.sync();
        await pumpEventQueue();

        expect(result.isSuccess, isFalse);
        expect(cubit.state.installedRelease?.version, equals('2026.10.14-01'));
        expect(cubit.state.state, equals(SyncState.failed));

        await cubit.close();
      },
    );
  });

  // =========================================================================
  // Scenario 14: First Startup When Backend is Unavailable
  // =========================================================================
  group('Scenario 14: First Startup When Backend is Unavailable', () {
    test(
      'Sync fails gracefully without uncaught exceptions on first launch',
      () async {
        mockInstalledReleaseResponse = null;

        final httpClient = MockHttpClient((request) async {
          throw const SocketException('Connection refused');
        });

        final config = AppConfig(
          apiBaseUrl: Uri.parse('http://127.0.0.1:8080'),
        );
        final apiClient = BlocklistApiClient(config, httpClient);
        final tunnelService = AuraTunnelService();
        final repository = BlocklistSyncRepository(apiClient, tunnelService);

        final result = await repository.sync();

        expect(result.isSuccess, isFalse);
        expect(result.error, contains('Connection refused'));
        expect(repository.currentStatus.state, equals(SyncState.failed));
        expect(repository.currentStatus.installedRelease, isNull);
      },
    );
  });

  // =========================================================================
  // Scenario 15: Startup Synchronization Does Not Require VPN Permission
  // =========================================================================
  group(
    'Scenario 15: Startup Synchronization Does Not Require VPN Permission',
    () {
      test('Blocklist sync only accesses App Group storage, never asks for VPN permission', () async {
        final httpClient = MockHttpClient((request) async {
          if (request.url.path == '/api/public/blocklist/manifest') {
            return http.Response(
              '{"version": "2026.10.15-01", "updatedAt": "2026-10-15T12:00:00Z", "domainCount": 1, "files": {"domains": "/api/public/blocklist/domains.txt"}}',
              200,
            );
          }
          if (request.url.path == '/api/public/blocklist/domains.txt') {
            return http.Response('domain1.com\n', 200);
          }
          return http.Response('Not Found', 404);
        });

        final config = AppConfig(
          apiBaseUrl: Uri.parse('http://127.0.0.1:8080'),
        );
        final apiClient = BlocklistApiClient(config, httpClient);
        final tunnelService = AuraTunnelService();
        final repository = BlocklistSyncRepository(apiClient, tunnelService);

        await repository.sync();

        // Ensure NO VPN permission or startTunnel calls occurred
        expect(
          recordedControlCalls.any((c) => c.method == 'startTunnel'),
          isFalse,
        );
        expect(
          recordedControlCalls.any((c) => c.method == 'prepareTunnel'),
          isFalse,
        );
      });
    },
  );

  // =========================================================================
  // Scenario 16: Custom BLOCK/ALLOW Rules Survive Default Blocklist Update
  // =========================================================================
  group(
    'Scenario 16: Custom BLOCK/ALLOW Rules Survive Default Blocklist Update',
    () {
      test('AuraDomainEvaluator enforces custom allow rules over newly updated blocklist', () {
        final customRules = [
          const AuraRuleItem(
            id: 'rule-1',
            domain: 'tracker.analytics.com',
            isEnabled: true,
            isBlocked: false, // Custom ALLOW
          ),
          const AuraRuleItem(
            id: 'rule-2',
            domain: 'custom-blocked-site.com',
            isEnabled: true,
            isBlocked: true, // Custom BLOCK
          ),
        ];

        // Simulated newly downloaded blocklist containing tracker.analytics.com
        final updatedCategories = {
          'Trackers': {'tracker.analytics.com', 'other-tracker.com'},
        };

        // 1. Custom ALLOW overrides category block
        final isAllowedDomainBlocked = AuraDomainEvaluator.isEffectivelyBlocked(
          domain: 'tracker.analytics.com',
          customRules: customRules,
          disabledDefaultDomains: {},
          categoryPreferences: {'Trackers': true},
          categoryDomains: updatedCategories,
        );
        expect(isAllowedDomainBlocked, isFalse);

        // 2. Custom BLOCK blocks even if not in default categories
        final isCustomBlocked = AuraDomainEvaluator.isEffectivelyBlocked(
          domain: 'custom-blocked-site.com',
          customRules: customRules,
          disabledDefaultDomains: {},
          categoryPreferences: {'Trackers': true},
          categoryDomains: updatedCategories,
        );
        expect(isCustomBlocked, isTrue);

        // 3. Other domains in updated category are blocked
        final isOtherBlocked = AuraDomainEvaluator.isEffectivelyBlocked(
          domain: 'other-tracker.com',
          customRules: customRules,
          disabledDefaultDomains: {},
          categoryPreferences: {'Trackers': true},
          categoryDomains: updatedCategories,
        );
        expect(isOtherBlocked, isTrue);
      });
    },
  );

  // =========================================================================
  // Scenario 17: Existing Activity/Logs DB Bootstrap and Domain-Switch Unchanged
  // =========================================================================
  group('Scenario 17: Existing Activity/Logs DB Bootstrap and Domain-Switch Unchanged', () {
    test(
      'AuraActivityService database bootstrap succeeds independently of sync',
      () async {
        final activityService = AuraActivityService();
        expect(activityService.isDatabaseReady, isFalse);

        final ready = await activityService.initializeDatabase();
        expect(ready, isTrue);
        expect(activityService.isDatabaseReady, isTrue);
        expect(
          recordedActivityCalls.any((c) => c.method == 'initializeDatabase'),
          isTrue,
        );
      },
    );

    test('BlocklistValidator correctly sanitizes hosts format and RFC-1035 domains', () {
      const rawHosts = '''
      # Blocklist Header
      127.0.0.1 adservice.google.com
      0.0.0.0 doubleclick.net
      ::1 tracker.bad.org
      regular-domain.com
      # Commented domain
      # bad.com
      invalid..domain
      -invalid.com
      ''';

      final validation = BlocklistValidator.validate(rawHosts);
      expect(validation.isValid, isTrue);
      expect(validation.validDomains, contains('adservice.google.com'));
      expect(validation.validDomains, contains('doubleclick.net'));
      expect(validation.validDomains, contains('tracker.bad.org'));
      expect(validation.validDomains, contains('regular-domain.com'));
      expect(validation.validDomains.contains('invalid..domain'), isFalse);
      expect(validation.validDomains.contains('-invalid.com'), isFalse);
    });
  });

  // =========================================================================
  // Scenario 18: Release Hardening — Obsolete Category Removal & Rollback Safety
  // =========================================================================
  group('Scenario 18: Release Hardening — Obsolete Category Removal & Rollback Safety', () {
    test('Release dropping a category sends only current files to native channel', () async {
      final client = MockHttpClient((request) async {
        if (request.url.path.endsWith('/manifest')) {
          return http.Response(
            jsonEncode({
              'version': '2026.10.16-02',
              'updatedAt': '2026-10-16T12:00:00Z',
              'domainCount': 2,
              'files': {
                'ads': '/categories/ads.txt',
                'trackers': '/categories/trackers.txt',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.endsWith('/categories/ads.txt')) {
          return http.Response('adservice.google.com\n', 200);
        }
        if (request.url.path.endsWith('/categories/trackers.txt')) {
          return http.Response('tracker.example.com\n', 200);
        }
        return http.Response('Not Found', 404);
      });

      final config = AppConfig(apiBaseUrl: Uri.parse('http://127.0.0.1:8080'));
      final apiClient = BlocklistApiClient(config, client);
      final repo = BlocklistSyncRepository(apiClient, AuraTunnelService());

      final result = await repo.sync();
      expect(result.isSuccess, isTrue);

      final installCall = recordedControlCalls.firstWhere(
        (c) => c.method == 'installBlocklistRelease',
      );
      final filesMap = (installCall.arguments as Map)['files'] as Map;
      expect(filesMap.containsKey('ads.txt'), isTrue);
      expect(filesMap.containsKey('trackers.txt'), isTrue);
      expect(filesMap.containsKey('malware.txt'), isFalse);
    });

    test('Native channel failure during installation preserves last known good release', () async {
      final client = MockHttpClient((request) async {
        if (request.url.path.endsWith('/manifest')) {
          return http.Response(
            jsonEncode({
              'version': '2026.10.16-fail',
              'updatedAt': '2026-10-16T12:00:00Z',
              'domainCount': 1,
              'files': {
                'ads': '/categories/ads.txt',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.endsWith('/categories/ads.txt')) {
          return http.Response('adservice.google.com\n', 200);
        }
        return http.Response('Not Found', 404);
      });

      final config = AppConfig(apiBaseUrl: Uri.parse('http://127.0.0.1:8080'));
      final apiClient = BlocklistApiClient(config, client);
      final repo = BlocklistSyncRepository(apiClient, AuraTunnelService());

      // Simulate native install throwing an error (e.g. staging validation failed or disk error)
      shouldNativeInstallFail = true;

      final result = await repo.sync();
      expect(result.isSuccess, isFalse);
      expect(repo.currentStatus.state, equals(SyncState.failed));
    });
  });

  // =========================================================================
  // Scenario 19: Phase 3 Verified Contract & Edge Cases
  // =========================================================================
  group('Scenario 19: Phase 3 Verified Contract & Edge Cases', () {
    test(
      'Deserializes actual live backend manifest with uppercase keys and nested relative URLs',
      () {
        final actualBackendJson = {
          'version': '6ad193313259a32fe8debeb9',
          'updatedAt': '2026-10-16T03:08:20.255Z',
          'domainCount': 253998,
          'files': {
            'hosts': '/api/public/blocklist/hosts.txt',
            'domains': '/api/public/blocklist/domains.txt',
          },
          'categories': {
            'ADS': {
              'domainCount': 192771,
              'files': {
                'hosts': '/api/public/blocklist/categories/ads/hosts.txt',
                'domains':
                    '/api/public/blocklist/categories/ads/domains.txt',
              },
            },
            'TRACKERS': {
              'domainCount': 34,
              'files': {
                'hosts':
                    '/api/public/blocklist/categories/trackers/hosts.txt',
                'domains':
                    '/api/public/blocklist/categories/trackers/domains.txt',
              },
            },
            'ANALYTICS': {
              'domainCount': 0,
              'files': {
                'hosts':
                    '/api/public/blocklist/categories/analytics/hosts.txt',
                'domains':
                    '/api/public/blocklist/categories/analytics/domains.txt',
              },
            },
            'MALWARE': {
              'domainCount': 437,
              'files': {
                'hosts':
                    '/api/public/blocklist/categories/malware/hosts.txt',
                'domains':
                    '/api/public/blocklist/categories/malware/domains.txt',
              },
            },
            'SOCIAL': {
              'domainCount': 0,
              'files': {
                'hosts': '/api/public/blocklist/categories/social/hosts.txt',
                'domains':
                    '/api/public/blocklist/categories/social/domains.txt',
              },
            },
          },
        };

        final manifest = BlocklistManifest.fromJson(actualBackendJson);
        expect(manifest.version, equals('6ad193313259a32fe8debeb9'));
        expect(manifest.domainCount, equals(253998));
        expect(manifest.checksum, isNull);
        expect(
          manifest.files['domains'],
          equals('/api/public/blocklist/domains.txt'),
        );
        expect(
          manifest.files['hosts'],
          equals('/api/public/blocklist/hosts.txt'),
        );

        expect(manifest.categories, isNotNull);
        expect(manifest.categories!.length, equals(5));

        // Uppercase category keys parsed and preserved
        expect(manifest.categories!.containsKey('ADS'), isTrue);
        expect(manifest.categories!.containsKey('TRACKERS'), isTrue);
        expect(manifest.categories!.containsKey('ANALYTICS'), isTrue);
        expect(manifest.categories!.containsKey('MALWARE'), isTrue);
        expect(manifest.categories!.containsKey('SOCIAL'), isTrue);

        final ads = manifest.categories!['ADS']!;
        expect(ads.name, equals('ADS'));
        expect(ads.domainCount, equals(192771));
        expect(
          ads.resolvedDomainsUrl,
          equals('/api/public/blocklist/categories/ads/domains.txt'),
        );
        expect(
          ads.resolvedHostsUrl,
          equals('/api/public/blocklist/categories/ads/hosts.txt'),
        );
        expect(ads.checksum, isNull);

        final analytics = manifest.categories!['ANALYTICS']!;
        expect(analytics.domainCount, equals(0));
        expect(
          analytics.resolvedDomainsUrl,
          equals('/api/public/blocklist/categories/analytics/domains.txt'),
        );
      },
    );

    test('BlocklistValidator accepts valid header-only empty category file', () {
      const emptyCategoryContent = '''
# PrivacyShield compiled blocklist - Category: ANALYTICS
# Version: 6ad193313259a32fe8debeb9
# Updated: 2026-10-16T03:00:16.276041Z
# Domains: 0
''';

      final result = BlocklistValidator.validate(
        emptyCategoryContent,
        allowEmpty: true,
      );
      expect(result.isValid, isTrue);
      expect(result.validDomains, isEmpty);
      expect(result.validDomainCount, equals(0));
      expect(result.isEmptyCategory, isTrue);
      expect(result.error, isNull);
    });

    test(
      'BlocklistValidator rejects malformed HTML error pages even when allowEmpty is true',
      () {
        const html500Content = '''
<!DOCTYPE html>
<html>
<head><title>500 Internal Server Error</title></head>
<body><h1>500 Internal Server Error</h1></body>
</html>
''';

        final result = BlocklistValidator.validate(
          html500Content,
          allowEmpty: true,
        );
        expect(result.isValid, isFalse);
        expect(result.validDomains, isEmpty);
        expect(result.error, contains('invalid lines'));
      },
    );

    test('BlocklistValidator rejects binary content containing NULL bytes', () {
      const binaryContent = '0.0.0.0 safe.com\x00corrupt-bytes';
      final result = BlocklistValidator.validate(
        binaryContent,
        allowEmpty: true,
      );
      expect(result.isValid, isFalse);
      expect(result.error, contains('binary data / NULL bytes'));
    });

    test(
      'Sync handles checksum verification when checksum is present and valid',
      () async {
        final config = AppConfig(
          apiBaseUrl: Uri.parse('http://127.0.0.1:8080'),
        );
        const adsContent = 'doubleclick.net\ngoogle-adservices.com\n';
        // Compute actual sha256 for adsContent
        // sha256 of "doubleclick.net\ngoogle-adservices.com\n"
        final actualHash =
            '765e793cb56280f51e5c3bc1f315dfe406cd1f69fd9181b7b729750e8d2c1f22';

        final httpClient = MockHttpClient((request) async {
          if (request.url.path == '/api/public/blocklist/manifest') {
            return http.Response(
              jsonEncode({
                'version': 'v-checksummed',
                'updatedAt': '2026-10-16T12:00:00Z',
                'domainCount': 2,
                'categories': {
                  'ADS': {
                    'domainCount': 2,
                    'checksum': actualHash,
                    'files': {
                      'domains': '/categories/ads/domains.txt',
                    },
                  },
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/categories/ads/domains.txt') {
            return http.Response(
              adsContent,
              200,
              headers: {'content-type': 'text/plain'},
            );
          }
          return http.Response('Not Found', 404);
        });

        final apiClient = BlocklistApiClient(config, httpClient);
        final repo = BlocklistSyncRepository(apiClient, AuraTunnelService());

        final result = await repo.sync();
        expect(result.isSuccess, isTrue);
        expect(result.isChecksumVerified, isTrue);
      },
    );

    test(
      'Sync throws ChecksumMismatchException when file checksum does not match expected',
      () async {
        final config = AppConfig(
          apiBaseUrl: Uri.parse('http://127.0.0.1:8080'),
        );
        const adsContent = 'adservice.google.com\n';

        final httpClient = MockHttpClient((request) async {
          if (request.url.path == '/api/public/blocklist/manifest') {
            return http.Response(
              jsonEncode({
                'version': 'v-mismatch',
                'updatedAt': '2026-10-16T12:00:00Z',
                'domainCount': 1,
                'checksum':
                    '0000000000000000000000000000000000000000000000000000000000000000',
                'categories': {
                  'ADS': {
                    'domainCount': 1,
                    'files': {
                      'domains': '/categories/ads/domains.txt',
                    },
                  },
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/categories/ads/domains.txt') {
            return http.Response(
              adsContent,
              200,
              headers: {'content-type': 'text/plain'},
            );
          }
          return http.Response('Not Found', 404);
        });

        final apiClient = BlocklistApiClient(config, httpClient);
        final repo = BlocklistSyncRepository(apiClient, AuraTunnelService());

        final result = await repo.sync();
        expect(result.isSuccess, isFalse);
        expect(result.error, contains('ChecksumMismatchException'));
      },
    );

    test(
      'Sync fails and preserves previous release when category endpoint returns 500',
      () async {
        mockInstalledReleaseResponse = {
          'version': 'old-release-v1',
          'installedAt': '2026-10-15T12:00:00Z',
          'domainCount': 100,
          'files': {'ads.txt': '/path/ads.txt'},
        };

        final config = AppConfig(
          apiBaseUrl: Uri.parse('http://127.0.0.1:8080'),
        );
        final httpClient = MockHttpClient((request) async {
          if (request.url.path == '/api/public/blocklist/manifest') {
            return http.Response(
              jsonEncode({
                'version': 'new-release-v2',
                'updatedAt': '2026-10-16T12:00:00Z',
                'domainCount': 100,
                'categories': {
                  'ADS': {
                    'domainCount': 100,
                    'files': {'domains': '/categories/ads/domains.txt'},
                  },
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/categories/ads/domains.txt') {
            return http.Response('Internal Server Error', 500);
          }
          return http.Response('Not Found', 404);
        });

        final apiClient = BlocklistApiClient(config, httpClient);
        final repo = BlocklistSyncRepository(apiClient, AuraTunnelService());

        final result = await repo.sync();
        expect(result.isSuccess, isFalse);
        expect(result.error, contains('Failed to download blocklist file'));
        // Verifies previous release is preserved on error
        expect(result.installedRelease?.version, equals('old-release-v1'));
      },
    );
  });

  // =========================================================================
  // Scenario 20: Static Blocklist Removal & Sole Backend Source of Truth
  // =========================================================================
  group('Scenario 20: Static Blocklist Removal & Sole Backend Source of Truth', () {
    test('1. No bundled blocklist data is loaded or used by Flutter', () async {
      mockReleaseCategoriesResponse = null;
      mockCategoryDomainsResponse = {};

      final repo = BlocklistRepository(AuraTunnelService());
      final categories = await repo.getDefaultCategories();
      final domains = await repo.getCategoryDomains('ads');

      expect(categories, isEmpty, reason: 'Must not substitute bundled categories');
      expect(domains, isEmpty, reason: 'Must not return bundled or hardcoded domains');
    });

    test('2. A successful backend sync displays only published backend categories and domains', () async {
      mockReleaseCategoriesResponse = [
        {'name': 'Ads', 'domainCount': 120},
        {'name': 'Trackers', 'domainCount': 85},
      ];
      mockCategoryDomainsResponse = {
        'ads': ['adservice.google.com', 'tracker.doubleclick.net'],
        'trackers': ['telemetry.app.com'],
      };

      final repo = BlocklistRepository(AuraTunnelService());
      final categories = await repo.getDefaultCategories();

      expect(categories.length, equals(2));
      expect(categories[0].name, equals('Ads'));
      expect(categories[0].domainCount, equals(120));
      expect(categories[1].name, equals('Trackers'));
      expect(categories[1].domainCount, equals(85));

      final adsDomains = await repo.getCategoryDomains('ads');
      expect(adsDomains, contains('adservice.google.com'));
      expect(adsDomains, contains('tracker.doubleclick.net'));
      expect(adsDomains.length, equals(2));
    });

    test('3. An empty backend category (0 domains) remains empty; no synthetic domains fabricated', () async {
      mockReleaseCategoriesResponse = [
        {'name': 'Analytics', 'domainCount': 0},
      ];
      mockCategoryDomainsResponse = {
        'analytics': [],
      };

      final repo = BlocklistRepository(AuraTunnelService());
      final categories = await repo.getDefaultCategories();

      expect(categories.length, equals(1));
      expect(categories[0].name, equals('Analytics'));
      expect(categories[0].domainCount, equals(0));

      final domains = await repo.getCategoryDomains('analytics');
      expect(domains, isEmpty, reason: 'Zero domains category must remain empty');
    });

    test('4. Offline operation continues to use the last installed backend release', () async {
      mockInstalledReleaseResponse = {
        'version': 'cached-offline-rel-1',
        'installedAt': '2026-10-16T10:00:00Z',
        'domainCount': 500,
        'files': {'ads.txt': '/path/ads.txt'},
      };
      mockReleaseCategoriesResponse = [
        {'name': 'Ads', 'domainCount': 500},
      ];

      final config = AppConfig(apiBaseUrl: Uri.parse('http://127.0.0.1:8080'));
      // Network fails (offline)
      final httpClient = MockHttpClient((_) async => throw const SocketException('Network offline'));
      final syncRepo = BlocklistSyncRepository(BlocklistApiClient(config, httpClient), AuraTunnelService());

      final syncResult = await syncRepo.sync();
      expect(syncResult.isSuccess, isFalse);
      expect(syncResult.installedRelease?.version, equals('cached-offline-rel-1'));

      final blocklistRepo = BlocklistRepository(AuraTunnelService());
      final categories = await blocklistRepo.getDefaultCategories();
      expect(categories.length, equals(1));
      expect(categories.first.name, equals('Ads'));
      expect(categories.first.domainCount, equals(500));
    });

    test('5. First launch without backend sync displays empty categories with zero blocked category domains', () async {
      mockInstalledReleaseResponse = null;
      mockReleaseCategoriesResponse = null;

      final blocklistRepo = BlocklistRepository(AuraTunnelService());
      final categories = await blocklistRepo.getDefaultCategories();
      expect(categories, isEmpty);

      // Domain evaluation with empty categories
      final isBlocked = AuraDomainEvaluator.isEffectivelyBlocked(
        domain: 'doubleclick.net',
        customRules: [],
        disabledDefaultDomains: {},
        categoryPreferences: {'ads': true},
        categoryDomains: const {},
      );
      expect(isBlocked, isFalse, reason: 'No domains must be blocked via categories before backend sync');
    });

    test('6. A category removed in a new backend release does not survive in active filtering rules', () async {
      final config = AppConfig(apiBaseUrl: Uri.parse('http://127.0.0.1:8080'));
      // New release contains only 'ads', 'malware' was removed
      final manifestJson = jsonEncode({
        'version': 'rel-v2-without-malware',
        'updatedAt': '2026-10-16T14:00:00Z',
        'domainCount': 50,
        'categories': {
          'ADS': {
            'domainCount': 50,
            'files': {'domains': '/categories/ads/domains.txt'},
          },
        },
      });

      final httpClient = MockHttpClient((request) async {
        if (request.url.path == '/api/public/blocklist/manifest') {
          return http.Response(manifestJson, 200, headers: {'content-type': 'application/json'});
        }
        if (request.url.path == '/categories/ads/domains.txt') {
          return http.Response('adserver.com\n', 200, headers: {'content-type': 'text/plain'});
        }
        return http.Response('Not Found', 404);
      });

      final syncRepo = BlocklistSyncRepository(BlocklistApiClient(config, httpClient), AuraTunnelService());
      final syncResult = await syncRepo.sync();

      expect(syncResult.isSuccess, isTrue);
      final installCall = recordedControlCalls.firstWhere(
        (c) => c.method == 'installBlocklistRelease',
      );
      final installedFiles = (installCall.arguments as Map)['files'] as Map;
      expect(installedFiles.containsKey('ads.txt'), isTrue);
      expect(installedFiles.containsKey('malware.txt'), isFalse, reason: 'Removed category must not be staged or installed');
    });

    test('7. Custom BLOCK and ALLOW rules survive backend release replacement', () async {
      mockRulesResponse = [
        {'id': 'rule-1', 'domain': 'my-custom-allow.com', 'isBlocked': false, 'isEnabled': true},
        {'id': 'rule-2', 'domain': 'my-custom-block.com', 'isBlocked': true, 'isEnabled': true},
      ];

      final repo = BlocklistRepository(AuraTunnelService());
      final rulesBefore = await repo.getRules();
      expect(rulesBefore?.length, equals(2));

      // Synchronize a new release
      final config = AppConfig(apiBaseUrl: Uri.parse('http://127.0.0.1:8080'));
      final manifestJson = jsonEncode({
        'version': 'rel-v3-rules-test',
        'updatedAt': '2026-10-16T15:00:00Z',
        'domainCount': 10,
        'categories': {
          'ADS': {
            'domainCount': 10,
            'files': {'domains': '/categories/ads/domains.txt'},
          },
        },
      });

      final httpClient = MockHttpClient((request) async {
        if (request.url.path == '/api/public/blocklist/manifest') {
          return http.Response(manifestJson, 200, headers: {'content-type': 'application/json'});
        }
        if (request.url.path == '/categories/ads/domains.txt') {
          return http.Response('ad.example.com\n', 200, headers: {'content-type': 'text/plain'});
        }
        return http.Response('Not Found', 404);
      });

      final syncRepo = BlocklistSyncRepository(BlocklistApiClient(config, httpClient), AuraTunnelService());
      await syncRepo.sync();

      // Verify custom rules were untouched
      final rulesAfter = await repo.getRules();
      expect(rulesAfter?.length, equals(2));
      expect(rulesAfter?[0].domain, equals('my-custom-allow.com'));
      expect(rulesAfter?[1].domain, equals('my-custom-block.com'));
    });

    test('8. Category enable/disable preferences survive backend release replacement', () async {
      mockPreferencesResponse = {
        'Ads': true,
        'Trackers': false,
        'Analytics': true,
      };

      final repo = BlocklistRepository(AuraTunnelService());
      final prefs = await repo.getCategories();
      expect(prefs['Trackers'], isFalse);

      // Verify installBlocklistRelease does not alter category preferences
      expect(recordedControlCalls.any((c) => c.method == 'saveCategories'), isFalse);
    });

    test('9. Domain overrides survive backend release replacement', () async {
      mockOverridesResponse = ['allowed-ad.com', 'custom-unblocked.org'];

      final repo = BlocklistRepository(AuraTunnelService());
      final overrides = await repo.getDefaultDomainOverrides();
      expect(overrides, contains('allowed-ad.com'));
      expect(overrides, contains('custom-unblocked.org'));

      // Verify release installation never wipes domain overrides
      expect(recordedControlCalls.any((c) => c.method == 'clearDefaultDomainOverrides'), isFalse);
    });

    test('10. Native firewall verification - zero category domains blocked when no release exists', () {
      final evaluatorBlocked = AuraDomainEvaluator.isEffectivelyBlocked(
        domain: 'adservice.google.com',
        customRules: [],
        disabledDefaultDomains: {},
        categoryPreferences: {'ads': true, 'trackers': true},
        categoryDomains: const {},
      );
      expect(evaluatorBlocked, isFalse, reason: 'Zero category domains must be blocked when no release is installed');
    });

    test('11. Dynamic category discovery exposes all 5 published backend categories with formatted names', () async {
      mockReleaseCategoriesResponse = [
        {'id': 'ads', 'name': 'Ads', 'fileName': 'ads.txt', 'domainCount': 192771},
        {'id': 'trackers', 'name': 'Trackers', 'fileName': 'trackers.txt', 'domainCount': 34},
        {'id': 'analytics', 'name': 'Analytics', 'fileName': 'analytics.txt', 'domainCount': 0},
        {'id': 'malware', 'name': 'Malware', 'fileName': 'malware.txt', 'domainCount': 437},
        {'id': 'social', 'name': 'Social', 'fileName': 'social.txt', 'domainCount': 0},
      ];

      final repo = BlocklistRepository(AuraTunnelService());
      final categories = await repo.getDefaultCategories();

      expect(categories.length, equals(5));
      expect(categories.map((c) => c.name), containsAll(['Ads', 'Trackers', 'Analytics', 'Malware', 'Social']));
      expect(categories.firstWhere((c) => c.name == 'Malware').domainCount, equals(437));
      expect(categories.firstWhere((c) => c.name == 'Social').domainCount, equals(0));
      expect(categories.firstWhere((c) => c.name == 'Ads').icon, isNotNull);
    });

    test('12. Dynamic category discovery supports arbitrary unknown future categories without code changes', () async {
      final manifestJson = jsonEncode({
        'version': '2026.11.01-01',
        'updatedAt': '2026-11-01T00:00:00Z',
        'domainCount': 500,
        'categories': {
          'CRYPTO_MINING': {
            'domainCount': 350,
            'files': {'domains': '/categories/crypto/domains.txt'},
          },
          'GAMBLING': {
            'domainCount': 150,
            'files': {'domains': '/categories/gambling/domains.txt'},
          },
        },
      });

      final httpClient = MockHttpClient((request) async {
        if (request.url.path == '/api/public/blocklist/manifest') {
          return http.Response(manifestJson, 200, headers: {'content-type': 'application/json'});
        }
        if (request.url.path == '/categories/crypto/domains.txt') {
          return http.Response('coinhive.com\nminer.pool\n', 200, headers: {'content-type': 'text/plain'});
        }
        if (request.url.path == '/categories/gambling/domains.txt') {
          return http.Response('betting-casino.biz\n', 200, headers: {'content-type': 'text/plain'});
        }
        return http.Response('Not Found', 404);
      });

      final config = AppConfig(apiBaseUrl: Uri.parse('http://127.0.0.1:8080'));
      final syncRepo = BlocklistSyncRepository(BlocklistApiClient(config, httpClient), AuraTunnelService());
      final result = await syncRepo.sync(force: true);

      expect(result.isSuccess, isTrue);
      expect(result.installedCategories, containsAll(['CRYPTO_MINING', 'GAMBLING']));
      expect(result.unsupportedCategories, isEmpty);

      // Verify native install call received the dynamic filenames
      final installCall = recordedControlCalls.lastWhere((c) => c.method == 'installBlocklistRelease');
      final files = (installCall.arguments as Map)['files'] as Map;
      expect(files.containsKey('crypto_mining.txt'), isTrue);
      expect(files.containsKey('gambling.txt'), isTrue);

      // Verify category display name formatting helper
      expect(AuraCategoryMetadata.formatDisplayName('CRYPTO_MINING'), equals('Crypto Mining'));
      expect(AuraCategoryMetadata.formatDisplayName('GAMBLING'), equals('Gambling'));
    });

    test('13. Category removal between releases: omitted categories are pruned and absent from native storage', () async {
      // Setup mock native response simulating release with category removed
      mockReleaseCategoriesResponse = [
        {'id': 'ads', 'name': 'Ads', 'fileName': 'ads.txt', 'domainCount': 100},
        {'id': 'trackers', 'name': 'Trackers', 'fileName': 'trackers.txt', 'domainCount': 50},
      ];

      final repo = BlocklistRepository(AuraTunnelService());
      final categories = await repo.getDefaultCategories();

      expect(categories.length, equals(2));
      expect(categories.any((c) => c.name.toLowerCase() == 'malware'), isFalse);
      expect(categories.any((c) => c.name.toLowerCase() == 'social'), isFalse);
    });
  });
}

