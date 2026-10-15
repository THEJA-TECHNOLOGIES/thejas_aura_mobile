import 'aura_default_categories.dart';
import 'aura_tunnel_service.dart';

/// Pure domain evaluation and matching logic mirroring native `AuraDNSEngine`.
/// Enforces deterministic precedence:
/// 1. Custom Allowlist (highest precedence, overrides all blocks and categories)
/// 2. Custom Blocklist (overrides default categories)
/// 3. Default Categories (Ads, Trackers, Analytics) respecting category preferences
///    and individual disabled domain overrides
/// 4. Default Allow (queries permitted by default)
class AuraDomainEvaluator {
  /// Common multi-part public suffixes to exclude from rule candidate suffixes,
  /// mirroring native `AuraPSLValidator`.
  static const Set<String> _multiPartPublicSuffixes = {
    'co.uk',
    'org.uk',
    'gov.uk',
    'me.uk',
    'ltd.uk',
    'plc.uk',
    'com.au',
    'net.au',
    'org.au',
    'edu.au',
    'gov.au',
    'co.jp',
    'ne.jp',
    'ac.jp',
    'go.jp',
    'or.jp',
    'co.nz',
    'org.nz',
    'co.za',
    'com.br',
    'com.sg',
  };

  /// Normalizes a domain string according to RFC 1035 standards.
  static String normalizeDomain(String raw) {
    var str = raw.trim().toLowerCase();
    if (str.startsWith('http://')) str = str.substring(7);
    if (str.startsWith('https://')) str = str.substring(8);
    final slashIndex = str.indexOf('/');
    if (slashIndex != -1) str = str.substring(0, slashIndex);
    final colonIndex = str.indexOf(':');
    if (colonIndex != -1) str = str.substring(0, colonIndex);
    final qIndex = str.indexOf('?');
    if (qIndex != -1) str = str.substring(0, qIndex);
    final hashIndex = str.indexOf('#');
    if (hashIndex != -1) str = str.substring(0, hashIndex);
    while (str.endsWith('.')) {
      str = str.substring(0, str.length - 1);
    }
    return str;
  }

  /// Generates candidate domain suffixes from longest to shortest.
  /// E.g. "sub.ads.google.com" -> ["sub.ads.google.com", "ads.google.com", "google.com"]
  /// Bare public suffixes like "com" or "co.uk" are excluded.
  static List<String> generateCandidateSuffixes(String domain) {
    final normalized = normalizeDomain(domain);
    if (normalized.isEmpty) return const [];

    final parts = normalized.split('.');
    if (parts.length < 2) return const [];

    final candidates = <String>[];
    for (int i = 0; i < parts.length; i++) {
      final candidate = parts.sublist(i).join('.');
      if (candidate.contains('.') &&
          !_multiPartPublicSuffixes.contains(candidate)) {
        candidates.add(candidate);
      }
    }
    return candidates;
  }

  /// Evaluates whether a domain is currently effectively blocked.
  static bool isEffectivelyBlocked({
    required String domain,
    required List<AuraRuleItem> customRules,
    required Set<String> disabledDefaultDomains,
    required Map<String, bool> categoryPreferences,
    Map<String, Set<String>>? categoryDomains,
    bool fallback = false,
  }) {
    final normalized = normalizeDomain(domain);
    if (normalized.isEmpty) return false;

    final candidates = generateCandidateSuffixes(normalized);
    if (candidates.isEmpty) return fallback;

    // Build lookups for active custom rules
    final allowRules = <String, AuraRuleItem>{};
    final blockRules = <String, AuraRuleItem>{};
    for (final rule in customRules) {
      if (rule.isEnabled) {
        final d = normalizeDomain(rule.domain);
        if (!rule.isBlocked) {
          allowRules[d] = rule;
        } else {
          blockRules[d] = rule;
        }
      }
    }

    // 1. Check Custom Allowlist (highest precedence across all candidates)
    for (final candidate in candidates) {
      if (allowRules.containsKey(candidate)) {
        return false;
      }
    }

    // 2. Check Custom Blocklist across candidates
    bool hasCustomBlock = false;
    for (final candidate in candidates) {
      if (blockRules.containsKey(candidate)) {
        hasCustomBlock = true;
        break;
      }
    }

    // 3. Check Default Categories across candidates
    final categories =
        categoryDomains ?? AuraDefaultCategoryData.allCategoriesMap;
    final normalizedDisabled = disabledDefaultDomains
        .map(normalizeDomain)
        .toSet();

    bool hasDefaultCategoryBlock = false;
    for (final entry in categories.entries) {
      final catName = entry.key;

      // Case-insensitive category preference lookup, default true
      bool isCatEnabled = true;
      if (categoryPreferences.containsKey(catName)) {
        isCatEnabled = categoryPreferences[catName]!;
      } else {
        for (final prefEntry in categoryPreferences.entries) {
          if (prefEntry.key.toLowerCase() == catName.toLowerCase()) {
            isCatEnabled = prefEntry.value;
            break;
          }
        }
      }

      if (isCatEnabled) {
        for (final candidate in candidates) {
          if (entry.value.contains(candidate) &&
              !normalizedDisabled.contains(candidate)) {
            hasDefaultCategoryBlock = true;
            break;
          }
        }
      }
      if (hasDefaultCategoryBlock) break;
    }

    if (hasCustomBlock) return true;
    if (hasDefaultCategoryBlock) return true;

    return false;
  }
}
