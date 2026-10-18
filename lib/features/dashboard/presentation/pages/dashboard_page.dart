import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/cta_buttons.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/firewall_controller.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/statistics_section.dart';

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
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: () {
                  context.read<DashboardBloc>().add(
                    const DashboardEvent.started(),
                  );
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 22),
                FirewallController(),
                const SizedBox(height: 18),
                StatisticsSection(),
                const SizedBox(height: 18),
                CTAButtons(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}
