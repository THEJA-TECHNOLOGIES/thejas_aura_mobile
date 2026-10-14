import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:theja_aura/core/services/aura_activity_service.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';
import 'package:theja_aura/features/activity/domain/repositories/i_activity_repository.dart';
import 'package:theja_aura/features/activity/presentation/bloc/activity_bloc.dart';
import 'package:theja_aura/features/blocklist/domain/repositories/i_blocklist_repository.dart';
import 'package:theja_aura/features/blocklist/presentation/bloc/blocklist_bloc.dart';
import 'package:theja_aura/features/dashboard/domain/models/dashboard_stats.dart';
import 'package:theja_aura/features/dashboard/domain/repositories/i_dashboard_repository.dart';
import 'package:theja_aura/features/dashboard/presentation/bloc/dashboard_bloc.dart';

class FakeDashboardRepository implements IDashboardRepository {
  final _statusController = StreamController<TunnelStatus>.broadcast();
  TunnelStatus currentStatus = TunnelStatus.disconnected;
  DashboardStats currentStats = const DashboardStats(
    blockedToday: 12,
    blockedThisWeek: 45,
    totalBlockedDomains: 8,
  );
  bool shouldThrowOnToggle = false;

  @override
  Stream<TunnelStatus> get tunnelStatusStream => _statusController.stream;

  @override
  Future<TunnelStatus> getTunnelStatus() async => currentStatus;

  @override
  Future<DashboardStats> getDashboardStats() async => currentStats;

  @override
  Future<void> startTunnel() async {
    if (shouldThrowOnToggle) throw Exception('Failed to start tunnel');
    currentStatus = TunnelStatus.connected;
    _statusController.add(currentStatus);
  }

  @override
  Future<void> stopTunnel() async {
    if (shouldThrowOnToggle) throw Exception('Failed to stop tunnel');
    currentStatus = TunnelStatus.disconnected;
    _statusController.add(currentStatus);
  }

  void emitStatus(TunnelStatus status) {
    currentStatus = status;
    _statusController.add(status);
  }

  void dispose() {
    _statusController.close();
  }
}

class FakeActivityRepository implements IActivityRepository {
  PaginatedActivityResult result = PaginatedActivityResult(
    records: [
      DnsActivityRecord(
        id: 1,
        timestamp: 1000,
        domain: 'tracker.com',
        queryType: 'A',
        outcome: 'blocked',
        matchedSource: 'default',
        reason: 'Blocked by Trackers',
      ),
    ],
    hasMore: true,
    nextCursorTimestamp: 1000,
    nextCursorId: 1,
  );

  bool shouldThrow = false;
  String? lastOutcome;
  String? lastSearch;

  @override
  Future<PaginatedActivityResult> getActivity({
    int limit = 25,
    int? cursorTimestamp,
    int? cursorId,
    String? outcome,
    String? searchDomain,
    int? startTime,
  }) async {
    if (shouldThrow) throw Exception('Database read error');
    lastOutcome = outcome;
    lastSearch = searchDomain;
    return result;
  }

  @override
  Future<bool> checkpoint() async => true;

  @override
  Future<DashboardStatsData> getDashboardStats({
    required int timeWindowMillis,
  }) async {
    return const DashboardStatsData(
      timeWindowMillis: 86400000,
      startTime: 0,
      endTime: 86400000,
      totalQueries: 100,
      totalBlocked: 20,
      totalAllowed: 80,
      totalFailed: 0,
      uniqueBlockedDomains: 5,
      uniqueDomainsTotal: 30,
    );
  }
}

class FakeBlocklistRepository implements IBlocklistRepository {
  Set<String> overrides = {'ads.example.com'};
  List<AuraRuleItem> rules = [
    const AuraRuleItem(
      id: 'rule-1',
      domain: 'custom-block.com',
      isBlocked: true,
      isEnabled: true,
    ),
  ];
  bool shouldThrow = false;

  @override
  Future<Set<String>> getDefaultDomainOverrides() async {
    if (shouldThrow) throw Exception('Storage error');
    return overrides;
  }

  @override
  Future<Set<String>> toggleDefaultDomain({
    required String domain,
    required bool isEnabled,
  }) async {
    if (shouldThrow) throw Exception('Toggle error');
    final updated = Set<String>.from(overrides);
    if (isEnabled) {
      updated.remove(domain);
    } else {
      updated.add(domain);
    }
    overrides = updated;
    return overrides;
  }

  @override
  Future<List<AuraRuleItem>?> getRules() async {
    if (shouldThrow) throw Exception('Rules fetch error');
    return rules;
  }

  @override
  Future<AuraRuleItem> addRule({
    required String domain,
    required bool isBlocked,
    bool isEnabled = true,
  }) async {
    if (shouldThrow) throw Exception('Add rule error');
    final item = AuraRuleItem(
      id: 'rule-${rules.length + 1}',
      domain: domain,
      isBlocked: isBlocked,
      isEnabled: isEnabled,
    );
    rules = [item, ...rules];
    return item;
  }

  @override
  Future<AuraRuleItem> updateRule({
    required String id,
    String? domain,
    bool? isBlocked,
    bool? isEnabled,
  }) async {
    final index = rules.indexWhere((r) => r.id == id);
    final updated = AuraRuleItem(
      id: id,
      domain: domain ?? rules[index].domain,
      isBlocked: isBlocked ?? rules[index].isBlocked,
      isEnabled: isEnabled ?? rules[index].isEnabled,
    );
    rules[index] = updated;
    return updated;
  }

  @override
  Future<AuraRuleItem> deleteRule(String id) async {
    if (shouldThrow) throw Exception('Delete rule error');
    final item = rules.firstWhere((r) => r.id == id);
    rules = rules.where((r) => r.id != id).toList();
    return item;
  }

  @override
  Future<AuraRuleItem> toggleRule(String id, bool isEnabled) async {
    final index = rules.indexWhere((r) => r.id == id);
    final updated = AuraRuleItem(
      id: id,
      domain: rules[index].domain,
      isBlocked: rules[index].isBlocked,
      isEnabled: isEnabled,
    );
    rules[index] = updated;
    return updated;
  }

  @override
  Future<String> validateDomain(String domain) async => domain;
}

void main() {
  group('DashboardBloc Tests', () {
    late FakeDashboardRepository repository;
    late DashboardBloc bloc;

    setUp(() {
      repository = FakeDashboardRepository();
      bloc = DashboardBloc(repository);
    });

    tearDown(() async {
      await bloc.close();
      repository.dispose();
    });

    test('Initial state is correct', () {
      expect(bloc.state.status, TunnelStatus.disconnected);
      expect(bloc.state.isTogglingTunnel, isFalse);
      expect(bloc.state.errorMessage, isNull);
    });

    test(
      'Started event initializes tunnel status and fetches statistics',
      () async {
        bloc.add(const DashboardEvent.started());
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(bloc.state.status, TunnelStatus.disconnected);
        expect(bloc.state.blockedToday, 12);
        expect(bloc.state.blockedThisWeek, 45);
        expect(bloc.state.totalBlockedDomains, 8);
      },
    );

    test('Tunnel status stream updates state', () async {
      bloc.add(const DashboardEvent.started());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      repository.emitStatus(TunnelStatus.connected);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.status, TunnelStatus.connected);
    });

    test('Tunnel toggle starts disconnected tunnel', () async {
      bloc.add(const DashboardEvent.started());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      bloc.add(const DashboardEvent.tunnelToggled());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(repository.currentStatus, TunnelStatus.connected);
    });

    test(
      'Tunnel toggle error emits error message and resets loading',
      () async {
        bloc.add(const DashboardEvent.started());
        await Future<void>.delayed(const Duration(milliseconds: 50));

        repository.shouldThrowOnToggle = true;
        bloc.add(const DashboardEvent.tunnelToggled());
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(bloc.state.isTogglingTunnel, isFalse);
        expect(bloc.state.errorMessage, contains('Failed to start tunnel'));

        // Dismiss error
        bloc.add(const DashboardEvent.errorMessageDismissed());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(bloc.state.errorMessage, isNull);
      },
    );
  });

  group('ActivityBloc Tests', () {
    late FakeActivityRepository repository;
    late ActivityBloc bloc;

    setUp(() {
      repository = FakeActivityRepository();
      bloc = ActivityBloc(repository);
    });

    tearDown(() async {
      await bloc.close();
    });

    test('Initial state is empty', () {
      expect(bloc.state.records, isEmpty);
      expect(bloc.state.isLoading, isFalse);
      expect(bloc.state.errorMessage, isNull);
    });

    test('Started event loads initial page', () async {
      bloc.add(const ActivityEvent.started());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.records.length, 1);
      expect(bloc.state.records.first.domain, 'tracker.com');
      expect(bloc.state.hasMore, isTrue);
    });

    test('Filter outcome updates and queries repository', () async {
      bloc.add(const ActivityEvent.outcomeFilterChanged('blocked'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.selectedOutcome, 'blocked');
      expect(repository.lastOutcome, 'blocked');
    });

    test('Search debouncing queries after delay', () async {
      bloc.add(const ActivityEvent.searchQueryChanged('tracker'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // Should not have queried yet due to 350ms debounce
      expect(repository.lastSearch, isNull);

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(repository.lastSearch, 'tracker');
    });

    test('Load more appends next page', () async {
      bloc.add(const ActivityEvent.started());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      repository.result = PaginatedActivityResult(
        records: [
          DnsActivityRecord(
            id: 2,
            timestamp: 900,
            domain: 'analytics.com',
            queryType: 'A',
            outcome: 'allowed',
            matchedSource: 'default',
          ),
        ],
        hasMore: false,
        nextCursorTimestamp: null,
        nextCursorId: null,
      );

      bloc.add(const ActivityEvent.loadMoreRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.records.length, 2);
      expect(bloc.state.hasMore, isFalse);
    });

    test('Error during fetch updates errorMessage', () async {
      repository.shouldThrow = true;
      bloc.add(const ActivityEvent.refreshRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.errorMessage, contains('Database read error'));
      expect(bloc.state.isLoading, isFalse);
    });
  });

  group('BlocklistBloc Tests', () {
    late FakeBlocklistRepository repository;
    late BlocklistBloc bloc;

    setUp(() {
      repository = FakeBlocklistRepository();
      bloc = BlocklistBloc(repository);
    });

    tearDown(() async {
      await bloc.close();
    });

    test('Started event loads overrides and custom rules', () async {
      bloc.add(const BlocklistEvent.started());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.disabledDefaultDomains, contains('ads.example.com'));
      expect(bloc.state.customRules.length, 1);
      expect(bloc.state.customRules.first.domain, 'custom-block.com');
    });

    test(
      'Default domain toggled updates overrides optimistically and persists',
      () async {
        bloc.add(const BlocklistEvent.started());
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Enable the domain (removes from disabled set)
        bloc.add(
          const BlocklistEvent.defaultDomainToggled(
            domain: 'ads.example.com',
            isEnabled: true,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          bloc.state.disabledDefaultDomains,
          isNot(contains('ads.example.com')),
        );
      },
    );

    test('Add custom rule dispatches event and resolves completer', () async {
      bloc.add(const BlocklistEvent.started());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final success = await bloc.addRule(
        domain: 'bad-site.com',
        isBlocked: true,
      );
      expect(success, isTrue);
      expect(
        bloc.state.customRules.any((r) => r.domain == 'bad-site.com'),
        isTrue,
      );
    });

    test(
      'Delete custom rule dispatches event and resolves completer',
      () async {
        bloc.add(const BlocklistEvent.started());
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final success = await bloc.deleteRule('rule-1');
        expect(success, isTrue);
        expect(bloc.state.customRules.any((r) => r.id == 'rule-1'), isFalse);
      },
    );

    test('Action error dismissed clears error state', () async {
      repository.shouldThrow = true;
      final completer = Completer<bool>();
      bloc.add(
        BlocklistEvent.customRuleAddRequested(
          domain: 'fail.com',
          isBlocked: true,
          completer: completer,
        ),
      );
      final result = await completer.future;
      expect(result, isFalse);
      expect(bloc.state.actionError, isNotNull);

      bloc.add(const BlocklistEvent.actionErrorDismissed());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bloc.state.actionError, isNull);
    });
  });
}
