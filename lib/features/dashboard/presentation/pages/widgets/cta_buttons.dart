import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/features/activity/presentation/pages/activity_page.dart';
import 'package:theja_aura/features/blocklist/presentation/pages/blocklist_page.dart';
import 'package:theja_aura/features/dashboard/presentation/bloc/dashboard_bloc.dart';

class CTAButtons extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    void openLiveActivity() async {
      ActivityPage.show(context: context);
      if (context.mounted) {
        context.read<DashboardBloc>().add(
          const DashboardEvent.statsRefreshRequested(),
        );
      }
    }

    void openBlocklist() async {
      // await context.push('/blocklist');
      BlocklistPage.show(context: context);
      if (context.mounted) {
        context.read<DashboardBloc>().add(
          const DashboardEvent.statsRefreshRequested(),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Expanded(
          //   child: CtaButtons(
          //     label: 'Logs',
          //     subtitle: 'Blocked events',
          //     icon: Icons.notes,
          //     color: Colors.blueAccent,
          //     onTap: openLogs,
          //   ),
          // ),
          // const SizedBox(width: 8),
          Expanded(
            child: CtaButtons(
              label: 'Live Activity',
              subtitle: 'All requests',
              icon: Icons.insights,
              color: Color(0XFF0B7F65),
              onTap: openLiveActivity,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: CtaButtons(
              label: 'Blocklist',
              subtitle: 'Domains & rules',
              icon: Icons.rule,
              color: Colors.deepPurpleAccent,
              onTap: openBlocklist,
            ),
          ),
        ],
      ),
    );
  }
}

class CtaButtons extends StatelessWidget {
  const new({
    super.key,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typo = context.appTypography;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: typo.titleMedium.copyWith(fontWeight: FontWeight.w600),
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
