import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';

part 'dashboard_state.freezed.dart';

@freezed
abstract class DashboardState with _$DashboardState {
  const factory DashboardState({
    @Default(TunnelStatus.disconnected) TunnelStatus status,
    @Default(false) bool isInitialized,
    @Default(false) bool isTogglingTunnel,
    @Default(false) bool isLoadingStats,
    int? blockedToday,
    int? blockedThisWeek,
    int? totalBlockedDomains,
    String? statsError,
    String? errorMessage,
  }) = _DashboardState;
}
