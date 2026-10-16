import 'package:flutter/material.dart';

/// Represents a domain blocking category published by the backend release in Theja's Aura.
class AuraDefaultCategory {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final List<String> domains;
  final int domainCount;

  const AuraDefaultCategory({
    required this.name,
    required this.description,
    required this.icon,
    this.domains = const [],
    int? domainCount,
    String? id,
  })  : id = id ?? name,
        domainCount = domainCount ?? domains.length;

  AuraDefaultCategory copyWith({
    String? id,
    String? name,
    String? description,
    IconData? icon,
    List<String>? domains,
    int? domainCount,
  }) {
    return AuraDefaultCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      domains: domains ?? this.domains,
      domainCount: domainCount ?? this.domainCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuraDefaultCategory &&
          runtimeType == other.runtimeType &&
          name.toLowerCase() == other.name.toLowerCase() &&
          domainCount == other.domainCount;

  @override
  int get hashCode => name.toLowerCase().hashCode ^ domainCount.hashCode;
}

/// Metadata mapping and UI presentation helpers for backend-published categories.
class AuraCategoryMetadata {
  static IconData iconForCategory(String name) {
    switch (name.toLowerCase().trim()) {
      case 'ads':
        return Icons.ad_units;
      case 'trackers':
        return Icons.track_changes;
      case 'analytics':
        return Icons.analytics_outlined;
      case 'malware':
        return Icons.security_rounded;
      case 'social':
        return Icons.people_outline;
      default:
        return Icons.shield_outlined;
    }
  }

  static String descriptionForCategory(String name) {
    switch (name.toLowerCase().trim()) {
      case 'ads':
        return 'Known advertising networks & ad-serving servers';
      case 'trackers':
        return 'Behavioral tracking, fingerprinting & attribution';
      case 'analytics':
        return 'Telemetry, usage metrics & diagnostics services';
      case 'malware':
        return 'Malicious domains and phishing hosts';
      case 'social':
        return 'Social media tracking and telemetry';
      default:
        return 'Backend published blocklist category';
    }
  }
}
