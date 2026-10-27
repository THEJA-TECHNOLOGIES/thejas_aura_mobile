import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';

import '../../domain/repositories/i_dashboard_repository.dart';
import 'dashboard_event.dart';
import 'dashboard_state.dart';

export 'package:theja_aura/core/services/aura_tunnel_service.dart'
    show TunnelStatus;

export 'dashboard_event.dart';
export 'dashboard_state.dart';

@injectable
class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  final IDashboardRepository _repository;
  StreamSubscription<TunnelStatus>? _statusSubscription;
  Timer? _pauseTimer;
  VpnPolicy _policy = const VpnPolicy();

  VpnPolicy get policy => _policy;

  DashboardBloc(this._repository) : super(const DashboardState()) {
    on<DashboardEvent>((event, emit) async {
      await event.when(
        started: () => _onStarted(emit),
        tunnelStatusUpdated: (status) => _onTunnelStatusUpdated(status, emit),
        tunnelToggled: () => _onTunnelToggled(emit),
        statsRefreshRequested: () => _onStatsRefreshRequested(emit),
        appResumed: () => _onAppResumed(emit),
        errorMessageDismissed: () async => _onErrorMessageDismissed(emit),
      );
    });
  }

  Future<void> _onStarted(Emitter<DashboardState> emit) async {
    await _statusSubscription?.cancel();
    _statusSubscription = _repository.tunnelStatusStream.listen((newStatus) {
      add(DashboardEvent.tunnelStatusUpdated(newStatus));
    });

    _policy = await _repository.getVpnPolicy();
    if (_policy.mode == VpnPolicyMode.paused) {
      final remaining = _policy.remainingPauseDuration;
      if (remaining == Duration.zero) {
        // Pause expired while app was closed: attempt automatic reconnection
        try {
          await _repository.startTunnel();
          _policy = await _repository.getVpnPolicy();
        } catch (_) {}
      } else {
        _schedulePauseTimer(remaining);
      }
    }

    final currentStatus = await _repository.getTunnelStatus();
    emit(state.copyWith(status: currentStatus, isInitialized: true));

    await _fetchStats(emit);
  }

  Future<void> _onTunnelStatusUpdated(
    TunnelStatus status,
    Emitter<DashboardState> emit,
  ) async {
    _policy = await _repository.getVpnPolicy();
    emit(state.copyWith(status: status, isTogglingTunnel: false));
    if (status == TunnelStatus.disconnected || status == TunnelStatus.connecting) {
      try {
        final diag = await _repository.getTunnelDiagnostics();
        if (diag.isNotEmpty) {
          debugPrint('==================================================');
          debugPrint('AURA CROSS-PROCESS DIAGNOSTICS:');
          debugPrint(diag);
          debugPrint('==================================================');
        }
      } catch (_) {}
    }
    await _fetchStats(emit);
  }

  Future<void> _onTunnelToggled(Emitter<DashboardState> emit) async {
    if (!state.isInitialized || state.isTogglingTunnel) return;

    emit(state.copyWith(isTogglingTunnel: true, errorMessage: null));

    try {
      _cancelPauseTimer();
      if (state.status == TunnelStatus.connected) {
        await _repository.stopTunnel();
      } else {
        await _repository.startTunnel();
      }
      _policy = await _repository.getVpnPolicy();
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Tunnel Action Failed: $e'));
    } finally {
      emit(state.copyWith(isTogglingTunnel: false));
      await _fetchStats(emit);
    }
  }

  /// Pauses the VPN tunnel for the specified [duration].
  Future<void> pauseTunnel(Duration duration) async {
    if (!state.isInitialized || state.isTogglingTunnel) return;
    emit(state.copyWith(isTogglingTunnel: true, errorMessage: null));

    try {
      await _repository.pauseTunnel(duration);
      _policy = await _repository.getVpnPolicy();
      _schedulePauseTimer(duration);
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Failed to pause protection: $e'));
    } finally {
      emit(state.copyWith(isTogglingTunnel: false));
      // Re-fetch stats and emit state to refresh UI
      final currentStatus = await _repository.getTunnelStatus();
      emit(state.copyWith(status: currentStatus));
    }
  }

  /// Performs a permanent manual shutdown ("Turn Off Until I Turn It On").
  Future<void> shutdownTunnel() async {
    if (!state.isInitialized || state.isTogglingTunnel) return;
    emit(state.copyWith(isTogglingTunnel: true, errorMessage: null));

    try {
      _cancelPauseTimer();
      await _repository.shutdownTunnel();
      _policy = await _repository.getVpnPolicy();
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Failed to turn off protection: $e'));
    } finally {
      emit(state.copyWith(isTogglingTunnel: false));
      final currentStatus = await _repository.getTunnelStatus();
      emit(state.copyWith(status: currentStatus));
    }
  }

  /// Opens system VPN settings on Android.
  Future<void> openVpnSettings() async {
    await _repository.openVpnSettings();
  }

  void _schedulePauseTimer(Duration duration) {
    _cancelPauseTimer();
    _pauseTimer = Timer(duration, () async {
      _policy = await _repository.getVpnPolicy();
      if (_policy.mode == VpnPolicyMode.paused && _policy.remainingPauseDuration == Duration.zero) {
        add(const DashboardEvent.tunnelToggled());
      }
    });
  }

  void _cancelPauseTimer() {
    _pauseTimer?.cancel();
    _pauseTimer = null;
  }

  Future<void> _onStatsRefreshRequested(Emitter<DashboardState> emit) async {
    _policy = await _repository.getVpnPolicy();
    await _fetchStats(emit);
  }

  Future<void> _onAppResumed(Emitter<DashboardState> emit) async {
    _policy = await _repository.getVpnPolicy();
    if (_policy.mode == VpnPolicyMode.paused && _policy.remainingPauseDuration == Duration.zero) {
      // Pause expired while app was in background: attempt auto-reconnect
      try {
        await _repository.startTunnel();
        _policy = await _repository.getVpnPolicy();
      } catch (_) {}
    }
    final currentStatus = await _repository.getTunnelStatus();
    emit(state.copyWith(status: currentStatus, isInitialized: true));
    await _fetchStats(emit);
  }

  void _onErrorMessageDismissed(Emitter<DashboardState> emit) {
    emit(state.copyWith(errorMessage: null));
  }

  Future<void> _fetchStats(Emitter<DashboardState> emit) async {
    emit(state.copyWith(isLoadingStats: true, statsError: null));

    try {
      final stats = await _repository.getDashboardStats();
      emit(
        state.copyWith(
          blockedToday: stats.blockedToday,
          blockedThisWeek: stats.blockedThisWeek,
          totalBlockedDomains: stats.totalBlockedDomains,
          chartData: stats.dailyBlockedActivity,
          isLoadingStats: false,
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          isLoadingStats: false,
          statsError: 'Activity stats unavailable',
        ),
      );
    }
  }

  @override
  Future<void> close() {
    _cancelPauseTimer();
    _statusSubscription?.cancel();
    return super.close();
  }
}
