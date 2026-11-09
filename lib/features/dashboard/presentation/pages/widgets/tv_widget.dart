import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:theja_aura/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/bar_chart/bar_chart.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/bar_chart/individual_bar.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/block_list_sync_indicator.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/cta_buttons.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/firewall_controller.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/statistics_section.dart';

class TVWidget extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
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
            SizedBox(height: 18),
            CTAButtons(useRow: true),
          ],
        ),
      ),
    );
  }
}
