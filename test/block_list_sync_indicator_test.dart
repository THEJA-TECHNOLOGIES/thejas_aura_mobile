import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/features/blocklist/domain/models/blocklist_manifest.dart';
import 'package:theja_aura/features/blocklist/domain/models/installed_release_meta.dart';
import 'package:theja_aura/features/blocklist/domain/repositories/i_blocklist_sync_repository.dart';
import 'package:theja_aura/features/blocklist/presentation/bloc/blocklist_sync_cubit.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/block_list_sync_indicator.dart';

class FakeBlocklistSyncRepository implements IBlocklistSyncRepository {
  final StreamController<BlocklistSyncStatus> _controller =
      StreamController<BlocklistSyncStatus>.broadcast();
  BlocklistSyncStatus _currentStatus = BlocklistSyncStatus.initial();
  BlocklistManifest? _latestManifest;
  InstalledReleaseMeta? installedRelease;
  Future<SyncResult> Function({bool force})? syncHandler;

  @override
  Stream<BlocklistSyncStatus> get statusStream => _controller.stream;

  @override
  BlocklistSyncStatus get currentStatus => _currentStatus;

  @override
  BlocklistManifest? get latestManifest => _latestManifest;

  @override
  Future<InstalledReleaseMeta?> getInstalledRelease() async => installedRelease;

  @override
  Future<SyncResult> sync({bool force = false}) async {
    if (syncHandler != null) {
      return syncHandler!(force: force);
    }
    return const SyncResult(isSuccess: true, isUpdated: false, version: '1.0');
  }

  void emitStatus(BlocklistSyncStatus status) {
    _currentStatus = status;
    _controller.add(status);
  }

  void dispose() {
    _controller.close();
  }
}

Widget createTestWidget({required BlocklistSyncCubit cubit}) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: BlocProvider.value(
        value: cubit,
        child: const BlockListSyncIndicator(),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBlocklistSyncRepository repository;
  late BlocklistSyncCubit cubit;

  setUp(() {
    repository = FakeBlocklistSyncRepository();
    cubit = BlocklistSyncCubit(repository);
  });

  tearDown(() async {
    await cubit.close();
    repository.dispose();
  });

  group('BlocklistSyncCubit - State & Lifecycle', () {
    test('Initial state: isLoading is false and errorMessage is null', () {
      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.errorMessage, isNull);
    });

    test('Sync starts: isLoading is true and previous error is cleared', () async {
      final completer = Completer<SyncResult>();
      repository.syncHandler = ({bool force = false}) => completer.future;

      // Seed previous error
      repository.emitStatus(
        const BlocklistSyncStatus(
          state: SyncState.failed,
          error: 'Old network failure',
        ),
      );
      await pumpEventQueue();
      expect(cubit.state.errorMessage, equals('Old network failure'));
      expect(cubit.state.isLoading, isFalse);

      // Start sync
      final syncFuture = cubit.sync();
      expect(cubit.state.isLoading, isTrue);
      expect(cubit.state.errorMessage, isNull);

      // Complete sync
      completer.complete(
        const SyncResult(isSuccess: true, isUpdated: true, version: '2.0'),
      );
      await syncFuture;
      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.errorMessage, isNull);
    });

    test('Sync failure: isLoading is false and errorMessage is set', () async {
      repository.syncHandler = ({bool force = false}) async {
        return const SyncResult(
          isSuccess: false,
          isUpdated: false,
          version: '1.0',
          error: 'Connection timeout',
        );
      };

      final result = await cubit.sync();
      expect(result.isSuccess, isFalse);
      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.errorMessage, equals('Connection timeout'));
    });

    test('Unexpected exception does not leave cubit loading and is not swallowed', () async {
      repository.syncHandler = ({bool force = false}) async {
        throw Exception('Low level socket crash');
      };

      expect(() => cubit.sync(), throwsA(isA<Exception>()));
      await pumpEventQueue();

      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.errorMessage, contains('Low level socket crash'));
      expect(cubit.state.state, equals(SyncState.failed));
    });
  });

  group('BlockListSyncIndicator - Validation Scenarios', () {
    testWidgets('Scenario 1: Sync starts -> loading indicator appears', (tester) async {
      final completer = Completer<SyncResult>();
      repository.syncHandler = ({bool force = false}) => completer.future;

      await tester.pumpWidget(createTestWidget(cubit: cubit));
      // Initially idle -> nothing rendered
      expect(find.byType(LinearProgressIndicator), findsNothing);

      // Start sync
      unawaited(cubit.sync());
      await tester.pump();

      // Loading indicator appears
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Updating block lists..'), findsOneWidget);

      completer.complete(const SyncResult(isSuccess: true, isUpdated: true, version: '1.0'));
      await tester.pumpAndSettle();
    });

    testWidgets('Scenario 2: Sync succeeds -> loading indicator disappears and no success UI is shown', (tester) async {
      final completer = Completer<SyncResult>();
      repository.syncHandler = ({bool force = false}) => completer.future;

      await tester.pumpWidget(createTestWidget(cubit: cubit));

      unawaited(cubit.sync());
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      completer.complete(const SyncResult(isSuccess: true, isUpdated: true, version: '1.0'));
      await tester.pumpAndSettle();

      // Indicator removed, nothing rendered
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Updating block lists..'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(find.byType(Container), findsNothing);
    });

    testWidgets('Scenario 3: Sync fails -> loading indicator disappears and error details with Retry appear', (tester) async {
      repository.syncHandler = ({bool force = false}) async {
        return const SyncResult(
          isSuccess: false,
          isUpdated: false,
          version: '1.0',
          error: 'Server unavailable: 503',
        );
      };

      await tester.pumpWidget(createTestWidget(cubit: cubit));

      await cubit.sync();
      await tester.pumpAndSettle();

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Block list sync failed'), findsOneWidget);
      expect(find.text('Server unavailable: 503'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('Scenario 4: Retry succeeds -> error disappears and indicator is removed', (tester) async {
      var callCount = 0;
      final retryCompleter = Completer<SyncResult>();

      repository.syncHandler = ({bool force = false}) async {
        callCount++;
        if (callCount == 1) {
          return const SyncResult(
            isSuccess: false,
            isUpdated: false,
            version: '1.0',
            error: 'First failure',
          );
        } else {
          return retryCompleter.future;
        }
      };

      await tester.pumpWidget(createTestWidget(cubit: cubit));

      // First sync fails
      await cubit.sync();
      await tester.pumpAndSettle();

      expect(find.text('First failure'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // Tap Retry
      await tester.tap(find.text('Retry'));
      await tester.pump();

      // While retrying: loading indicator is shown and Retry button is gone
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Retry'), findsNothing);

      // Complete retry successfully
      retryCompleter.complete(const SyncResult(isSuccess: true, isUpdated: true, version: '2.0'));
      await tester.pumpAndSettle();

      // Error disappears and indicator is removed
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('First failure'), findsNothing);
      expect(find.byType(Container), findsNothing);
    });

    testWidgets('Scenario 5: Retry fails -> the error is updated and Retry remains available', (tester) async {
      var callCount = 0;

      repository.syncHandler = ({bool force = false}) async {
        callCount++;
        if (callCount == 1) {
          return const SyncResult(
            isSuccess: false,
            isUpdated: false,
            version: '1.0',
            error: 'Initial DNS error',
          );
        } else {
          return const SyncResult(
            isSuccess: false,
            isUpdated: false,
            version: '1.0',
            error: 'Secondary timeout error',
          );
        }
      };

      await tester.pumpWidget(createTestWidget(cubit: cubit));

      // First failure
      await cubit.sync();
      await tester.pumpAndSettle();
      expect(find.text('Initial DNS error'), findsOneWidget);

      // Tap Retry
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      // Error is updated and Retry remains available
      expect(find.text('Initial DNS error'), findsNothing);
      expect(find.text('Secondary timeout error'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('Scenario 6: An unexpected exception does not leave the UI stuck in a loading state', (tester) async {
      repository.syncHandler = ({bool force = false}) async {
        throw Exception('Native crash simulated');
      };

      await tester.pumpWidget(createTestWidget(cubit: cubit));

      // Trigger sync that throws
      try {
        await cubit.sync();
      } catch (_) {}

      await tester.pumpAndSettle();

      // UI is not stuck in loading state, error and Retry are shown
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Block list sync failed'), findsOneWidget);
      expect(find.textContaining('Native crash simulated'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
