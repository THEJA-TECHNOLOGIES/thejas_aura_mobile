import 'package:flutter_test/flutter_test.dart';
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
      'category blocks domain when category is enabled with category domains passed',
      () {
        const testCategoryDomains = {
          'ads': {'doubleclick.net'},
        };

        final isBlocked = AuraDomainEvaluator.isEffectivelyBlocked(
          domain: 'doubleclick.net',
          customRules: [],
          disabledDefaultDomains: {},
          categoryPreferences: {'ads': true},
          categoryDomains: testCategoryDomains,
        );

        expect(isBlocked, isTrue);
      },
    );

    test('first launch or empty release does not block domains via categories', () {
      final isBlocked = AuraDomainEvaluator.isEffectivelyBlocked(
        domain: 'doubleclick.net',
        customRules: [],
        disabledDefaultDomains: {},
        categoryPreferences: {'ads': true},
        categoryDomains: const {},
      );

      expect(isBlocked, isFalse);
    });

    test('category does not block domain when category is disabled', () {
      const testCategoryDomains = {
        'ads': {'doubleclick.net'},
      };

      final isBlocked = AuraDomainEvaluator.isEffectivelyBlocked(
        domain: 'doubleclick.net',
        customRules: [],
        disabledDefaultDomains: {},
        categoryPreferences: {'ads': false},
        categoryDomains: testCategoryDomains,
      );

      expect(isBlocked, isFalse);
    });

    test('default domain override allows specific domain while category is enabled', () {
      const testCategoryDomains = {
        'ads': {'doubleclick.net'},
      };

      final isBlocked = AuraDomainEvaluator.isEffectivelyBlocked(
        domain: 'doubleclick.net',
        customRules: [],
        disabledDefaultDomains: {'doubleclick.net'},
        categoryPreferences: {'ads': true},
        categoryDomains: testCategoryDomains,
      );

      expect(isBlocked, isFalse);
    });

    test('subdomain inherits category block from parent domain', () {
      const testCategoryDomains = {
        'ads': {'doubleclick.net'},
      };

      final isBlocked = AuraDomainEvaluator.isEffectivelyBlocked(
        domain: 'static.doubleclick.net',
        customRules: [],
        disabledDefaultDomains: {},
        categoryPreferences: {'ads': true},
        categoryDomains: testCategoryDomains,
      );

      expect(isBlocked, isTrue);
    });

    test('unrelated clean domain is not blocked', () {
      const testCategoryDomains = {
        'ads': {'doubleclick.net'},
      };

      final isBlocked = AuraDomainEvaluator.isEffectivelyBlocked(
        domain: 'flutter.dev',
        customRules: [],
        disabledDefaultDomains: {},
        categoryPreferences: {'ads': true, 'trackers': true, 'analytics': true},
        categoryDomains: testCategoryDomains,
      );

      expect(isBlocked, isFalse);
    });
  });
}
