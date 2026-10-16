import 'dart:async';

import '../models/blocklist_manifest.dart';
import '../models/installed_release_meta.dart';

enum SyncState {
  idle,
  checkingForUpdates,
  downloading,
  validating,
  installing,
  upToDate,
  updated,
  failed,
}

class BlocklistSyncStatus {
  final SyncState state;
  final String? message;
  final double? progress;
  final String? error;
  final InstalledReleaseMeta? installedRelease;

  const BlocklistSyncStatus({
    required this.state,
    this.message,
    this.progress,
    this.error,
    this.installedRelease,
  });

  factory BlocklistSyncStatus.initial([InstalledReleaseMeta? installed]) =>
      BlocklistSyncStatus(state: SyncState.idle, installedRelease: installed);

  factory BlocklistSyncStatus.checking([InstalledReleaseMeta? installed]) =>
      BlocklistSyncStatus(
        state: SyncState.checkingForUpdates,
        message: 'Checking for blocklist updates...',
        installedRelease: installed,
      );

  factory BlocklistSyncStatus.downloading(
    double progress, [
    InstalledReleaseMeta? installed,
  ]) => BlocklistSyncStatus(
    state: SyncState.downloading,
    progress: progress,
    message: 'Downloading blocklist files (${(progress * 100).toInt()}%)...',
    installedRelease: installed,
  );

  factory BlocklistSyncStatus.validating([InstalledReleaseMeta? installed]) =>
      BlocklistSyncStatus(
        state: SyncState.validating,
        message: 'Validating domain entries and checksums...',
        installedRelease: installed,
      );

  factory BlocklistSyncStatus.installing([InstalledReleaseMeta? installed]) =>
      BlocklistSyncStatus(
        state: SyncState.installing,
        message: 'Installing release to firewall...',
        installedRelease: installed,
      );

  factory BlocklistSyncStatus.upToDate(InstalledReleaseMeta installed) =>
      BlocklistSyncStatus(
        state: SyncState.upToDate,
        message: 'Blocklist is up-to-date (Version: ${installed.version})',
        installedRelease: installed,
      );

  factory BlocklistSyncStatus.updated(InstalledReleaseMeta installed) =>
      BlocklistSyncStatus(
        state: SyncState.updated,
        message: 'Successfully installed release ${installed.version}',
        installedRelease: installed,
      );

  factory BlocklistSyncStatus.failed(
    String error, [
    InstalledReleaseMeta? installed,
  ]) => BlocklistSyncStatus(
    state: SyncState.failed,
    error: error,
    message: 'Blocklist sync failed: $error',
    installedRelease: installed,
  );
}

class SyncResult {
  final bool isSuccess;
  final bool isUpdated;
  final String version;
  final String? message;
  final String? error;
  final bool activeFirewallReloaded;
  final bool isCategoryEndpointsMissing;
  final InstalledReleaseMeta? installedRelease;
  final List<String> installedCategories;
  final List<String> unsupportedCategories;
  final bool isChecksumVerified;

  const SyncResult({
    required this.isSuccess,
    required this.isUpdated,
    required this.version,
    this.message,
    this.error,
    this.activeFirewallReloaded = false,
    this.isCategoryEndpointsMissing = false,
    this.installedRelease,
    this.installedCategories = const [],
    this.unsupportedCategories = const [],
    this.isChecksumVerified = false,
  });

  factory SyncResult.upToDate(InstalledReleaseMeta installed) => SyncResult(
    isSuccess: true,
    isUpdated: false,
    version: installed.version,
    message: 'Blocklist is already up to date',
    installedRelease: installed,
  );

  factory SyncResult.success({
    required String version,
    required bool activeFirewallReloaded,
    required bool isCategoryEndpointsMissing,
    required InstalledReleaseMeta installedRelease,
    List<String> installedCategories = const [],
    List<String> unsupportedCategories = const [],
    bool isChecksumVerified = false,
  }) => SyncResult(
    isSuccess: true,
    isUpdated: true,
    version: version,
    activeFirewallReloaded: activeFirewallReloaded,
    isCategoryEndpointsMissing: isCategoryEndpointsMissing,
    installedRelease: installedRelease,
    installedCategories: installedCategories,
    unsupportedCategories: unsupportedCategories,
    isChecksumVerified: isChecksumVerified,
    message: 'Successfully updated blocklist to $version',
  );

  factory SyncResult.failure({
    required String error,
    String version = 'unknown',
    InstalledReleaseMeta? currentRelease,
    List<String> unsupportedCategories = const [],
  }) => SyncResult(
    isSuccess: false,
    isUpdated: false,
    version: version,
    error: error,
    installedRelease: currentRelease,
    unsupportedCategories: unsupportedCategories,
  );
}

abstract class IBlocklistSyncRepository {
  /// Stream of synchronization lifecycle events.
  Stream<BlocklistSyncStatus> get statusStream;

  /// Current in-memory status.
  BlocklistSyncStatus get currentStatus;

  /// Gets the currently installed release metadata from native App Group storage.
  Future<InstalledReleaseMeta?> getInstalledRelease();

  /// Gets the most recent manifest fetched from the backend.
  BlocklistManifest? get latestManifest;

  /// Initiates synchronization against the backend manifest.
  /// If a synchronization is already in-flight, coalesces onto the existing Future.
  Future<SyncResult> sync({bool force = false});
}
