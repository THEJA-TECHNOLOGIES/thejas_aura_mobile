import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/core/utils/app_utils.dart';
import 'package:theja_aura/features/activity/presentation/pages/activity_page.dart';
import 'package:theja_aura/features/dashboard/presentation/bloc/dashboard_bloc.dart';

class StatisticsSection extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocSelector<DashboardBloc, DashboardState, (int?, int?, int?)>(
      selector: (s) =>
          (s.blockedToday, s.blockedThisWeek, s.totalBlockedDomains),
      builder: (context, state) {
        final (blockedToday, blockedThisWeek, totalBlockedDomains) = state;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: StatisticsCard(
                  subtitle: 'Blocked Today',
                  value: blockedToday,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatisticsCard(
                  subtitle: 'This Week',
                  value: blockedThisWeek,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatisticsCard(
                  subtitle: 'All Time',
                  value: totalBlockedDomains,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class StatisticsCard extends StatelessWidget {
  const new({super.key, required this.subtitle, required this.value});
  final int? value;
  final String subtitle;
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typo = context.appTypography;
    return GestureDetector(
      onTap: () async {
        ActivityPage.show(context: context, isLogsMode: true);
        if (context.mounted) {
          context.read<DashboardBloc>().add(
            const DashboardEvent.statsRefreshRequested(),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          children: [
            Text(
              formatNumber(value ?? 0),
              style: typo.titleLarge.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: typo.bodySmall.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
