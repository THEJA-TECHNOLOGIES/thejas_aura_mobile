import 'package:flutter_test/flutter_test.dart';
import 'package:theja_aura/core/services/aura_default_categories.dart';
import 'package:theja_aura/core/services/aura_domain_evaluator.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';

void main() {
  group('AuraDomainEvaluator', () {
    test('normalizes domains properly', () {
      expect(
        AuraDomainEvaluator.normalizeDomain('  EXAMPLE.COM.  '),
        equals('example.com'),
      );
      expect(
        AuraDomainEvaluator.normalizeDomain('doubleclick.net/path'),
        equals('doubleclick.net'),
      );
      expect(
        AuraDomainEvaluator.normalizeDomain('https://ads.google.com:443'),
        equals('ads.google.com'),
      );
    });

    test('generates candidate suffixes correctly', () {
      final suffixes = AuraDomainEvaluator.generateCandidateSuffixes(
        'sub.tracker.analytics.co.uk',
      );
      expect(suffixes, contains('sub.tracker.analytics.co.uk'));
      expect(suffixes, contains('tracker.analytics.co.uk'));
      expect(suffixes, contains('analytics.co.uk'));
      // TLD/SLD like co.uk and uk should not be candidate domain suffixes
      expect(suffixes, isNot(contains('co.uk')));
      expect(suffixes, isNot(contains('uk')));
    });

    test(
      'allowlist rule takes highest precedence over blocklist and categories',
      () {
        const allowRule = AuraRuleItem(
          id: '1',
          domain: 'doubleclick.net',
          isBlocked: false,
          isEnabled: true,
        );
        const blockRule = AuraRuleItem(
          id: '2',
          domain: 'doubleclick.net',
          isBlocked: true,
          isEnabled: true,
        );

        final isBlocked = AuraDomainEvaluator.isEffectivelyBlocked(
          domain: 'ad.doubleclick.net',
          customRules: [allowRule, blockRule],
          disabledDefaultDomains: {},
          categoryPreferences: {'ads': true},
        );

        expect(isBlocked, isFalse);
      },
    );

    test(
      'custom block rule blocks domain even if not in default categories',
      () {
        const blockRule = AuraRuleItem(
          id: '1',
          domain: 'malicious-site.xyz',
          isBlocked: true,
          isEnabled: true,
        );

        final isBlocked = AuraDomainEvaluator.isEffectivelyBlocked(
          domain: 'sub.malicious-site.xyz',
          customRules: [blockRule],
          disabledDefaultDomains: {},
          categoryPreferences: {},
        );

        expect(isBlocked, isTrue);
      },
    );

    test(
      'default category blocks bundled domains when category is enabled',
      () {
        expect(
          AuraDefaultCategoryData.adsDomains.contains('doubleclick.net'),
          isTrue,
        );

        final isBlocked = AuraDomainEvaluator.isEffectivelyBlocked(
          domain: 'doubleclick.net',
          customRules: [],
          disabledDefaultDomains: {},
          categoryPreferences: {'ads': true},
        );

        expect(isBlocked, isTrue);
      },
    );

    test('default category does not block bundled domain when category is disabled', () {
      final isBlocked = AuraDomainEvaluator.isEffectivelyBlocked(
        domain: 'doubleclick.net',
        customRules: [],
        disabledDefaultDomains: {},
        categoryPreferences: {'ads': false},
      );

      expect(isBlocked, isFalse);
    });

    test('default domain override allows specific bundled domain while category is enabled', () {
      final isBlocked = AuraDomainEvaluator.isEffectivelyBlocked(
        domain: 'doubleclick.net',
        customRules: [],
        disabledDefaultDomains: {'doubleclick.net'},
        categoryPreferences: {'ads': true},
      );

      expect(isBlocked, isFalse);
    });

    test('subdomain inherits default category block from bundled parent', () {
      final isBlocked = AuraDomainEvaluator.isEffectivelyBlocked(
        domain: 'static.doubleclick.net',
        customRules: [],
        disabledDefaultDomains: {},
        categoryPreferences: {'ads': true},
      );

      expect(isBlocked, isTrue);
    });

    test('unrelated clean domain is not blocked', () {
      final isBlocked = AuraDomainEvaluator.isEffectivelyBlocked(
        domain: 'flutter.dev',
        customRules: [],
        disabledDefaultDomains: {},
        categoryPreferences: {'ads': true, 'trackers': true, 'analytics': true},
      );

      expect(isBlocked, isFalse);
    });
  });
}
