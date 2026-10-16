import 'package:freezed_annotation/freezed_annotation.dart';

part 'installed_release_meta.freezed.dart';
part 'installed_release_meta.g.dart';

@freezed
abstract class InstalledReleaseMeta with _$InstalledReleaseMeta {
  const factory InstalledReleaseMeta({
    required String version,
    required DateTime installedAt,
    @Default(0) int domainCount,
    @Default({}) Map<String, String> categoryFiles,
    @Default({}) Map<String, int> categoryDomainCounts,
    String? etag,
    String? globalChecksum,
  }) = _InstalledReleaseMeta;

  factory InstalledReleaseMeta.fromJson(Map<String, dynamic> json) =>
      _$InstalledReleaseMetaFromJson(json);
}
