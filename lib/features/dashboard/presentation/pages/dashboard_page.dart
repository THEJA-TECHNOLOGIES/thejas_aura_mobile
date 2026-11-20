import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:theja_aura/core/utils/check_platforms.dart';
import 'package:theja_aura/core/utils/sized_context.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/mobile_widget.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/desktop_widget.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/tv_widget.dart';
import 'package:theja_aura/features/settings/presentation/pages/settings_page.dart';

import '../../../../core/utils/app_toast.dart';
import '../bloc/dashboard_bloc.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<DashboardBloc>().add(const DashboardEvent.appResumed());
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DashboardBloc, DashboardState>(
      listener: (context, state) {
        if (state.errorMessage != null) {
          showErrorToast(message: state.errorMessage!);
          debugPrint('Tunnel toggle error: ${state.errorMessage}');
          context.read<DashboardBloc>().add(
            const DashboardEvent.errorMessageDismissed(),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: const Text("Theja's Aura"),
            centerTitle: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.settings),
                tooltip: 'Settings',
                onPressed: () {
                  SettingsPage.show(context: context);
                },
              ),
            ],
          ),
          body: PlatformChecker.isAndroidTV ? TVWidget() : MobileWidget(),
        );
      },
    );
  }
}
