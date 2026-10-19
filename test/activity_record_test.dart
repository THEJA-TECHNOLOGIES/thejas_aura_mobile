import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:theja_aura/core/services/aura_activity_service.dart';

void main() {
  group('DnsActivityRecord.fromMap', () {
    test('parses camelCase keys with List of categories', () {
      final map = {
        'id': 1,
        'domain': 'doubleclick.net',
        'timestamp': 1700000000000,
        'queryType': 'A',
        'outcome': 'blocked',
        'matchedSource': 'default',
        'matchedRuleId': 'rule-1',
        'matchedCategories': ['Ads', 'Trackers'],
        'reason': 'Blocked by default list',
        'appIdentifier': 'com.apple.mobilesafari',
        'appName': 'Safari',
        'appIconKey': 'safari_icon',
      };

      final record = DnsActivityRecord.fromMap(map);
      expect(record.id, equals(1));
      expect(record.domain, equals('doubleclick.net'));
      expect(record.timestamp, equals(1700000000000));
      expect(record.queryType, equals('A'));
      expect(record.outcome, equals('blocked'));
      expect(record.matchedSource, equals('default'));
      expect(record.matchedRuleId, equals('rule-1'));
      expect(record.matchedCategories, equals(['Ads', 'Trackers']));
      expect(record.reason, equals('Blocked by default list'));
      expect(record.appIdentifier, equals('com.apple.mobilesafari'));
      expect(record.appName, equals('Safari'));
      expect(record.appIconKey, equals('safari_icon'));
      expect(record.isBlocked, isTrue);
      expect(record.isAllowed, isFalse);
    });

    test('parses snake_case keys with List of categories', () {
      final map = {
        'id': 2,
        'domain': 'google.com',
        'timestamp': 1700000001000,
        'query_type': 'AAAA',
        'outcome': 'allowed',
        'matched_source': 'none',
        'matched_rule_id': null,
        'matched_categories': ['Analytics'],
        'reason': null,
        'app_identifier': 'com.google.chrome',
        'app_name': 'Chrome',
        'app_icon_key': 'chrome_icon',
      };

      final record = DnsActivityRecord.fromMap(map);
      expect(record.id, equals(2));
      expect(record.domain, equals('google.com'));
      expect(record.queryType, equals('AAAA'));
      expect(record.outcome, equals('allowed'));
      expect(record.matchedSource, equals('none'));
      expect(record.matchedCategories, equals(['Analytics']));
      expect(record.appIdentifier, equals('com.google.chrome'));
      expect(record.appName, equals('Chrome'));
      expect(record.isAllowed, isTrue);
      expect(record.isBlocked, isFalse);
    });

    test('parses JSON array string in matched_categories', () {
      final map = {
        'id': 3,
        'domain': 'tracker.org',
        'timestamp': 1700000002000,
        'query_type': 'A',
        'outcome': 'blocked',
        'matched_source': 'default',
        'matched_categories': '["Ads", "Trackers", "Analytics"]',
      };

      final record = DnsActivityRecord.fromMap(map);
      expect(record.matchedCategories, equals(['Ads', 'Trackers', 'Analytics']));
    });

    test('parses comma-separated string in matched_categories', () {
      final map = {
        'id': 4,
        'domain': 'ads.example.com',
        'timestamp': 1700000003000,
        'queryType': 'A',
        'outcome': 'blocked',
        'matchedSource': 'default',
        'matched_categories': 'Ads, Trackers',
      };

      final record = DnsActivityRecord.fromMap(map);
      expect(record.matchedCategories, equals(['Ads', 'Trackers']));
    });

    test('parses single string in matched_categories', () {
      final map = {
        'id': 5,
        'domain': 'ads.example.com',
        'timestamp': 1700000004000,
        'queryType': 'A',
        'outcome': 'blocked',
        'matchedSource': 'default',
        'matched_categories': 'Ads',
      };

      final record = DnsActivityRecord.fromMap(map);
      expect(record.matchedCategories, equals(['Ads']));
    });

    test('handles empty and null matched_categories gracefully', () {
      final nullMap = {
        'id': 6,
        'domain': 'clean.org',
        'timestamp': 1700000005000,
        'outcome': 'allowed',
        'matched_categories': null,
      };

      final emptyListMap = {
        'id': 7,
        'domain': 'clean.org',
        'timestamp': 1700000006000,
        'outcome': 'allowed',
        'matchedCategories': <String>[],
      };

      final emptyStringMap = {
        'id': 8,
        'domain': 'clean.org',
        'timestamp': 1700000007000,
        'outcome': 'allowed',
        'matched_categories': '',
      };

      expect(DnsActivityRecord.fromMap(nullMap).matchedCategories, isEmpty);
      expect(DnsActivityRecord.fromMap(emptyListMap).matchedCategories, isEmpty);
      expect(DnsActivityRecord.fromMap(emptyStringMap).matchedCategories, isEmpty);
    });
  });
}
