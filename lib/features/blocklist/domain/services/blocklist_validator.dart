import 'package:theja_aura/core/services/aura_domain_evaluator.dart';

class BlocklistValidationResult {
  final bool isValid;
  final Set<String> validDomains;
  final int totalLines;
  final int validDomainCount;
  final int invalidLineCount;
  final String? error;

  const BlocklistValidationResult({
    required this.isValid,
    required this.validDomains,
    required this.totalLines,
    required this.validDomainCount,
    required this.invalidLineCount,
    this.error,
  });

  bool get isEmptyCategory => isValid && validDomains.isEmpty;

  factory BlocklistValidationResult.failure(String error) =>
      BlocklistValidationResult(
        isValid: false,
        validDomains: const {},
        totalLines: 0,
        validDomainCount: 0,
        invalidLineCount: 0,
        error: error,
      );
}

class BlocklistValidator {
  /// Validates raw blocklist content (.txt or hosts format) and extracts sanitized domains.
  /// - Strips comments (#, //) and blank lines.
  /// - Extracts domain from hosts format ('0.0.0.0 domain' / '127.0.0.1 domain').
  /// - Normalizes using [AuraDomainEvaluator.normalizeDomain].
  /// - Enforces RFC 1035 syntax (valid labels, length <= 253, at least one dot).
  /// - Rejects malformed/truncated content.
  /// - When [allowEmpty] is true, accepts valid header-only files with 0 domains,
  ///   but strictly rejects malformed files containing invalid lines.
  static BlocklistValidationResult validate(
    String rawContent, {
    bool allowEmpty = false,
  }) {
    if (rawContent.trim().isEmpty) {
      if (allowEmpty) {
        return const BlocklistValidationResult(
          isValid: true,
          validDomains: {},
          totalLines: 0,
          validDomainCount: 0,
          invalidLineCount: 0,
        );
      }
      return BlocklistValidationResult.failure(
        'Blocklist file content is empty',
      );
    }

    // Check for binary data
    if (rawContent.contains('\u0000')) {
      return BlocklistValidationResult.failure(
        'File contains binary data / NULL bytes',
      );
    }

    final lines = rawContent.split('\n');
    final validDomains = <String>{};
    int totalLines = lines.length;
    int invalidCount = 0;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) {
        continue;
      }

      String domainCandidate = line;
      // Handle hosts format: '0.0.0.0 example.com' or '127.0.0.1 example.com'
      if (domainCandidate.startsWith('0.0.0.0 ') ||
          domainCandidate.startsWith('127.0.0.1 ') ||
          domainCandidate.startsWith('::1 ') ||
          domainCandidate.contains('\t')) {
        final parts = domainCandidate.split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          domainCandidate = parts[1];
        }
      }

      final normalized = AuraDomainEvaluator.normalizeDomain(domainCandidate);
      if (_isValidDomain(normalized)) {
        validDomains.add(normalized);
      } else {
        invalidCount++;
      }
    }

    if (validDomains.isEmpty) {
      if (allowEmpty && invalidCount == 0) {
        return BlocklistValidationResult(
          isValid: true,
          validDomains: const {},
          totalLines: totalLines,
          validDomainCount: 0,
          invalidLineCount: 0,
        );
      }
      return BlocklistValidationResult.failure(
        invalidCount > 0
            ? 'Content contains $invalidCount invalid lines and no valid RFC-1035 domains'
            : 'No valid RFC-1035 domain entries found in blocklist content',
      );
    }

    return BlocklistValidationResult(
      isValid: true,
      validDomains: validDomains,
      totalLines: totalLines,
      validDomainCount: validDomains.length,
      invalidLineCount: invalidCount,
    );
  }

  /// Validates RFC 1035 / RFC 1123 domain syntax.
  static bool _isValidDomain(String domain) {
    if (domain.isEmpty || domain.length > 253) return false;

    // Must contain at least one dot
    final labels = domain.split('.');
    if (labels.length < 2) return false;

    for (final label in labels) {
      if (label.isEmpty || label.length > 63) return false;
      if (label.startsWith('-') || label.endsWith('-')) return false;

      // Label must consist of alphanumeric or hyphen
      for (int i = 0; i < label.length; i++) {
        final code = label.codeUnitAt(i);
        final isDigit = code >= 48 && code <= 57; // 0-9
        final isLower = code >= 97 && code <= 122; // a-z
        final isHyphen = code == 45; // -
        if (!isDigit && !isLower && !isHyphen) return false;
      }
    }

    // Top-level domain cannot be all numeric (RFC 1123 / ICANN)
    final tld = labels.last;
    if (tld.runes.every((r) => r >= 48 && r <= 57)) return false;

    return true;
  }
}
