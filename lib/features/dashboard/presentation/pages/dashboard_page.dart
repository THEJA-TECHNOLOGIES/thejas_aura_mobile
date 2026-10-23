import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/core/utils/sized_context.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/bar_chart/bar_chart.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/bar_chart/individual_bar.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/block_list_sync_indicator.dart';
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
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith<Color?>((
                    states,
                  ) {
                    if (states.contains(WidgetState.focused)) {
                      return context.appColors.primary;
                    }
                    return context.appColors.surfaceRaised; // Default color
                  }),
                ),
                onPressed: () {
                  context.read<DashboardBloc>().add(
                    const DashboardEvent.started(),
                  );
                },
              ),
            ],
          ),
          body: !context.isMobile
              ? Align(
                  alignment: .topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 1200),
                    child: Column(
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(left: 16),
                                child: FirewallController(),
                              ),
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    BlockListSyncIndicator(),
                                    StatisticsSection(),
                                    Expanded(
                                      child: BlocSelector<DashboardBloc, DashboardState, List<IndividualBar>>(
                                        selector: (s) => s.chartData,
                                        builder: (context, chartData) {
                                          return AppBarChart(data: chartData);
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 18),
                        CTAButtons(useRow: true),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: 22),
                      FirewallController(),
                      const SizedBox(height: 18),
                      BlockListSyncIndicator(),
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
