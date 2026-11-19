import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:theja_aura/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/bar_chart/bar_chart.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/bar_chart/individual_bar.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/block_list_sync_indicator.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/cta_buttons.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/firewall_controller.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/statistics_section.dart';

class DesktopWidget extends StatefulWidget {
  const new({super.key});

  @override
  State<DesktopWidget> createState() => _DesktopWidgetState();
}

enum TabType { logs, activity, blocklist }

class _DesktopWidgetState extends State<DesktopWidget> {
  TabType tabType = .activity;
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Align(
        alignment: .topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 8),
              IntrinsicHeight(
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: FirewallController(),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          StatisticsSection(),
                          SizedBox(
                            height: 290,
                            child:
                                BlocSelector<
                                  DashboardBloc,
                                  DashboardState,
                                  List<IndividualBar>
                                >(
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
              const SizedBox(height: 16),
              BlockListSyncIndicator(),
              // const SizedBox(height: 16),
              CTAButtons(
                useRow: true,
                // onLogsTaped: () {
                //   context.read<DashboardBloc>().add(
                //     const DashboardEvent.statsRefreshRequested(),
                //   );
                // },
                // onActivityTaped: () {
                //   context.read<DashboardBloc>().add(
                //     const DashboardEvent.statsRefreshRequested(),
                //   );
                // },
                // onBlocklistTaped: () {
                //   context.read<DashboardBloc>().add(
                //     const DashboardEvent.statsRefreshRequested(),
                //   );
                // },
              ),
              const SizedBox(height: 24),
              // tabType == TabType.logs
              //     ? ActivityPage(isLogsMode: true, shrinkWrap: true)
              //     : tabType == TabType.activity
              //     ? ActivityPage(isLogsMode: false)
              //     : BlocklistPage(),
            ],
          ),
        ),
      ),
    );
  }
}
