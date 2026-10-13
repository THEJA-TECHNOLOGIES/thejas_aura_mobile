import 'dart:async';
import 'package:flutter/services.dart';

enum TunnelStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
  invalid;

  static TunnelStatus fromString(String raw) {
    switch (raw.toLowerCase()) {
      case 'connected':
        return TunnelStatus.connected;
      case 'connecting':
        return TunnelStatus.connecting;
      case 'disconnecting':
        return TunnelStatus.disconnecting;
      case 'disconnected':
        return TunnelStatus.disconnected;
      default:
        return TunnelStatus.invalid;
    }
  }
}

class AuraRuleItem {
  final String domain;
  final bool isEnabled;
  final bool isBlocked;

  const AuraRuleItem({
    required this.domain,
    this.isEnabled = true,
    this.isBlocked = true,
  });

  Map<String, dynamic> toMap() => {
        'domain': domain,
        'isEnabled': isEnabled,
        'isBlocked': isBlocked,
      };

  factory AuraRuleItem.fromMap(Map<String, dynamic> map) => AuraRuleItem(
        domain: map['domain'] as String,
        isEnabled: map['isEnabled'] as bool? ?? true,
        isBlocked: map['isBlocked'] as bool? ?? true,
      );
}

/// Service wrapping native platform channels for Theja's Aura Local Tunnel.
class AuraTunnelService {
  static const MethodChannel _controlChannel =
      MethodChannel('com.thejatech.aura/tunnel_control');
  static const EventChannel _statusChannel =
      EventChannel('com.thejatech.aura/tunnel_status');

  /// Stream of live tunnel status changes emitted by iOS.
  Stream<TunnelStatus> get statusStream => _statusChannel
      .receiveBroadcastStream()
      .map((event) => TunnelStatus.fromString(event as String? ?? 'invalid'));

  /// Queries current status of the tunnel.
  Future<TunnelStatus> getStatus() async {
    try {
      final String? status = await _controlChannel.invokeMethod<String>('getStatus');
      return TunnelStatus.fromString(status ?? 'invalid');
    } catch (_) {
      return TunnelStatus.invalid;
    }
  }

  /// Starts the local firewall tunnel.
  Future<void> startTunnel() async {
    await _controlChannel.invokeMethod<void>('startTunnel');
  }

  /// Stops the local firewall tunnel.
  Future<void> stopTunnel() async {
    await _controlChannel.invokeMethod<void>('stopTunnel');
  }

  /// Queries persisted rules stored in the App Group.
  /// Returns null if native loading failed (e.g. file corrupt or channel error),
  /// or an empty list if no rules are stored.
  Future<List<AuraRuleItem>?> getRules() async {
    try {
      final List<dynamic>? raw =
          await _controlChannel.invokeMethod<List<dynamic>>('getRules');
      if (raw == null) return null;
      return raw
          .map((item) =>
              AuraRuleItem.fromMap(Map<String, dynamic>.from(item as Map)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Atomically synchronizes domain rules to App Group storage and signals running tunnel if active.
  Future<bool> syncRules(List<AuraRuleItem> rules) async {
    try {
      final List<Map<String, dynamic>> ruleMaps =
          rules.map((r) => r.toMap()).toList();
      final bool? success =
          await _controlChannel.invokeMethod<bool>('syncRules', ruleMaps);
      return success ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Explicitly requests a live rule reload on an active tunnel session with dedicated error reporting.
  Future<bool> reloadRules() async {
    final bool? sent = await _controlChannel.invokeMethod<bool>('reloadRules');
    return sent ?? false;
  }
}
