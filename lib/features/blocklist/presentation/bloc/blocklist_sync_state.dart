import 'package:freezed_annotation/freezed_annotation.dart';

import '../../domain/models/blocklist_manifest.dart';
import '../../domain/models/installed_release_meta.dart';
import '../../domain/repositories/i_blocklist_sync_repository.dart';

part 'blocklist_sync_state.freezed.dart';

@freezed
abstract class BlocklistSyncState with _$BlocklistSyncState {
  const factory BlocklistSyncState({
    @Default(SyncState.idle) SyncState state,
    String? message,
    double? progress,
    InstalledReleaseMeta? installedRelease,
    BlocklistManifest? latestManifest,
    String? errorMessage,
    @Default(false) bool isCategoryEndpointsMissing,
  }) = _BlocklistSyncState;

  const BlocklistSyncState._();

  bool get isSyncing =>
      state == SyncState.checkingForUpdates ||
      state == SyncState.downloading ||
      state == SyncState.validating ||
      state == SyncState.installing;

  bool get isUpToDate => state == SyncState.upToDate;
  bool get isUpdated => state == SyncState.updated;
  bool get hasFailed => state == SyncState.failed;
}
