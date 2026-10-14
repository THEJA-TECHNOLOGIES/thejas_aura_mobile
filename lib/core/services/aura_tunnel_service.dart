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
  final String id;
  final String domain;
  final bool isEnabled;
  final bool isBlocked;

  const AuraRuleItem({
    String? id,
    required this.domain,
    this.isEnabled = true,
    this.isBlocked = true,
  }) : id = id ?? domain;

  Map<String, dynamic> toMap() => {
    'id': id,
    'domain': domain,
    'isEnabled': isEnabled,
    'isBlocked': isBlocked,
  };

  factory AuraRuleItem.fromMap(Map<String, dynamic> map) {
    final domain = map['domain'] as String;
    final rawId = map['id'] as String?;
    return AuraRuleItem(
      id: (rawId == null || rawId.isEmpty) ? domain : rawId,
      domain: domain,
      isEnabled: map['isEnabled'] as bool? ?? true,
      isBlocked: map['isBlocked'] as bool? ?? true,
    );
  }

  AuraRuleItem copyWith({
    String? id,
    String? domain,
    bool? isEnabled,
    bool? isBlocked,
  }) {
    return AuraRuleItem(
      id: id ?? this.id,
      domain: domain ?? this.domain,
      isEnabled: isEnabled ?? this.isEnabled,
      isBlocked: isBlocked ?? this.isBlocked,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuraRuleItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          domain == other.domain &&
          isEnabled == other.isEnabled &&
          isBlocked == other.isBlocked;

  @override
  int get hashCode =>
      id.hashCode ^ domain.hashCode ^ isEnabled.hashCode ^ isBlocked.hashCode;
}

/// Typed exception for rule and category management errors.
class AuraRuleException implements Exception {
  final String code;
  final String message;

  const AuraRuleException(this.code, this.message);

  @override
  String toString() => 'AuraRuleException: [$code] $message';
}

/// Service wrapping native platform channels for Theja's Aura Local Tunnel.
class AuraTunnelService {
  static const MethodChannel _controlChannel = MethodChannel(
    'com.thejatech.aura/tunnel_control',
  );
  static const EventChannel _statusChannel = EventChannel(
    'com.thejatech.aura/tunnel_status',
  );

  /// Stream of live tunnel status changes emitted by iOS.
  Stream<TunnelStatus> get statusStream => _statusChannel
      .receiveBroadcastStream()
      .map((event) => TunnelStatus.fromString(event as String? ?? 'invalid'));

  /// Queries current status of the tunnel.
  Future<TunnelStatus> getStatus() async {
    try {
      final String? status = await _controlChannel.invokeMethod<String>(
        'getStatus',
      );
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

  // MARK: - Custom Rules Operations

  /// Queries persisted rules stored in the App Group.
  /// Returns null if native loading failed (e.g. file corrupt or channel error),
  /// or an empty list if no rules are stored.
  Future<List<AuraRuleItem>?> getRules() async {
    try {
      final List<dynamic>? raw = await _controlChannel
          .invokeMethod<List<dynamic>>('getRules');
      if (raw == null) return null;
      return raw
          .map(
            (item) =>
                AuraRuleItem.fromMap(Map<String, dynamic>.from(item as Map)),
          )
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Validates a domain using the native Mozilla Public Suffix List validator.
  /// Throws [AuraRuleException] if the domain is invalid, a public suffix, an IP, etc.
  Future<String> validateDomain(String domain) async {
    try {
      final String? validated = await _controlChannel.invokeMethod<String>(
        'validateDomain',
        {'domain': domain},
      );
      return validated ?? domain;
    } on PlatformException catch (e) {
      throw AuraRuleException(e.code, e.message ?? 'Domain validation failed.');
    }
  }

  /// Adds a new custom rule with PSL validation and duplicate prevention.
  Future<AuraRuleItem> addRule({
    required String domain,
    required bool isBlocked,
    bool isEnabled = true,
  }) async {
    try {
      final dynamic raw = await _controlChannel.invokeMethod<dynamic>(
        'addRule',
        {'domain': domain, 'isBlocked': isBlocked, 'isEnabled': isEnabled},
      );
      if (raw is Map) {
        return AuraRuleItem.fromMap(Map<String, dynamic>.from(raw));
      }
      throw const AuraRuleException(
        'INVALID_RESPONSE',
        'Invalid response from native addRule.',
      );
    } on PlatformException catch (e) {
      throw AuraRuleException(e.code, e.message ?? 'Failed to add rule.');
    }
  }

  /// Updates an existing rule.
  Future<AuraRuleItem> updateRule({
    required String id,
    String? domain,
    bool? isBlocked,
    bool? isEnabled,
  }) async {
    try {
      final Map<String, dynamic> args = {'id': id};
      if (domain != null) args['domain'] = domain;
      if (isBlocked != null) args['isBlocked'] = isBlocked;
      if (isEnabled != null) args['isEnabled'] = isEnabled;

      final dynamic raw = await _controlChannel.invokeMethod<dynamic>(
        'updateRule',
        args,
      );
      if (raw is Map) {
        return AuraRuleItem.fromMap(Map<String, dynamic>.from(raw));
      }
      throw const AuraRuleException(
        'INVALID_RESPONSE',
        'Invalid response from native updateRule.',
      );
    } on PlatformException catch (e) {
      throw AuraRuleException(e.code, e.message ?? 'Failed to update rule.');
    }
  }

  /// Deletes a custom rule by its stable identifier.
  Future<AuraRuleItem> deleteRule(String id) async {
    try {
      final dynamic raw = await _controlChannel.invokeMethod<dynamic>(
        'deleteRule',
        {'id': id},
      );
      if (raw is Map) {
        return AuraRuleItem.fromMap(Map<String, dynamic>.from(raw));
      }
      throw const AuraRuleException(
        'INVALID_RESPONSE',
        'Invalid response from native deleteRule.',
      );
    } on PlatformException catch (e) {
      throw AuraRuleException(e.code, e.message ?? 'Failed to delete rule.');
    }
  }

  /// Toggles the enabled/disabled state of a rule.
  Future<AuraRuleItem> toggleRule(String id, bool isEnabled) async {
    try {
      final dynamic raw = await _controlChannel.invokeMethod<dynamic>(
        'toggleRule',
        {'id': id, 'isEnabled': isEnabled},
      );
      if (raw is Map) {
        return AuraRuleItem.fromMap(Map<String, dynamic>.from(raw));
      }
      throw const AuraRuleException(
        'INVALID_RESPONSE',
        'Invalid response from native toggleRule.',
      );
    } on PlatformException catch (e) {
      throw AuraRuleException(e.code, e.message ?? 'Failed to toggle rule.');
    }
  }

  /// Atomically synchronizes domain rules to App Group storage and signals running tunnel if active.
  Future<bool> syncRules(List<AuraRuleItem> rules) async {
    try {
      final List<Map<String, dynamic>> ruleMaps = rules
          .map((r) => r.toMap())
          .toList();
      final bool? success = await _controlChannel.invokeMethod<bool>(
        'syncRules',
        ruleMaps,
      );
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

  // MARK: - Category Preferences Operations

  /// Fetches the persisted enable/disable state of default categories (Ads, Trackers, Analytics).
  Future<Map<String, bool>> getCategories() async {
    try {
      final dynamic raw = await _controlChannel.invokeMethod<dynamic>(
        'getCategories',
      );
      if (raw is Map) {
        final Map<String, bool> result = {};
        for (final entry in raw.entries) {
          result[entry.key.toString()] = entry.value as bool? ?? true;
        }
        return result;
      }
      return {'Ads': true, 'Trackers': true, 'Analytics': true};
    } on PlatformException catch (e) {
      throw AuraRuleException(
        e.code,
        e.message ?? 'Failed to load categories.',
      );
    }
  }

  /// Toggles or sets an individual category preference.
  Future<Map<String, bool>> setCategoryPreference(
    String category,
    bool isEnabled,
  ) async {
    try {
      final dynamic raw = await _controlChannel.invokeMethod<dynamic>(
        'setCategoryPreference',
        {'category': category, 'isEnabled': isEnabled},
      );
      if (raw is Map) {
        final Map<String, bool> result = {};
        for (final entry in raw.entries) {
          result[entry.key.toString()] = entry.value as bool? ?? true;
        }
        return result;
      }
      return {'Ads': true, 'Trackers': true, 'Analytics': true};
    } on PlatformException catch (e) {
      throw AuraRuleException(
        e.code,
        e.message ?? 'Failed to update category $category.',
      );
    }
  }

  /// Sets all category preferences simultaneously.
  Future<Map<String, bool>> setAllCategoryPreferences(
    Map<String, bool> preferences,
  ) async {
    try {
      final dynamic raw = await _controlChannel.invokeMethod<dynamic>(
        'setAllCategoryPreferences',
        {'preferences': preferences},
      );
      if (raw is Map) {
        final Map<String, bool> result = {};
        for (final entry in raw.entries) {
          result[entry.key.toString()] = entry.value as bool? ?? true;
        }
        return result;
      }
      return preferences;
    } on PlatformException catch (e) {
      throw AuraRuleException(
        e.code,
        e.message ?? 'Failed to save category preferences.',
      );
    }
  }

  // MARK: - Default Domain Overrides Operations

  /// Fetches the set of disabled default domains from native persistence.
  Future<Set<String>> getDefaultDomainOverrides() async {
    try {
      final dynamic raw = await _controlChannel.invokeMethod<dynamic>(
        'getDefaultDomainOverrides',
      );
      if (raw is List) {
        return raw.map((e) => e.toString().toLowerCase().trim()).toSet();
      }
      return <String>{};
    } on PlatformException catch (e) {
      throw AuraRuleException(
        e.code,
        e.message ?? 'Failed to load default domain overrides.',
      );
    }
  }

  /// Toggles an individual default domain enable/disable state.
  /// When [isEnabled] is true, the domain participates in default blocking (removed from disabled set).
  /// When [isEnabled] is false, the domain is excluded from default blocking (added to disabled set).
  /// Returns the updated set of disabled default domains.
  Future<Set<String>> toggleDefaultDomain({
    required String domain,
    required bool isEnabled,
  }) async {
    try {
      final dynamic raw = await _controlChannel.invokeMethod<dynamic>(
        'toggleDefaultDomain',
        {'domain': domain, 'isEnabled': isEnabled},
      );
      if (raw is List) {
        return raw.map((e) => e.toString().toLowerCase().trim()).toSet();
      }
      return <String>{};
    } on PlatformException catch (e) {
      throw AuraRuleException(
        e.code,
        e.message ?? 'Failed to toggle default domain $domain.',
      );
    }
  }
}
