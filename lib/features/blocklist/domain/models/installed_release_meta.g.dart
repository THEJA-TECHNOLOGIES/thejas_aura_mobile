// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'installed_release_meta.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_InstalledReleaseMeta _$InstalledReleaseMetaFromJson(
  Map<String, dynamic> json,
) => _InstalledReleaseMeta(
  version: json['version'] as String,
  installedAt: DateTime.parse(json['installedAt'] as String),
  domainCount: (json['domainCount'] as num?)?.toInt() ?? 0,
  categoryFiles:
      (json['categoryFiles'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ) ??
      const {},
  categoryDomainCounts:
      (json['categoryDomainCounts'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, (e as num).toInt()),
      ) ??
      const {},
  etag: json['etag'] as String?,
  globalChecksum: json['globalChecksum'] as String?,
);

Map<String, dynamic> _$InstalledReleaseMetaToJson(
  _InstalledReleaseMeta instance,
) => <String, dynamic>{
  'version': instance.version,
  'installedAt': instance.installedAt.toIso8601String(),
  'domainCount': instance.domainCount,
  'categoryFiles': instance.categoryFiles,
  'categoryDomainCounts': instance.categoryDomainCounts,
  'etag': instance.etag,
  'globalChecksum': instance.globalChecksum,
};
