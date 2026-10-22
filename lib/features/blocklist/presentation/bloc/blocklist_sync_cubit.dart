import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:injectable/injectable.dart';

import '../../domain/repositories/i_blocklist_sync_repository.dart';
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
      emit(
        state.copyWith(
          state: status.state,
          message: status.message,
          progress: status.progress,
          installedRelease: status.installedRelease ?? state.installedRelease,
          latestManifest: _repository.latestManifest ?? state.latestManifest,
          errorMessage: status.error,
        ),
      );
    });

    // Load initial installed release asynchronously
    _initCurrentRelease();
  }

  Future<void> _initCurrentRelease() async {
    final release = await _repository.getInstalledRelease();
    if (release != null) {
      emit(state.copyWith(installedRelease: release));
    }
  }

  /// Initiates synchronization against backend.
  Future<SyncResult> sync({bool force = false}) async {
    final result = await _repository.sync(force: force);
    if (result.isSuccess) {
      emit(
        state.copyWith(
          state: result.isUpdated ? SyncState.updated : SyncState.upToDate,
          isCategoryEndpointsMissing: result.isCategoryEndpointsMissing,
          installedRelease: result.installedRelease ?? state.installedRelease,
        ),
      );
    } else {
      emit(
        state.copyWith(
          state: SyncState.failed,
          errorMessage: result.error,
          installedRelease: result.installedRelease ?? state.installedRelease,
        ),
      );
    }
    return result;
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
