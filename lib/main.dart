import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
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
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();
  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => getIt<DashboardBloc>()),
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
      themeMode: ThemeMode.system,
      builder: (context, child) {
        return child ?? const Text('child');
      },
    );
  }
}
