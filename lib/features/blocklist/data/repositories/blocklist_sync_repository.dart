import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:theja_aura/core/config/app_config.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';

import '../../domain/models/blocklist_manifest.dart';
import '../../domain/models/installed_release_meta.dart';
import '../../domain/repositories/i_blocklist_sync_repository.dart';
import '../../domain/services/blocklist_sync_error_formatter.dart';
import '../../domain/services/blocklist_validator.dart';
import '../datasources/blocklist_api_client.dart';

@LazySingleton(as: IBlocklistSyncRepository)
class BlocklistSyncRepository implements IBlocklistSyncRepository {
  final IBlocklistApiClient _apiClient;
  final AuraTunnelService _tunnelService;

  final StreamController<BlocklistSyncStatus> _statusController =
      StreamController<BlocklistSyncStatus>.broadcast();

  BlocklistSyncStatus _currentStatus = BlocklistSyncStatus.initial();
  BlocklistManifest? _latestManifest;
  InstalledReleaseMeta? _installedRelease;
  Future<SyncResult>? _activeSyncFuture;

  BlocklistSyncRepository(this._apiClient, this._tunnelService);

  @override
  Stream<BlocklistSyncStatus> get statusStream => _statusController.stream;

  @override
  BlocklistSyncStatus get currentStatus => _currentStatus;

  @override
  BlocklistManifest? get latestManifest => _latestManifest;

  void _emit(BlocklistSyncStatus status) {
    _currentStatus = status;
    _statusController.add(status);
  }

  @override
  Future<InstalledReleaseMeta?> getInstalledRelease() async {
    if (_installedRelease != null) return _installedRelease;
    try {
      final raw = await _tunnelService.getInstalledRelease();
      if (raw != null) {
        _installedRelease = InstalledReleaseMeta(
          version: raw['version'] as String? ?? 'unknown',
          installedAt:
              DateTime.tryParse(raw['installedAt'] as String? ?? '') ??
              DateTime.now(),
          domainCount: (raw['domainCount'] as num?)?.toInt() ?? 0,
          categoryFiles: Map<String, String>.from(raw['files'] as Map? ?? {}),
          etag: raw['etag'] as String?,
          globalChecksum: raw['checksum'] as String?,
        );
      }
    } catch (_) {
      _installedRelease = null;
    }
    return _installedRelease;
  }

  @override
  Future<SyncResult> sync({bool force = false}) {
    // Prevent duplicate concurrent synchronization requests
    if (_activeSyncFuture != null) {
      return _activeSyncFuture!;
    }

    final future = _executeSync(force: force).whenComplete(() {
      _activeSyncFuture = null;
    });
    _activeSyncFuture = future;
    return future;
  }

  Future<SyncResult> _executeSync({required bool force}) async {
    final currentRelease = await getInstalledRelease();
    _emit(BlocklistSyncStatus.checking(currentRelease));

    final unsupportedCategories = <String>[];

    try {
      // 1. Fetch manifest with ETag
      final manifest = await _apiClient.fetchManifest(
        ifNoneMatch: force ? null : currentRelease?.etag,
      );

      // Handle 304 Not Modified
      if (manifest == null) {
        if (currentRelease != null && !force) {
          _emit(BlocklistSyncStatus.upToDate(currentRelease));
          return SyncResult.upToDate(currentRelease);
        }
        throw const BlocklistApiException(
          'Manifest was reported not modified, but no valid local release is installed.',
        );
      }

      _latestManifest = manifest;

      // 2. Version Comparison
      final isSameVersion =
          currentRelease != null && currentRelease.version == manifest.version;
      if (isSameVersion && !force) {
        // Verify local category files exist
        if (currentRelease.categoryFiles.isNotEmpty) {
          _emit(BlocklistSyncStatus.upToDate(currentRelease));
          return SyncResult.upToDate(currentRelease);
        }
        // Missing or corrupt local files: trigger safe repair
      }

      // 3. Determine files to download based on the actual manifest
      _emit(BlocklistSyncStatus.downloading(0.05, currentRelease));

      final filesToDownload =
          <String, String>{}; // destinationFileName -> urlOrPath
      final installedCategories = <String>[];

      // 3.1. Process category-specific endpoints in manifest.categories dynamically
      if (manifest.categories != null && manifest.categories!.isNotEmpty) {
        for (final entry in manifest.categories!.entries) {
          final catKey = entry.key;
          final normalizedKey = catKey.toLowerCase().trim();
          final meta = entry.value;

          // Prefer domain-per-line list, fallback to hosts format
          final url =
              meta.domainsUrl ??
              meta.files['domains'] ??
              meta.hostsUrl ??
              meta.files['hosts'];

          if (url != null && url.isNotEmpty) {
            final destinationFileName = normalizedKey.endsWith('.txt')
                ? normalizedKey
                : '$normalizedKey.txt';
            filesToDownload[destinationFileName] = url;
            installedCategories.add(catKey);
          } else {
            unsupportedCategories.add(catKey);
          }
        }
      }

      // 3.2. Fallback to manifest.files if manifest.categories was not present or empty
      if (filesToDownload.isEmpty && manifest.files.isNotEmpty) {
        for (final entry in manifest.files.entries) {
          final key = entry.key.toLowerCase().trim();
          final url = entry.value;
          if (key.contains('categories/')) {
            final parts = key.split('/');
            final cat = parts.length > 1 ? parts[1].toLowerCase().trim() : key;
            final destinationFileName = cat.endsWith('.txt') ? cat : '$cat.txt';
            filesToDownload[destinationFileName] = url;
            installedCategories.add(cat.replaceAll('.txt', ''));
          } else if (key == 'domains' || key == 'domains.txt') {
            filesToDownload['domains.txt'] = url;
          } else if (key == 'hosts' || key == 'hosts.txt') {
            filesToDownload['hosts.txt'] = url;
          } else {
            final destinationFileName = key.endsWith('.txt') ? key : '$key.txt';
            filesToDownload[destinationFileName] = url;
            installedCategories.add(entry.key.replaceAll('.txt', ''));
          }
        }
      }

      if (filesToDownload.isEmpty) {
        throw const BlocklistApiException(
          'Manifest does not contain any downloadable blocklist files',
        );
      }

      // 4. Download and validate each file
      final downloadedFiles = <String, String>{}; // fileName -> rawContent
      final categoryDomainCounts = <String, int>{};
      int totalDomainsValidated = 0;
      int completed = 0;
      int fileIndex = 0;
      final totalFiles = filesToDownload.length;
      bool allChecksumsVerified = false;

      for (final entry in filesToDownload.entries) {
        final fileName = entry.key;
        final url = entry.value;

        // Extract expected checksum if available in manifest
        String? expectedChecksum = manifest.checksum;
        final baseCatName = fileName.replaceAll('.txt', '');
        if (manifest.categories != null) {
          for (final catEntry in manifest.categories!.entries) {
            if (catEntry.key.toLowerCase().trim() == baseCatName) {
              expectedChecksum = catEntry.value.checksum ?? manifest.checksum;
              break;
            }
          }
        }

        final downloadProgress = 0.05 + (0.80 * (fileIndex / totalFiles));
        _emit(
          BlocklistSyncStatus.downloading(downloadProgress, currentRelease),
        );

        // Bounded retry for transient file download failures
        DownloadedFileResult? downloadRes;
        for (var attempt = 1; attempt <= 2; attempt++) {
          try {
            downloadRes = await _apiClient.downloadFile(
              urlOrPath: url,
              expectedChecksum: expectedChecksum,
            );
            break;
          } catch (e) {
            if (attempt == 2 ||
                e is ChecksumMismatchException ||
                e is SecurityException ||
                e is FormatException) {
              rethrow;
            }
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }

        final validateProgress =
            0.05 + (0.80 * ((fileIndex + 0.5) / totalFiles));
        _emit(BlocklistSyncStatus.validating(validateProgress, currentRelease));

        // Validate content (allow empty for valid header-only category files)
        final isCategoryFile =
            fileName.endsWith('.txt') &&
            fileName != 'domains.txt' &&
            fileName != 'hosts.txt';
        final validation = BlocklistValidator.validate(
          downloadRes!.content,
          allowEmpty: isCategoryFile,
        );
        if (!validation.isValid) {
          throw BlocklistApiException(
            "Validation failed for '$fileName': ${validation.error}",
          );
        }

        if (downloadRes.isChecksumVerified) {
          allChecksumsVerified = true;
        }

        downloadedFiles[fileName] = downloadRes.content;
        categoryDomainCounts[baseCatName] = validation.validDomainCount;
        totalDomainsValidated += validation.validDomainCount;

        completed++;
        fileIndex++;
        final completedProgress = 0.05 + (0.80 * (completed / totalFiles));
        _emit(
          BlocklistSyncStatus.downloading(completedProgress, currentRelease),
        );
      }

      // 5. Install the release atomically via native bridge
      _emit(BlocklistSyncStatus.installing(0.90, currentRelease));

      final installResult = await _tunnelService.installBlocklistRelease(
        version: manifest.version,
        files: downloadedFiles,
        domainCount: manifest.domainCount > 0
            ? manifest.domainCount
            : totalDomainsValidated,
        etag: manifest.version,
        checksum: manifest.checksum,
      );

      final activeReloaded = installResult['reloaded'] as bool? ?? false;

      // 6. Record installed release metadata
      final newRelease = InstalledReleaseMeta(
        version: manifest.version,
        installedAt: DateTime.now(),
        domainCount: manifest.domainCount > 0
            ? manifest.domainCount
            : totalDomainsValidated,
        categoryFiles: Map<String, String>.from(
          installResult['files'] as Map? ?? {},
        ),
        categoryDomainCounts: categoryDomainCounts,
        etag: manifest.version,
        globalChecksum: manifest.checksum,
      );

      _installedRelease = newRelease;
      _emit(BlocklistSyncStatus.updated(newRelease, 1.0));

      return SyncResult.success(
        version: newRelease.version,
        activeFirewallReloaded: activeReloaded,
        isCategoryEndpointsMissing: false,
        installedRelease: newRelease,
        installedCategories: installedCategories,
        unsupportedCategories: unsupportedCategories,
        isChecksumVerified: allChecksumsVerified,
      );
    } catch (e) {
      // Retain last known-good release on failure
      final errorMsg = e.toString();
      _emit(BlocklistSyncStatus.failed(errorMsg, currentRelease));

      return SyncResult.failure(
        error: errorMsg,
        version:
            _latestManifest?.version ?? currentRelease?.version ?? 'unknown',
        currentRelease: currentRelease,
        unsupportedCategories: unsupportedCategories,
      );
    }
  }
}
