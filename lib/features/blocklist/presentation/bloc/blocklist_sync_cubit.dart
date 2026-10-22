import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:injectable/injectable.dart';

import '../../domain/repositories/i_blocklist_sync_repository.dart';
import '../../domain/services/blocklist_sync_error_formatter.dart';
import 'blocklist_sync_state.dart';

export '../../domain/repositories/i_blocklist_sync_repository.dart'
    show SyncState;
export 'blocklist_sync_state.dart';

@injectable
class BlocklistSyncCubit extends Cubit<BlocklistSyncState> {
  final IBlocklistSyncRepository _repository;
  StreamSubscription<BlocklistSyncStatus>? _subscription;

  BlocklistSyncCubit(this._repository) : super(const BlocklistSyncState()) {
    _subscription = _repository.statusStream.listen((status) {
      if (isClosed) return;
      emit(
        state.copyWith(
          state: status.state,
          message: status.message,
          progress: status.progress,
          installedRelease: status.installedRelease ?? state.installedRelease,
          latestManifest: _repository.latestManifest ?? state.latestManifest,
          errorMessage: status.error != null
              ? BlocklistSyncErrorFormatter.format(status.error)
              : null,
        ),
      );
    });

    // Load initial installed release asynchronously
    _initCurrentRelease();
  }

  Future<void> _initCurrentRelease() async {
    final release = await _repository.getInstalledRelease();
    if (isClosed) return;
    if (release != null) {
      emit(state.copyWith(installedRelease: release));
    }
  }

  Future<SyncResult>? _activeSyncFuture;

  /// Initiates synchronization against backend.
  Future<SyncResult> sync({bool force = false}) async {
    if (_activeSyncFuture != null) {
      return _activeSyncFuture!;
    }

    emit(
      state.copyWith(
        state: SyncState.checkingForUpdates,
        errorMessage: null,
        progress: null,
      ),
    );

    final future = _executeSync(force: force).whenComplete(() {
      _activeSyncFuture = null;
    });
    _activeSyncFuture = future;
    return future;
  }

  Future<SyncResult> _executeSync({required bool force}) async {
    try {
      final result = await _repository.sync(force: force);
      if (isClosed) return result;
      if (result.isSuccess) {
        emit(
          state.copyWith(
            state: result.isUpdated ? SyncState.updated : SyncState.upToDate,
            isCategoryEndpointsMissing: result.isCategoryEndpointsMissing,
            installedRelease: result.installedRelease ?? state.installedRelease,
            errorMessage: null,
            progress: null,
          ),
        );
      } else {
        final formattedError =
            BlocklistSyncErrorFormatter.format(result.error);
        emit(
          state.copyWith(
            state: SyncState.failed,
            errorMessage: formattedError,
            installedRelease: result.installedRelease ?? state.installedRelease,
            progress: null,
          ),
        );
      }
      return result;
    } catch (e) {
      final formattedError = BlocklistSyncErrorFormatter.format(e);
      if (!isClosed) {
        emit(
          state.copyWith(
            state: SyncState.failed,
            errorMessage: formattedError,
            progress: null,
          ),
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
