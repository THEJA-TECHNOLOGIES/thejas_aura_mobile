// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'blocklist_manifest.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_BlocklistCategoryMeta _$BlocklistCategoryMetaFromJson(
  Map<String, dynamic> json,
) => _BlocklistCategoryMeta(
  name: json['name'] as String? ?? '',
  description: json['description'] as String?,
  domainCount: (json['domainCount'] as num?)?.toInt() ?? 0,
  files:
      (json['files'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ) ??
      const {},
  domainsUrl: json['domainsUrl'] as String?,
  hostsUrl: json['hostsUrl'] as String?,
  checksum: json['checksum'] as String?,
);

Map<String, dynamic> _$BlocklistCategoryMetaToJson(
  _BlocklistCategoryMeta instance,
) => <String, dynamic>{
  'name': instance.name,
  'description': instance.description,
  'domainCount': instance.domainCount,
  'files': instance.files,
  'domainsUrl': instance.domainsUrl,
  'hostsUrl': instance.hostsUrl,
  'checksum': instance.checksum,
};

_BlocklistManifest _$BlocklistManifestFromJson(Map<String, dynamic> json) =>
    _BlocklistManifest(
      version: json['version'] as String,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      domainCount: (json['domainCount'] as num?)?.toInt() ?? 0,
      files:
          (json['files'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, e as String),
          ) ??
          const {},
      categories: (json['categories'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(
          k,
          BlocklistCategoryMeta.fromJson(e as Map<String, dynamic>),
        ),
      ),
      checksum: json['checksum'] as String?,
    );

Map<String, dynamic> _$BlocklistManifestToJson(_BlocklistManifest instance) =>
    <String, dynamic>{
      'version': instance.version,
      'updatedAt': instance.updatedAt.toIso8601String(),
      'domainCount': instance.domainCount,
      'files': instance.files,
      'categories': instance.categories,
      'checksum': instance.checksum,
    };
