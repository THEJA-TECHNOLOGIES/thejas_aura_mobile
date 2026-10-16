import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuration and environment settings for Theja Aura.
/// Encapsulates backend API endpoint resolution and validation.
class AppConfig {
  static const String defaultLocalUrl = 'http://127.0.0.1:8080';
  static const String envVarName = 'API_BASE_URL';

  final Uri apiBaseUrl;
  final Duration requestTimeout;

  AppConfig({
    required this.apiBaseUrl,
    this.requestTimeout = const Duration(seconds: 15),
  });

  /// Factory to initialize [AppConfig] from environment sources.
  /// Precedence:
  /// 1. `.env` file via `flutter_dotenv`
  /// 2. Dart compile-time environment (`--dart-define=API_BASE_URL=...`)
  /// 3. Default fallback `http://127.0.0.1:8080`
  static Future<AppConfig> load({String? overrideUrl}) async {
    String? rawUrl = overrideUrl;

    if (rawUrl == null || rawUrl.isEmpty) {
      try {
        final envFile = File('.env');
        if (await envFile.exists()) {
          await dotenv.load(fileName: '.env');
          rawUrl = dotenv.env[envVarName];
        }
      } catch (_) {
        // Ignored; fallback to compile-time or default
      }
    }

    if (rawUrl == null || rawUrl.isEmpty) {
      const compileTimeVal = String.fromEnvironment(envVarName);
      if (compileTimeVal.isNotEmpty) {
        rawUrl = compileTimeVal;
      }
    }

    final effectiveUrl = rawUrl?.trim().isNotEmpty == true
        ? rawUrl!.trim()
        : defaultLocalUrl;
    final parsedUri = validateBaseUrl(effectiveUrl);

    return AppConfig(apiBaseUrl: parsedUri);
  }

  /// Validates that a base URL string is a valid HTTP or HTTPS endpoint with a host.
  static Uri validateBaseUrl(String url) {
    var trimmed = url.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        (!uri.isScheme('http') && !uri.isScheme('https')) ||
        uri.host.isEmpty) {
      throw FormatException(
        "Invalid API_BASE_URL: '$url'. Must be a valid HTTP or HTTPS URL with a hostname.",
      );
    }
    return uri;
  }

  /// Resolves a URL from a manifest file.
  /// If [pathOrUrl] is relative (e.g. '/api/public/blocklist/domains.txt'), resolves against [apiBaseUrl].
  /// If absolute, validates that it matches the authorized [apiBaseUrl] host.
  Uri resolveManifestUrl(String pathOrUrl) {
    final candidate = Uri.parse(pathOrUrl);
    if (!candidate.hasScheme) {
      // Relative path: resolve against apiBaseUrl
      return apiBaseUrl.resolve(pathOrUrl);
    }

    // Absolute URL: reject unexpected destinations
    if (candidate.host != apiBaseUrl.host) {
      throw SecurityException(
        "Untrusted manifest file destination: '${candidate.host}'. Expected '${apiBaseUrl.host}'.",
      );
    }

    return candidate;
  }
}

class SecurityException implements Exception {
  final String message;
  SecurityException(this.message);

  @override
  String toString() => 'SecurityException: $message';
}
