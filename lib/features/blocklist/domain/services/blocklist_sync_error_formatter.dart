import 'dart:async';
import 'dart:io';

import '../../../../core/config/app_config.dart';
import '../../data/datasources/blocklist_api_client.dart';

/// Formats blocklist synchronization errors into user-friendly messages.
class BlocklistSyncErrorFormatter {
  static const String defaultErrorMessage =
      'An unexpected error occurred while updating the blocklist.';
  static const String timeoutMessage =
      'Connection timed out. Please check your internet connection and try again.';
  static const String networkMessage =
      'Unable to reach the blocklist server. Please check your internet connection and try again.';
  static const String checksumMessage =
      'Blocklist file verification failed. Please retry the update.';
  static const String formatMessage =
      'Received invalid blocklist data from server. Please try again later.';
  static const String securityMessage =
      'Untrusted download source. Sync cancelled for security.';
  static const String notFoundMessage =
      'Blocklist release not found on server.';
  static const String accessDeniedMessage =
      'Access to blocklist updates was denied.';
  static const String serverUnavailableMessage =
      'The blocklist server is temporarily unavailable. Please try again later.';

  /// Formats an error into a clean, user-facing error message without internal URLs or raw traces.
  static String format(dynamic error) {
    if (error == null) return defaultErrorMessage;

    if (error is TimeoutException) {
      return timeoutMessage;
    }

    if (error is SocketException) {
      return networkMessage;
    }

    if (error is ChecksumMismatchException) {
      return checksumMessage;
    }

    if (error is SecurityException) {
      return securityMessage;
    }

    if (error is FormatException) {
      return formatMessage;
    }

    if (error is BlocklistApiException) {
      if (error.cause != null) {
        return format(error.cause);
      }
      if (error.statusCode != null) {
        final code = error.statusCode!;
        if (code == 404) return notFoundMessage;
        if (code == 401 || code == 403) return accessDeniedMessage;
        if (code >= 500 && code < 600) return serverUnavailableMessage;
      }
      return _cleanString(error.message);
    }

    final raw = error.toString();
    return _formatRawString(raw);
  }

  static String _formatRawString(String raw) {
    final lower = raw.toLowerCase();

    // Check for specific raw exception types
    if (raw.startsWith('TimeoutException') ||
        lower.contains('timed out') ||
        lower.contains('connection timeout')) {
      return timeoutMessage;
    }

    if (raw.startsWith('SocketException') ||
        lower.contains('failed host lookup') ||
        lower.contains('network is unreachable') ||
        lower.contains('connection refused') ||
        lower.contains('connection reset by peer')) {
      return networkMessage;
    }

    if (raw.startsWith('ChecksumMismatchException') ||
        lower.contains('checksum mismatch')) {
      return checksumMessage;
    }

    if (raw.startsWith('SecurityException') ||
        lower.contains('untrusted manifest') ||
        lower.contains('untrusted destination')) {
      return securityMessage;
    }

    if (raw.startsWith('FormatException') ||
        lower.contains('malformed manifest') ||
        lower.contains('unexpected character')) {
      return formatMessage;
    }

    return _cleanString(raw);
  }

  static String _cleanString(String message) {
    var cleaned = message.trim();

    // Strip common technical prefixes
    final prefixes = [
      'BlocklistApiException:',
      'ChecksumMismatchException:',
      'SecurityException:',
      'FormatException:',
      'Exception:',
      'Error:',
    ];

    bool stripped = true;
    while (stripped) {
      stripped = false;
      for (final prefix in prefixes) {
        if (cleaned.startsWith(prefix)) {
          cleaned = cleaned.substring(prefix.length).trim();
          stripped = true;
        }
      }
    }

    // Replace internal URLs with 'the server'
    cleaned = cleaned.replaceAll(RegExp(r'https?://[^\s]+'), 'the server');

    if (cleaned.isEmpty) {
      return defaultErrorMessage;
    }

    return cleaned;
  }
}
