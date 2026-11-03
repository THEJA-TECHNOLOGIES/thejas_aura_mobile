import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/bar_chart/individual_bar.dart';

part 'dashboard_state.freezed.dart';

@freezed
abstract class DashboardState with _$DashboardState {
  const factory DashboardState({
    @Default(TunnelStatus.disconnected) TunnelStatus status,
    @Default(VpnPolicy()) VpnPolicy policy,
    @Default(false) bool isInitialized,
    @Default(false) bool isTogglingTunnel,
    @Default(false) bool isLoadingStats,
    int? blockedToday,
    int? blockedThisWeek,
    int? totalBlockedDomains,
    @Default([]) List<IndividualBar> chartData,
    String? statsError,
    String? errorMessage,
  }) = _DashboardState;
}
