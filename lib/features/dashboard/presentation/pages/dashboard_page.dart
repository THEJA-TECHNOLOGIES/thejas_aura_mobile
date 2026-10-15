import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/features/dashboard/presentation/pages/widgets/firewall_controller.dart';

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

  void _openLogs() async {
    await context.push('/logs');
    if (!mounted) return;
    context.read<DashboardBloc>().add(
      const DashboardEvent.statsRefreshRequested(),
    );
  }

  void _openLiveActivity() async {
    await context.push('/activity');
    if (!mounted) return;
    context.read<DashboardBloc>().add(
      const DashboardEvent.statsRefreshRequested(),
    );
  }

  void _openBlocklist() async {
    await context.push('/blocklist');
    if (!mounted) return;
    context.read<DashboardBloc>().add(
      const DashboardEvent.statsRefreshRequested(),
    );
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

                // B. Three CTA Buttons
                _buildCtaButtonsSection(),

                const SizedBox(height: 18),

                // C. Three Statistics Chips
                _buildStatisticsSection(context, state),

                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  // MARK: - Three CTA Buttons

  Widget _buildCtaButtonsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildCtaCard(
              label: 'Logs',
              subtitle: 'Blocked events',
              icon: Icons.notes,
              color: Colors.blueAccent,
              onTap: _openLogs,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildCtaCard(
              label: 'Live Activity',
              subtitle: 'All requests',
              icon: Icons.insights,
              color: Color(0XFF0B7F65),
              onTap: _openLiveActivity,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildCtaCard(
              label: 'Blocklist',
              subtitle: 'Domains & rules',
              icon: Icons.rule,
              color: Colors.deepPurpleAccent,
              onTap: _openBlocklist,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCtaCard({
    required String label,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
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

  // MARK: - Three Statistics Chips

  Widget _buildStatisticsSection(BuildContext context, DashboardState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatChip(
              context: context,
              subtitle: 'Blocked Today',
              value: state.blockedToday != null ? '${state.blockedToday}' : '—',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatChip(
              context: context,
              subtitle: 'This Week',
              value: state.blockedThisWeek != null
                  ? '${state.blockedThisWeek}'
                  : '—',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatChip(
              context: context,
              subtitle: 'All Time',
              value: state.totalBlockedDomains != null
                  ? '${state.totalBlockedDomains}'
                  : '—',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required BuildContext context,
    required String value,
    required String subtitle,
  }) {
    final colors = context.appColors;
    final typo = context.appTypography;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Text(
            value,
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
    );
  }
}
