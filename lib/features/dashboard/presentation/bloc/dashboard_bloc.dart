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

    final currentStatus = await _repository.getTunnelStatus();
    emit(state.copyWith(status: currentStatus, isInitialized: true));

    await _fetchStats(emit);
  }

  Future<void> _onTunnelStatusUpdated(
    TunnelStatus status,
    Emitter<DashboardState> emit,
  ) async {
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
      if (state.status == TunnelStatus.connected) {
        await _repository.stopTunnel();
      } else {
        await _repository.startTunnel();
      }
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Tunnel Action Failed: $e'));
    } finally {
      emit(state.copyWith(isTogglingTunnel: false));
      await _fetchStats(emit);
    }
  }

  Future<void> _onStatsRefreshRequested(Emitter<DashboardState> emit) async {
    await _fetchStats(emit);
  }

  Future<void> _onAppResumed(Emitter<DashboardState> emit) async {
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
    _statusSubscription?.cancel();
    return super.close();
  }
}
