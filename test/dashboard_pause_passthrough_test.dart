import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/features/dashboard/domain/models/dashboard_stats.dart';
import 'package:theja_aura/features/dashboard/domain/repositories/i_dashboard_repository.dart';
import 'package:theja_aura/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/firewall_controller.dart';

class MockDashboardRepository implements IDashboardRepository {
  TunnelStatus _currentStatus = TunnelStatus.connected;
  VpnPolicy _currentPolicy = const VpnPolicy(mode: VpnPolicyMode.enabled);
  final StreamController<TunnelStatus> _statusStreamController =
      StreamController<TunnelStatus>.broadcast();

  int startTunnelCallCount = 0;
  int stopTunnelCallCount = 0;
  int pauseTunnelCallCount = 0;
  int shutdownTunnelCallCount = 0;

  @override
  Stream<TunnelStatus> get tunnelStatusStream => _statusStreamController.stream;

  @override
  Future<TunnelStatus> getTunnelStatus() async => _currentStatus;

  @override
  Future<VpnPolicy> getVpnPolicy() async {
    // Simulate native layer pause expiry reconciliation
    final expiry = _currentPolicy.pauseExpiryUtcMillis;
    if (_currentPolicy.mode == VpnPolicyMode.paused &&
        expiry != null &&
        expiry > 0 &&
        _currentPolicy.remainingPauseDuration == Duration.zero) {
      _currentPolicy = const VpnPolicy(mode: VpnPolicyMode.enabled);
    }
    return _currentPolicy;
  }

  @override
  Future<void> startTunnel() async {
    startTunnelCallCount++;
    _currentStatus = TunnelStatus.connected;
    _currentPolicy = const VpnPolicy(mode: VpnPolicyMode.enabled);
    _statusStreamController.add(_currentStatus);
  }

  @override
  Future<void> stopTunnel() async {
    stopTunnelCallCount++;
    _currentStatus = TunnelStatus.disconnected;
    _statusStreamController.add(_currentStatus);
  }

  @override
  Future<void> pauseTunnel(Duration duration) async {
    pauseTunnelCallCount++;
    // Passthrough: tunnel remains CONNECTED
    _currentStatus = TunnelStatus.connected;
    final expiryUtc = DateTime.now().toUtc().add(duration).millisecondsSinceEpoch;
    _currentPolicy = VpnPolicy(
      mode: VpnPolicyMode.paused,
      pauseExpiryUtcMillis: expiryUtc,
      isAutoRecoveryPermitted: true,
    );
    _statusStreamController.add(_currentStatus);
  }

  @override
  Future<void> shutdownTunnel() async {
    shutdownTunnelCallCount++;
    _currentStatus = TunnelStatus.disconnected;
    _currentPolicy = const VpnPolicy(mode: VpnPolicyMode.manuallyDisabled);
    _statusStreamController.add(_currentStatus);
  }

  @override
  Future<DashboardStats> getDashboardStats() async {
    return const DashboardStats(
      blockedToday: 10,
      blockedThisWeek: 50,
      totalBlockedDomains: 100,
      dailyBlockedActivity: [],
    );
  }

  @override
  Future<String> getTunnelDiagnostics() async => '';

  @override
  Future<bool> clearTunnelDiagnostics() async => true;

  @override
  Future<bool> isAlwaysOnActive() async => false;

  @override
  Future<void> openVpnSettings() async {}

  void dispose() {
    _statusStreamController.close();
  }
}

class FakeDashboardBloc extends Bloc<DashboardEvent, DashboardState>
    implements DashboardBloc {
  final List<DashboardEvent> dispatchedEvents = [];

  FakeDashboardBloc(super.initialState) : super() {
    on<DashboardEvent>((event, emit) {
      dispatchedEvents.add(event);
    });
  }

  @override
  VpnPolicy get policy => state.policy;

  int pauseCalled = 0;
  int shutdownCalled = 0;
  int openVpnSettingsCalled = 0;

  @override
  Future<void> pauseTunnel(Duration duration) async {
    pauseCalled++;
  }

  @override
  Future<void> shutdownTunnel() async {
    shutdownCalled++;
  }

  @override
  Future<void> openVpnSettings() async {
    openVpnSettingsCalled++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VpnPolicy Domain Logic', () {
    test('future expiry marks policy as paused with positive remaining duration', () {
      final futureExpiry =
          DateTime.now().toUtc().millisecondsSinceEpoch + 60000;
      final policy = VpnPolicy(
        mode: VpnPolicyMode.paused,
        pauseExpiryUtcMillis: futureExpiry,
      );

      expect(policy.isPaused, isTrue);
      expect(policy.remainingPauseDuration.inMilliseconds, greaterThan(0));
      expect(policy.isExplicitlyEnabled, isFalse);
      expect(policy.isManuallyDisabled, isFalse);
    });

    test('past expiry automatically expires pause with Duration.zero remaining', () {
      final pastExpiry =
          DateTime.now().toUtc().millisecondsSinceEpoch - 1000;
      final policy = VpnPolicy(
        mode: VpnPolicyMode.paused,
        pauseExpiryUtcMillis: pastExpiry,
      );

      expect(policy.isPaused, isFalse);
      expect(policy.remainingPauseDuration, equals(Duration.zero));
    });

    test('enabled mode is not paused and explicitly enabled', () {
      const policy = VpnPolicy(mode: VpnPolicyMode.enabled);
      expect(policy.isPaused, isFalse);
      expect(policy.isExplicitlyEnabled, isTrue);
      expect(policy.isManuallyDisabled, isFalse);
    });

    test('manually disabled mode is not paused and is manually disabled', () {
      const policy = VpnPolicy(mode: VpnPolicyMode.manuallyDisabled);
      expect(policy.isPaused, isFalse);
      expect(policy.isExplicitlyEnabled, isFalse);
      expect(policy.isManuallyDisabled, isTrue);
    });
  });

  group('DashboardBloc Persistent Pause Passthrough & Recovery', () {
    late MockDashboardRepository repository;
    late DashboardBloc bloc;

    setUp(() {
      repository = MockDashboardRepository();
      bloc = DashboardBloc(repository);
    });

    tearDown(() {
      bloc.close();
      repository.dispose();
    });

    test('pauseTunnel keeps tunnel CONNECTED and sets policy to paused', () async {
      bloc.add(const DashboardEvent.started());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.status, equals(TunnelStatus.connected));
      expect(bloc.state.policy.mode, equals(VpnPolicyMode.enabled));

      await bloc.pauseTunnel(const Duration(minutes: 30));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Tunnel must NOT disconnect in passthrough mode!
      expect(bloc.state.status, equals(TunnelStatus.connected));
      expect(bloc.state.policy.isPaused, isTrue);
      expect(bloc.state.policy.mode, equals(VpnPolicyMode.paused));
      expect(repository.pauseTunnelCallCount, equals(1));
      expect(repository.stopTunnelCallCount, equals(0));
    });

    test('tapping hero while paused immediately resumes protection without restarting tunnel', () async {
      bloc.add(const DashboardEvent.started());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await bloc.pauseTunnel(const Duration(minutes: 30));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state.policy.isPaused, isTrue);

      // User taps hero button while paused -> tunnelToggled
      bloc.add(const DashboardEvent.tunnelToggled());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Protection is resumed immediately: startTunnel called (reload policy), stopTunnel NOT called
      expect(bloc.state.status, equals(TunnelStatus.connected));
      expect(bloc.state.policy.isPaused, isFalse);
      expect(bloc.state.policy.mode, equals(VpnPolicyMode.enabled));
      expect(repository.startTunnelCallCount, equals(1));
      expect(repository.stopTunnelCallCount, equals(0));
    });

    test('shutdownTunnel stops the tunnel and transitions policy to manuallyDisabled', () async {
      bloc.add(const DashboardEvent.started());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await bloc.shutdownTunnel();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.status, equals(TunnelStatus.disconnected));
      expect(bloc.state.policy.isManuallyDisabled, isTrue);
      expect(bloc.state.policy.isPaused, isFalse);
      expect(repository.shutdownTunnelCallCount, equals(1));
    });

    test('app resume when pause expired reconciles policy back to enabled', () async {
      // Simulate expired pause
      repository._currentStatus = TunnelStatus.connected;
      repository._currentPolicy = VpnPolicy(
        mode: VpnPolicyMode.paused,
        pauseExpiryUtcMillis: DateTime.now().toUtc().millisecondsSinceEpoch - 5000,
      );

      bloc.add(const DashboardEvent.appResumed());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.policy.mode, equals(VpnPolicyMode.enabled));
      // Native layer handles pause expiry reconciliation; Flutter should NOT call startTunnel
      expect(repository.startTunnelCallCount, equals(0));
    });
  });

  group('FirewallController UI Widget Tests', () {
    testWidgets('displays active protection when tunnel is connected and enabled', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeBloc = FakeDashboardBloc(
        const DashboardState(
          isInitialized: true,
          status: TunnelStatus.connected,
          policy: VpnPolicy(mode: VpnPolicyMode.enabled),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: BlocProvider<DashboardBloc>.value(
              value: fakeBloc,
              child: const FirewallController(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text("You're protected"), findsOneWidget);
      expect(find.text('Local filtering active'), findsOneWidget);
    });

    testWidgets('displays paused protection and remaining time when paused with active tunnel', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final futureExpiry =
          DateTime.now().toUtc().add(const Duration(minutes: 30)).millisecondsSinceEpoch;
      final fakeBloc = FakeDashboardBloc(
        DashboardState(
          isInitialized: true,
          status: TunnelStatus.connected,
          policy: VpnPolicy(
            mode: VpnPolicyMode.paused,
            pauseExpiryUtcMillis: futureExpiry,
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: BlocProvider<DashboardBloc>.value(
              value: fakeBloc,
              child: const FirewallController(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Protection is paused'), findsOneWidget);
      expect(find.textContaining('Tap to resume'), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);
    });

    testWidgets('tapping power button while paused dispatches tunnelToggled to resume immediately', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final futureExpiry =
          DateTime.now().toUtc().add(const Duration(minutes: 30)).millisecondsSinceEpoch;
      final fakeBloc = FakeDashboardBloc(
        DashboardState(
          isInitialized: true,
          status: TunnelStatus.connected,
          policy: VpnPolicy(
            mode: VpnPolicyMode.paused,
            pauseExpiryUtcMillis: futureExpiry,
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: BlocProvider<DashboardBloc>.value(
              value: fakeBloc,
              child: const FirewallController(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Protection is paused'), findsOneWidget);

      // Tap the power button
      await tester.tap(find.byType(GestureDetector));
      await tester.pump();

      // Verified: dispatches tunnelToggled (which resumes protection immediately)
      expect(fakeBloc.dispatchedEvents, contains(const DashboardEvent.tunnelToggled()));
    });

    testWidgets('displays manually disabled protection when tunnel is disconnected', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeBloc = FakeDashboardBloc(
        const DashboardState(
          isInitialized: true,
          status: TunnelStatus.disconnected,
          policy: VpnPolicy(mode: VpnPolicyMode.manuallyDisabled),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: BlocProvider<DashboardBloc>.value(
              value: fakeBloc,
              child: const FirewallController(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Protection is off'), findsOneWidget);
      expect(find.text('Tap the button to raise the wall.'), findsOneWidget);
      expect(find.text('Not filtering'), findsOneWidget);
    });
  });
}
