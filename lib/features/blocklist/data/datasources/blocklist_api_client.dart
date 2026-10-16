import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:theja_aura/core/config/app_config.dart';

import '../../domain/models/blocklist_manifest.dart';

class DownloadedFileResult {
  final String content;
  final String? etag;
  final String checksum;
  final int statusCode;
  final bool isNotModified;
  final bool isChecksumVerified;

  const DownloadedFileResult({
    required this.content,
    this.etag,
    required this.checksum,
    required this.statusCode,
    this.isNotModified = false,
    this.isChecksumVerified = false,
  });
}

class BlocklistApiException implements Exception {
  final String message;
  final int? statusCode;
  final Object? cause;

  const BlocklistApiException(this.message, {this.statusCode, this.cause});

  @override
  String toString() =>
      'BlocklistApiException: $message${statusCode != null ? ' (Status: $statusCode)' : ''}';
}

class ChecksumMismatchException implements Exception {
  final String expected;
  final String actual;

  const ChecksumMismatchException({
    required this.expected,
    required this.actual,
  });

  @override
  String toString() =>
      'ChecksumMismatchException: Expected SHA-256 $expected, but got $actual';
}

abstract class IBlocklistApiClient {
  /// Fetches the latest published blocklist manifest.
  /// If [ifNoneMatch] is supplied and matches the backend release ETag, returns null (Not Modified).
  Future<BlocklistManifest?> fetchManifest({String? ifNoneMatch});

  /// Downloads a blocklist file (domains.txt, hosts.txt, or category file).
  /// Resolves relative URLs against configured base URL and validates destinations.
  Future<DownloadedFileResult> downloadFile({
    required String urlOrPath,
    String? ifNoneMatch,
    String? expectedChecksum,
  });
}

@LazySingleton(as: IBlocklistApiClient)
class BlocklistApiClient implements IBlocklistApiClient {
  final AppConfig _config;
  final http.Client _client;

  BlocklistApiClient(this._config, this._client);

  @override
  Future<BlocklistManifest?> fetchManifest({String? ifNoneMatch}) async {
    final manifestUri = _config.resolveManifestUrl(
      '/api/public/blocklist/manifest',
    );

    final headers = <String, String>{
      'Accept': 'application/json',
      if (ifNoneMatch != null && ifNoneMatch.isNotEmpty)
        'If-None-Match': ifNoneMatch,
    };

    try {
      final response = await _client
          .get(manifestUri, headers: headers)
          .timeout(_config.requestTimeout);

      if (response.statusCode == 304) {
        return null;
      }

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonMap = jsonDecode(response.body);
        return BlocklistManifest.fromJson(jsonMap);
      }

      throw BlocklistApiException(
        'Failed to fetch manifest from $manifestUri',
        statusCode: response.statusCode,
      );
    } on FormatException catch (e) {
      throw BlocklistApiException(
        'Malformed manifest JSON received: ${e.message}',
        cause: e,
      );
    } on BlocklistApiException {
      rethrow;
    } catch (e) {
      throw BlocklistApiException(
        'Network error fetching manifest: $e',
        cause: e,
      );
    }
  }

  @override
  Future<DownloadedFileResult> downloadFile({
    required String urlOrPath,
    String? ifNoneMatch,
    String? expectedChecksum,
  }) async {
    final targetUri = _config.resolveManifestUrl(urlOrPath);

    final headers = <String, String>{
      'Accept': 'text/plain',
      if (ifNoneMatch != null && ifNoneMatch.isNotEmpty)
        'If-None-Match': ifNoneMatch,
    };

    try {
      final response = await _client
          .get(targetUri, headers: headers)
          .timeout(_config.requestTimeout);

      if (response.statusCode == 304) {
        return DownloadedFileResult(
          content: '',
          etag: ifNoneMatch,
          checksum: '',
          statusCode: 304,
          isNotModified: true,
          isChecksumVerified: false,
        );
      }

      if (response.statusCode == 200) {
        final content = response.body;
        final computedSha256 = sha256.convert(utf8.encode(content)).toString();
        bool isChecksumVerified = false;

        if (expectedChecksum != null && expectedChecksum.isNotEmpty) {
          if (expectedChecksum.toLowerCase() != computedSha256.toLowerCase()) {
            throw ChecksumMismatchException(
              expected: expectedChecksum,
              actual: computedSha256,
            );
          }
          isChecksumVerified = true;
        }

        final etag = response.headers['etag'];

        return DownloadedFileResult(
          content: content,
          etag: etag,
          checksum: computedSha256,
          statusCode: 200,
          isNotModified: false,
          isChecksumVerified: isChecksumVerified,
        );
      }

      throw BlocklistApiException(
        'Failed to download blocklist file from $targetUri',
        statusCode: response.statusCode,
      );
    } on BlocklistApiException {
      rethrow;
    } on ChecksumMismatchException {
      rethrow;
    } catch (e) {
      throw BlocklistApiException(
        'Network error downloading file: $e',
        cause: e,
      );
    }
  }
}
