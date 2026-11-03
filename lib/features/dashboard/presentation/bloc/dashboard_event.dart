import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';

part 'dashboard_event.freezed.dart';

@freezed
abstract class DashboardEvent with _$DashboardEvent {
  const factory DashboardEvent.started() = _DashboardStarted;
  const factory DashboardEvent.tunnelStatusUpdated(TunnelStatus status) =
      _DashboardTunnelStatusUpdated;
  const factory DashboardEvent.tunnelToggled() = _DashboardTunnelToggled;
  const factory DashboardEvent.pauseRequested(Duration duration) =
      _DashboardPauseRequested;
  const factory DashboardEvent.shutdownRequested() =
      _DashboardShutdownRequested;
  const factory DashboardEvent.statsRefreshRequested() =
      _DashboardStatsRefreshRequested;
  const factory DashboardEvent.appResumed() = _DashboardAppResumed;
  const factory DashboardEvent.errorMessageDismissed() =
      _DashboardErrorMessageDismissed;
}
