import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/core/utils/check_platforms.dart';
import 'package:theja_aura/features/activity/domain/repositories/i_activity_repository.dart';
import 'package:theja_aura/features/activity/presentation/bloc/activity_bloc.dart';
import 'package:theja_aura/features/blocklist/domain/repositories/i_blocklist_sync_repository.dart';
import 'package:theja_aura/features/blocklist/presentation/bloc/blocklist_bloc.dart';
import 'package:theja_aura/features/blocklist/presentation/bloc/blocklist_sync_cubit.dart';
import 'package:theja_aura/features/dashboard/presentation/bloc/dashboard_bloc.dart';

import 'core/DI/injection.dart';
import 'features/activity/presentation/pages/activity_page.dart';
import 'features/blocklist/presentation/pages/blocklist_page.dart';
import 'features/dashboard/presentation/pages/dashboard_page.dart';

export 'features/dashboard/presentation/pages/dashboard_page.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

void main() async {
  // 1. Initialize Flutter bindings
  WidgetsFlutterBinding.ensureInitialized();
  await PlatformChecker.initialize();
  // 2. Load environment configuration & 3. Configure dependencies
  await configureDependencies();

  // 4. Initialize required local/native storage and verify readiness (independent of VPN)
  try {
    await getIt<IActivityRepository>().initializeDatabase();
  } catch (e) {
    debugPrint('Database pre-initialization notice: $e');
  }

  // 5. Start manifest synchronization immediately
  final syncCubit = getIt<BlocklistSyncCubit>();
  unawaited(
    syncCubit.sync().catchError((error) {
      debugPrint('Startup blocklist sync notice: $error');
      return SyncResult.failure(error: error.toString());
    }),
  );

  // 6. Allow application UI to render without waiting for the network download
  // 7. Expose synchronization status through existing state-management architecture
  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) =>
              getIt<DashboardBloc>()..add(const DashboardEvent.started()),
        ),
        BlocProvider(create: (_) => getIt<ActivityBloc>()),
        BlocProvider(create: (_) => getIt<BlocklistBloc>()),
        BlocProvider.value(value: syncCubit),
      ],
      child: const AuraApp(),
    ),
  );
}

class AuraApp extends StatefulWidget {
  const AuraApp({super.key});

  @override
  State<AuraApp> createState() => _AuraAppState();
}

class _AuraAppState extends State<AuraApp> {
  late final GoRouter _goRouter;

  @override
  void initState() {
    super.initState();
    _goRouter = GoRouter(
      initialLocation: "/",
      navigatorKey: rootNavigatorKey,
      routes: [
        GoRoute(path: "/", builder: (context, state) => const DashboardPage()),
        GoRoute(
          path: "/logs",
          builder: (context, state) => const ActivityPage(isLogsMode: true),
        ),
        GoRoute(
          path: "/activity",
          builder: (context, state) => const ActivityPage(isLogsMode: false),
        ),
        GoRoute(
          path: "/blocklist",
          builder: (context, state) => const BlocklistPage(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: _goRouter,
      title: "Theja's Aura",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: PlatformChecker.isAndroidTV ? .light : ThemeMode.system,
      builder: (context, child) {
        return child ?? const Text('child');
      },
    );
  }
}
