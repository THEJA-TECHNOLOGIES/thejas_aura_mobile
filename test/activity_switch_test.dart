import 'package:flutter_test/flutter_test.dart';
import 'package:theja_aura/core/services/aura_activity_service.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';
import 'package:theja_aura/features/activity/domain/repositories/i_activity_repository.dart';
import 'package:theja_aura/features/activity/presentation/bloc/activity_bloc.dart';
import 'package:theja_aura/features/blocklist/domain/repositories/i_blocklist_repository.dart';

class FakeActivityRepository implements IActivityRepository {
  List<DnsActivityRecord> records = [];

  @override
  Future<PaginatedActivityResult> getActivity({
    int limit = 25,
    int? cursorTimestamp,
    int? cursorId,
    String? outcome,
    String? searchDomain,
    int? startTime,
  }) async {
    return PaginatedActivityResult(records: records, hasMore: false);
  }

  @override
  Future<bool> initializeDatabase({bool force = false}) async => true;

  @override
  Future<bool> checkpoint() async => true;

  @override
  Future<DashboardStatsData> getDashboardStats({
    required int timeWindowMillis,
  }) async {
    return DashboardStatsData(
      timeWindowMillis: timeWindowMillis,
      startTime: 0,
      endTime: 1000,
      totalQueries: records.length,
      totalBlocked: records.where((r) => r.isBlocked).length,
      totalAllowed: records.where((r) => r.isAllowed).length,
      totalFailed: 0,
      uniqueBlockedDomains: 0,
      uniqueDomainsTotal: 0,
    );
  }
}

class FakeBlocklistRepository implements IBlocklistRepository {
  List<AuraRuleItem> rules = [];
  Set<String> disabledOverrides = {};
  Map<String, bool> categories = {
    'Ads': true,
    'Trackers': true,
    'Analytics': true,
  };

  final List<String> recordedCalls = [];
  bool shouldThrowOnAdd = false;
  bool shouldThrowOnDelete = false;

  @override
  Future<List<AuraRuleItem>?> getRules() async {
    recordedCalls.add('getRules');
    return List.from(rules);
  }

  @override
  Future<Set<String>> getDefaultDomainOverrides() async {
    recordedCalls.add('getDefaultDomainOverrides');
    return Set.from(disabledOverrides);
  }

  @override
  Future<Map<String, bool>> getCategories() async {
    recordedCalls.add('getCategories');
    return Map.from(categories);
  }

  @override
  Future<AuraRuleItem> addRule({
    required String domain,
    required bool isBlocked,
    bool isEnabled = true,
  }) async {
    recordedCalls.add('addRule($domain, isBlocked: $isBlocked)');
    if (shouldThrowOnAdd) {
      throw Exception('Simulated addRule network/disk failure');
    }
    final rule = AuraRuleItem(
      id: 'rule-${rules.length + 1}',
      domain: domain,
      isBlocked: isBlocked,
      isEnabled: isEnabled,
    );
    rules.add(rule);
    return rule;
  }

  @override
  Future<AuraRuleItem> deleteRule(String id) async {
    recordedCalls.add('deleteRule($id)');
    if (shouldThrowOnDelete) {
      throw Exception('Simulated deleteRule failure');
    }
    final index = rules.indexWhere((r) => r.id == id);
    if (index != -1) {
      return rules.removeAt(index);
    }
    return AuraRuleItem(id: id, domain: id, isBlocked: true);
  }

  @override
  Future<Set<String>> toggleDefaultDomain({
    required String domain,
    required bool isEnabled,
  }) async {
    recordedCalls.add('toggleDefaultDomain($domain, isEnabled: $isEnabled)');
    if (isEnabled) {
      disabledOverrides.remove(domain);
    } else {
      disabledOverrides.add(domain);
    }
    return Set.from(disabledOverrides);
  }

  @override
  Future<AuraRuleItem> updateRule({
    required String id,
    String? domain,
    bool? isBlocked,
    bool? isEnabled,
  }) async {
    return AuraRuleItem(id: id, domain: domain ?? id);
  }

  @override
  Future<AuraRuleItem> toggleRule(String id, bool isEnabled) async {
    return AuraRuleItem(id: id, domain: id, isEnabled: isEnabled);
  }

  @override
  Future<String> validateDomain(String domain) async => domain;
}

void main() {
  group('ActivityBloc Domain Switch Integration', () {
    late FakeActivityRepository activityRepo;
    late FakeBlocklistRepository blocklistRepo;
    late ActivityBloc bloc;

    setUp(() {
      activityRepo = FakeActivityRepository();
      blocklistRepo = FakeBlocklistRepository();
      bloc = ActivityBloc(activityRepo, blocklistRepo);
    });

    tearDown(() {
      bloc.close();
    });

    test('Initial state: blocked domain displays ON and allowed domain displays OFF', () async {
      activityRepo.records = [
        const DnsActivityRecord(
          id: 1,
          domain: 'doubleclick.net',
          timestamp: 1000,
          queryType: 'A',
          outcome: 'blocked',
          matchedSource: 'default',
        ),
        const DnsActivityRecord(
          id: 2,
          domain: 'flutter.dev',
          timestamp: 2000,
          queryType: 'A',
          outcome: 'allowed',
          matchedSource: 'none',
        ),
      ];

      bloc.add(const ActivityEvent.started(isLogsMode: true));
      // Wait for initial load
      await Future.delayed(const Duration(milliseconds: 50));

      final state = bloc.state;
      expect(state.records.length, equals(2));

      // doubleclick.net is in bundled category Ads, and Ads is enabled -> blocked (switch ON)
      expect(state.isDomainBlocked('doubleclick.net'), isTrue);

      // flutter.dev is clean domain -> not blocked (switch OFF)
      expect(state.isDomainBlocked('flutter.dev'), isFalse);
    });

    test('Turning ON switch blocks an allowed domain via addRule', () async {
      activityRepo.records = [
        const DnsActivityRecord(
          id: 1,
          domain: 'example.com',
          timestamp: 1000,
          queryType: 'A',
          outcome: 'allowed',
          matchedSource: 'none',
        ),
      ];

      bloc.add(const ActivityEvent.started(isLogsMode: true));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.isDomainBlocked('example.com'), isFalse);

      // User turns ON the switch for example.com (requestedBlocked: true)
      bloc.add(
        const ActivityEvent.domainBlockToggled(
          domain: 'example.com',
          isBlocked: true,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 50));

      // Verify that addRule was called with isBlocked: true
      expect(
        blocklistRepo.recordedCalls,
        contains('addRule(example.com, isBlocked: true)'),
      );

      // Verify effective state is now blocked
      expect(bloc.state.isDomainBlocked('example.com'), isTrue);
      expect(bloc.state.pendingDomainToggles.contains('example.com'), isFalse);
    });

    test('Turning OFF switch allows a bundled domain via toggleDefaultDomain', () async {
      activityRepo.records = [
        const DnsActivityRecord(
          id: 1,
          domain: 'doubleclick.net',
          timestamp: 1000,
          queryType: 'A',
          outcome: 'blocked',
          matchedSource: 'default',
        ),
      ];

      bloc.add(const ActivityEvent.started(isLogsMode: true));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.isDomainBlocked('doubleclick.net'), isTrue);

      // User turns OFF the switch for doubleclick.net (requestedBlocked: false)
      bloc.add(
        const ActivityEvent.domainBlockToggled(
          domain: 'doubleclick.net',
          isBlocked: false,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 50));

      // Bundled domain was disabled
      expect(
        blocklistRepo.recordedCalls,
        contains('toggleDefaultDomain(doubleclick.net, isEnabled: false)'),
      );

      // Effective state is now unblocked (false)
      expect(bloc.state.isDomainBlocked('doubleclick.net'), isFalse);
      expect(
        bloc.state.pendingDomainToggles.contains('doubleclick.net'),
        isFalse,
      );
    });

    test('Turning OFF switch deletes custom block rule if present', () async {
      blocklistRepo.rules = [
        const AuraRuleItem(
          id: 'rule-custom-1',
          domain: 'badactor.com',
          isBlocked: true,
          isEnabled: true,
        ),
      ];
      activityRepo.records = [
        const DnsActivityRecord(
          id: 1,
          domain: 'badactor.com',
          timestamp: 1000,
          queryType: 'A',
          outcome: 'blocked',
          matchedSource: 'custom',
        ),
      ];

      bloc.add(const ActivityEvent.started(isLogsMode: true));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.isDomainBlocked('badactor.com'), isTrue);

      // User turns OFF switch
      bloc.add(
        const ActivityEvent.domainBlockToggled(
          domain: 'badactor.com',
          isBlocked: false,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 50));

      // Verify deleteRule was called for the custom block rule
      expect(
        blocklistRepo.recordedCalls,
        contains('deleteRule(rule-custom-1)'),
      );

      // Now unblocked
      expect(bloc.state.isDomainBlocked('badactor.com'), isFalse);
    });

    test(
      'Failure rollback reverts optimistic state and sets actionError',
      () async {
        blocklistRepo.shouldThrowOnAdd = true;
        activityRepo.records = [
          const DnsActivityRecord(
            id: 1,
            domain: 'flutter.dev',
            timestamp: 1000,
            queryType: 'A',
            outcome: 'allowed',
            matchedSource: 'none',
          ),
        ];

        bloc.add(const ActivityEvent.started(isLogsMode: true));
        await Future.delayed(const Duration(milliseconds: 50));

        expect(bloc.state.isDomainBlocked('flutter.dev'), isFalse);

        // User turns ON switch, but addRule will fail
        bloc.add(
          const ActivityEvent.domainBlockToggled(
            domain: 'flutter.dev',
            isBlocked: true,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 50));

        // State must be rolled back to false (NOT left in false success state)
        expect(bloc.state.isDomainBlocked('flutter.dev'), isFalse);
        expect(
          bloc.state.pendingDomainToggles.contains('flutter.dev'),
          isFalse,
        );
        expect(bloc.state.actionError, isNotNull);
        expect(
          bloc.state.actionError,
          contains('Failed to update domain preference'),
        );
      },
    );

    test(
      'In-flight toggle ignores rapid repeated clicks for the same domain',
      () async {
        activityRepo.records = [
          const DnsActivityRecord(
            id: 1,
            domain: 'rapidclick.org',
            timestamp: 1000,
            queryType: 'A',
            outcome: 'allowed',
            matchedSource: 'none',
          ),
        ];

        bloc.add(const ActivityEvent.started(isLogsMode: true));
        await Future.delayed(const Duration(milliseconds: 50));

        // Rapidly fire two toggle events before async operation completes
        bloc.add(
          const ActivityEvent.domainBlockToggled(
            domain: 'rapidclick.org',
            isBlocked: true,
          ),
        );
        bloc.add(
          const ActivityEvent.domainBlockToggled(
            domain: 'rapidclick.org',
            isBlocked: true,
          ),
        );

        await Future.delayed(const Duration(milliseconds: 100));

        // Should only have called addRule once
        final addCalls = blocklistRepo.recordedCalls
            .where((call) => call.contains('addRule(rapidclick.org'))
            .toList();
        expect(addCalls.length, equals(1));
      },
    );

    test('One domain toggle does not affect another domain', () async {
      activityRepo.records = [
        const DnsActivityRecord(
          id: 1,
          domain: 'first.org',
          timestamp: 1000,
          queryType: 'A',
          outcome: 'allowed',
          matchedSource: 'none',
        ),
        const DnsActivityRecord(
          id: 2,
          domain: 'second.org',
          timestamp: 2000,
          queryType: 'A',
          outcome: 'allowed',
          matchedSource: 'none',
        ),
      ];

      bloc.add(const ActivityEvent.started(isLogsMode: true));
      await Future.delayed(const Duration(milliseconds: 50));

      // Toggle first domain to blocked
      bloc.add(
        const ActivityEvent.domainBlockToggled(
          domain: 'first.org',
          isBlocked: true,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 50));

      // first.org is blocked, second.org remains allowed
      expect(bloc.state.isDomainBlocked('first.org'), isTrue);
      expect(bloc.state.isDomainBlocked('second.org'), isFalse);
    });
  });
}
