import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:theja_aura/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/bar_chart/bar_chart.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/bar_chart/individual_bar.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/block_list_sync_indicator.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/cta_buttons.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/firewall_controller.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/statistics_section.dart';

class MobileWidget extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 22),
          FirewallController(),
          const SizedBox(height: 16),
          BlockListSyncIndicator(),
          StatisticsSection(),
          const SizedBox(height: 16),
          CTAButtons(),
          SizedBox(
            height: 260,
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
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
