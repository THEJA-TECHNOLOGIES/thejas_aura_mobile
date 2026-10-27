import 'dart:async';

import 'package:theja_aura/core/services/aura_tunnel_service.dart';

import '../models/dashboard_stats.dart';

abstract class IDashboardRepository {
  Stream<TunnelStatus> get tunnelStatusStream;
  Future<TunnelStatus> getTunnelStatus();
  Future<void> startTunnel();
  Future<void> stopTunnel();
  Future<DashboardStats> getDashboardStats();
  Future<String> getTunnelDiagnostics();
  Future<bool> clearTunnelDiagnostics();
  Future<VpnPolicy> getVpnPolicy();
  Future<void> pauseTunnel(Duration duration);
  Future<void> shutdownTunnel();
  Future<bool> isAlwaysOnActive();
  Future<void> openVpnSettings();
}
