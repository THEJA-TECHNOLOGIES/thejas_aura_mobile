import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// Data model representing a recorded DNS activity event.
class DnsActivityRecord {
  final int id;
  final String domain;
  final int timestamp; // UTC Unix milliseconds
  final String queryType;
  final String outcome; // "blocked", "allowed", "failed"
  final String matchedSource; // "default", "custom", "allowlist", "none"
  final String? matchedRuleId;
  final List<String> matchedCategories;
  final String? reason;
  final String? appIdentifier;
  final String? appName;
  final String? appIconKey;

  const DnsActivityRecord({
    required this.id,
    required this.domain,
    required this.timestamp,
    required this.queryType,
    required this.outcome,
    required this.matchedSource,
    this.matchedRuleId,
    this.matchedCategories = const [],
    this.reason,
    this.appIdentifier,
    this.appName,
    this.appIconKey,
  });

  bool get isBlocked => outcome.toLowerCase() == 'blocked';
  bool get isAllowed => outcome.toLowerCase() == 'allowed';
  bool get isFailed => outcome.toLowerCase() == 'failed';

  DateTime get dateTime =>
      DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true).toLocal();

  factory DnsActivityRecord.fromMap(Map<String, dynamic> map) {
    final rawCats = map['matchedCategories'] ?? map['matched_categories'];
    List<String> categories = const [];
    if (rawCats is List) {
      categories = rawCats
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
    } else if (rawCats is String && rawCats.trim().isNotEmpty) {
      final trimmed = rawCats.trim();
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is List) {
            categories = decoded
                .map((e) => e?.toString().trim() ?? '')
                .where((e) => e.isNotEmpty)
                .toList();
          }
        } catch (_) {}
      }
      if (categories.isEmpty) {
        categories = trimmed
            .split(',')
            .map((e) => e.replaceAll('"', '').replaceAll("'", '').trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    }

    return DnsActivityRecord(
      id: (map['id'] as num?)?.toInt() ?? 0,
      domain: map['domain'] as String? ?? 'unknown',
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      queryType: map['queryType'] as String? ?? map['query_type'] as String? ?? 'A',
      outcome: map['outcome'] as String? ?? 'allowed',
      matchedSource: map['matchedSource'] as String? ?? map['matched_source'] as String? ?? 'none',
      matchedRuleId: map['matchedRuleId'] as String? ?? map['matched_rule_id'] as String?,
      matchedCategories: categories,
      reason: map['reason'] as String?,
      appIdentifier: map['appIdentifier'] as String? ?? map['app_identifier'] as String?,
      appName: map['appName'] as String? ?? map['app_name'] as String?,
      appIconKey: map['appIconKey'] as String? ?? map['app_icon_key'] as String?,
    );
  }
}

/// Paginated slice of activity records with cursor metadata.
class PaginatedActivityResult {
  final List<DnsActivityRecord> records;
  final int? nextCursorTimestamp;
  final int? nextCursorId;
  final bool hasMore;

  const PaginatedActivityResult({
    required this.records,
    this.nextCursorTimestamp,
    this.nextCursorId,
    required this.hasMore,
  });

  factory PaginatedActivityResult.fromMap(Map<String, dynamic> map) {
    final rawList = map['records'] as List<dynamic>? ?? const [];
    final records = rawList
        .map(
          (e) => DnsActivityRecord.fromMap(Map<String, dynamic>.from(e as Map)),
        )
        .toList();

    return PaginatedActivityResult(
      records: records,
      nextCursorTimestamp: (map['nextCursorTimestamp'] as num?)?.toInt(),
      nextCursorId: (map['nextCursorId'] as num?)?.toInt(),
      hasMore: map['hasMore'] as bool? ?? false,
    );
  }
}

/// Dashboard statistical totals for an explicit time window.
class DashboardStatsData {
  final int timeWindowMillis;
  final int startTime;
  final int endTime;
  final int totalQueries;
  final int totalBlocked;
  final int totalAllowed;
  final int totalFailed;
  final int uniqueBlockedDomains;
  final int uniqueDomainsTotal;

  const DashboardStatsData({
    required this.timeWindowMillis,
    required this.startTime,
    required this.endTime,
    required this.totalQueries,
    required this.totalBlocked,
    required this.totalAllowed,
    required this.totalFailed,
    required this.uniqueBlockedDomains,
    required this.uniqueDomainsTotal,
  });

  factory DashboardStatsData.fromMap(Map<String, dynamic> map) {
    return DashboardStatsData(
      timeWindowMillis: (map['timeWindowMillis'] as num).toInt(),
      startTime: (map['startTime'] as num).toInt(),
      endTime: (map['endTime'] as num).toInt(),
      totalQueries: (map['totalQueries'] as num).toInt(),
      totalBlocked: (map['totalBlocked'] as num).toInt(),
      totalAllowed: (map['totalAllowed'] as num).toInt(),
      totalFailed: (map['totalFailed'] as num).toInt(),
      uniqueBlockedDomains: (map['uniqueBlockedDomains'] as num).toInt(),
      uniqueDomainsTotal: (map['uniqueDomainsTotal'] as num).toInt(),
    );
  }

  double get blockPercentage =>
      totalQueries > 0 ? (totalBlocked / totalQueries) * 100.0 : 0.0;
}

/// Aggregated item for frequently blocked domains.
class TopBlockedDomainItem {
  final String domain;
  final int count;

  const TopBlockedDomainItem({required this.domain, required this.count});

  factory TopBlockedDomainItem.fromMap(Map<String, dynamic> map) {
    return TopBlockedDomainItem(
      domain: map['domain'] as String? ?? '',
      count: (map['count'] as num).toInt(),
    );
  }
}

/// Service wrapping the read-only native SQLite platform channel bridge.
class AuraActivityService {
  static const MethodChannel _activityChannel = MethodChannel(
    'com.thejatech.aura/activity',
  );

  Future<bool>? _initializationFuture;
  bool _isDatabaseReady = false;

  bool get isDatabaseReady => _isDatabaseReady;

  /// Ensures the native SQLite database is initialized in the shared App Group.
  /// Prevents concurrent callers from racing by caching and sharing the in-flight Future.
  Future<bool> initializeDatabase({bool force = false}) async {
    if (_isDatabaseReady && !force) return true;
    if (_initializationFuture != null && !force) {
      return _initializationFuture!;
    }

    _initializationFuture = () async {
      try {
        final dynamic res = await _activityChannel.invokeMethod<dynamic>(
          'initializeDatabase',
        );
        if (res is Map && res['ready'] == true) {
          _isDatabaseReady = true;
          return true;
        } else if (res == true) {
          _isDatabaseReady = true;
          return true;
        }
        _isDatabaseReady = false;
        return false;
      } catch (e) {
        _isDatabaseReady = false;
        _initializationFuture = null; // Allow retry on failure
        rethrow;
      }
    }();

    return _initializationFuture!;
  }

  /// Fetches a cursor-paginated page of activity records with optional filtering.
  Future<PaginatedActivityResult> getActivity({
    int limit = 25,
    int? cursorTimestamp,
    int? cursorId,
    String? outcome,
    String? searchDomain,
    int? startTime,
    int? endTime,
  }) async {
    await initializeDatabase();

    final Map<String, dynamic> args = {'limit': limit};
    if (cursorTimestamp != null) args['cursorTimestamp'] = cursorTimestamp;
    if (cursorId != null) args['cursorId'] = cursorId;
    if (outcome != null && outcome.isNotEmpty) args['outcome'] = outcome;
    if (searchDomain != null && searchDomain.isNotEmpty) {
      args['searchDomain'] = searchDomain;
    }
    if (startTime != null) args['startTime'] = startTime;
    if (endTime != null) args['endTime'] = endTime;

    final dynamic res = await _activityChannel.invokeMethod<dynamic>(
      'getActivity',
      args,
    );
    if (res is Map) {
      return PaginatedActivityResult.fromMap(Map<String, dynamic>.from(res));
    }
    return const PaginatedActivityResult(records: [], hasMore: false);
  }

  /// Computes dashboard totals and distinct counts for a specific time window.
  Future<DashboardStatsData> getDashboardStats({
    int timeWindowMillis = 86400000,
  }) async {
    await initializeDatabase();

    final dynamic res = await _activityChannel.invokeMethod<dynamic>(
      'getDashboardStats',
      {'timeWindowMillis': timeWindowMillis},
    );
    if (res is Map) {
      return DashboardStatsData.fromMap(Map<String, dynamic>.from(res));
    }
    throw StateError('Invalid response from getDashboardStats');
  }

  /// Retrieves frequently blocked domains for a given time window.
  Future<List<TopBlockedDomainItem>> getTopBlockedDomains({
    int limit = 5,
    int? timeWindowMillis,
  }) async {
    await initializeDatabase();
    final Map<String, dynamic> args = {'limit': limit};
    if (timeWindowMillis != null) args['timeWindowMillis'] = timeWindowMillis;

    final dynamic res = await _activityChannel.invokeMethod<dynamic>(
      'getTopBlockedDomains',
      args,
    );
    if (res is List) {
      return res
          .map(
            (e) => TopBlockedDomainItem.fromMap(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    }
    return const [];
  }

  /// Triggers a non-blocking passive WAL checkpoint in the Runner process.
  Future<bool> checkpoint() async {
    try {
      final bool? res = await _activityChannel.invokeMethod<bool>('checkpoint');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}
