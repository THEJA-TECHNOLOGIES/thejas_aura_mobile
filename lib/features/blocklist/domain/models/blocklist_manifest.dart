import 'package:freezed_annotation/freezed_annotation.dart';

part 'blocklist_manifest.freezed.dart';
part 'blocklist_manifest.g.dart';

Map<String, dynamic> _normalizeCategoryJson(
  Map<String, dynamic> json, [
  String? defaultName,
]) {
  final map = Map<String, dynamic>.from(json);
  if (defaultName != null &&
      (map['name'] == null || (map['name'] as String).isEmpty)) {
    map['name'] = defaultName;
  }
  if (map['files'] is Map) {
    final filesMap = Map<String, dynamic>.from(map['files'] as Map);
    map['domainsUrl'] = map['domainsUrl'] ?? filesMap['domains']?.toString();
    map['hostsUrl'] = map['hostsUrl'] ?? filesMap['hosts']?.toString();
  }
  return map;
}

Map<String, dynamic> _normalizeManifestJson(Map<String, dynamic> json) {
  final map = Map<String, dynamic>.from(json);
  final rawCategories = map['categories'];
  if (rawCategories is Map) {
    final normalizedCategories = <String, dynamic>{};
    rawCategories.forEach((key, value) {
      if (value is Map) {
        normalizedCategories[key.toString()] = _normalizeCategoryJson(
          Map<String, dynamic>.from(value),
          key.toString(),
        );
      } else {
        normalizedCategories[key.toString()] = value;
      }
    });
    map['categories'] = normalizedCategories;
  }
  return map;
}

@freezed
abstract class BlocklistCategoryMeta with _$BlocklistCategoryMeta {
  const BlocklistCategoryMeta._();

  const factory BlocklistCategoryMeta({
    @Default('') String name,
    String? description,
    @Default(0) int domainCount,
    @Default({}) Map<String, String> files,
    String? domainsUrl,
    String? hostsUrl,
    String? checksum,
  }) = _BlocklistCategoryMeta;

  /// Returns the effective domains URL, checking [domainsUrl] first then [files]['domains'].
  String? get resolvedDomainsUrl => domainsUrl ?? files['domains'];

  /// Returns the effective hosts URL, checking [hostsUrl] first then [files]['hosts'].
  String? get resolvedHostsUrl => hostsUrl ?? files['hosts'];

  factory BlocklistCategoryMeta.fromJson(Map<String, dynamic> json) =>
      _$BlocklistCategoryMetaFromJson(_normalizeCategoryJson(json));
}

@freezed
abstract class BlocklistManifest with _$BlocklistManifest {
  const factory BlocklistManifest({
    required String version,
    required DateTime updatedAt,
    @Default(0) int domainCount,
    @Default({}) Map<String, String> files,
    Map<String, BlocklistCategoryMeta>? categories,
    String? checksum,
  }) = _BlocklistManifest;

  factory BlocklistManifest.fromJson(Map<String, dynamic> json) =>
      _$BlocklistManifestFromJson(_normalizeManifestJson(json));
}
