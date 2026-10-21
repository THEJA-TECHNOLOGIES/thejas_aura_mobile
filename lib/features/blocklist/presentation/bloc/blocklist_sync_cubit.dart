import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:injectable/injectable.dart';

import '../../domain/repositories/i_blocklist_sync_repository.dart';
import 'blocklist_sync_state.dart';

export '../../domain/repositories/i_blocklist_sync_repository.dart' show SyncState;
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
              ? _formatErrorMessage(status.error)
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

  /// Initiates synchronization against backend.
  Future<SyncResult> sync({bool force = false}) async {
    if (!state.isLoading) {
      emit(
        state.copyWith(
          state: SyncState.checkingForUpdates,
          errorMessage: null,
        ),
      );
    }

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
          ),
        );
      } else {
        emit(
          state.copyWith(
            state: SyncState.failed,
            errorMessage: _formatErrorMessage(result.error),
            installedRelease: result.installedRelease ?? state.installedRelease,
          ),
        );
      }
      return result;
    } catch (e) {
      if (!isClosed) {
        emit(
          state.copyWith(
            state: SyncState.failed,
            errorMessage: _formatErrorMessage(e.toString()),
          ),
        );
      }
      rethrow;
    }
  }

  String _formatErrorMessage(String? error) {
    if (error == null || error.trim().isEmpty) {
      return 'Failed to synchronize block lists. Please check your network connection and try again.';
    }
    var msg = error.trim();
    if (msg.startsWith('Exception: ')) {
      msg = msg.substring('Exception: '.length).trim();
    }
    if (msg.startsWith('BlocklistApiException: ')) {
      msg = msg.substring('BlocklistApiException: '.length).trim();
    }
    return msg.isNotEmpty
        ? msg
        : 'Failed to synchronize block lists. Please check your network connection and try again.';
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
