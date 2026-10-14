import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:theja_aura/core/DI/injection.dart';
import 'package:theja_aura/features/activity/presentation/pages/activity_page.dart';
import 'package:theja_aura/features/blocklist/presentation/pages/blocklist_page.dart';

import '../bloc/dashboard_bloc.dart';

/// Compatibility alias
typedef AuraDashboardScreen = DashboardPage;

class DashboardPage extends StatefulWidget {
  final DashboardBloc? bloc;

  const DashboardPage({super.key, this.bloc});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver {
  late final DashboardBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = widget.bloc ?? getIt<DashboardBloc>();

    WidgetsBinding.instance.addObserver(this);
    _bloc.add(const DashboardEvent.started());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bloc.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _bloc.add(const DashboardEvent.appResumed());
    }
  }

  void _openLogs() async {
    if (GoRouter.maybeOf(context) != null) {
      await context.push('/logs');
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ActivityPage(isLogsMode: true)),
      );
    }
    if (!mounted) return;
    _bloc.add(const DashboardEvent.statsRefreshRequested());
  }

  void _openLiveActivity() async {
    if (GoRouter.maybeOf(context) != null) {
      await context.push('/activity');
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const ActivityPage(isLogsMode: false),
        ),
      );
    }
    if (!mounted) return;
    _bloc.add(const DashboardEvent.statsRefreshRequested());
  }

  void _openBlocklist() async {
    if (GoRouter.maybeOf(context) != null) {
      await context.push('/blocklist');
    } else {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const BlocklistPage()));
    }
    if (!mounted) return;
    _bloc.add(const DashboardEvent.statsRefreshRequested());
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _bloc,
      child: BlocConsumer<DashboardBloc, DashboardState>(
        listener: (context, state) {
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage!),
                backgroundColor: Colors.red.shade900,
              ),
            );
            debugPrint('Tunnel toggle error: ${state.errorMessage}');
            _bloc.add(const DashboardEvent.errorMessageDismissed());
          }
        },
        builder: (context, state) {
          return Scaffold(
            appBar: AppBar(
              title: const Text("Theja's Aura"),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                  onPressed: () {
                    _bloc.add(const DashboardEvent.started());
                  },
                ),
              ],
            ),
            body: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // A. Firewall Enable / Disable Control
                  _buildFirewallControlSection(context, state),

                  const SizedBox(height: 8),

                  // B. Three CTA Buttons
                  _buildCtaButtonsSection(),

                  const SizedBox(height: 8),

                  // C. Three Statistics Chips
                  _buildStatisticsSection(context, state),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // MARK: - Section A: Firewall Enable/Disable Control

  Widget _buildFirewallControlSection(
    BuildContext context,
    DashboardState state,
  ) {
    final isConnected = state.status == TunnelStatus.connected;
    final isBusy =
        !state.isInitialized ||
        state.status == TunnelStatus.connecting ||
        state.status == TunnelStatus.disconnecting ||
        state.isTogglingTunnel;

    final String statusText;
    final String stateBadgeText;
    final Color stateColor;

    if (!state.isInitialized) {
      statusText = 'Checking Firewall...';
      stateBadgeText = 'INITIALIZING';
      stateColor = Colors.grey;
    } else if (state.isTogglingTunnel ||
        state.status == TunnelStatus.connecting) {
      statusText = 'Activating Protection...';
      stateBadgeText = 'CONNECTING';
      stateColor = Colors.amber;
    } else if (state.status == TunnelStatus.disconnecting) {
      statusText = 'Deactivating Protection...';
      stateBadgeText = 'DISCONNECTING';
      stateColor = Colors.amber;
    } else if (isConnected) {
      statusText = 'Protection Active';
      stateBadgeText = 'ENABLED';
      stateColor = Colors.green;
    } else {
      statusText = 'Protection Disabled';
      stateBadgeText = 'DISABLED';
      stateColor = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isConnected ? Icons.shield : Icons.shield_outlined,
                  size: 64,
                  color: stateColor,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              statusText,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: stateColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: stateColor.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    stateBadgeText,
                    style: TextStyle(
                      color: stateColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Quad9 (9.9.9.9) • Local DNS',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: isBusy
                  ? null
                  : () => _bloc.add(const DashboardEvent.tunnelToggled()),
              style: ElevatedButton.styleFrom(
                backgroundColor: isConnected
                    ? Colors.red.shade900
                    : Colors.deepPurple,
                foregroundColor: Colors.white,
                minimumSize: const Size(200, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: isBusy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      isConnected ? 'Disable Firewall' : 'Enable Firewall',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // MARK: - Section B: Three CTA Buttons

  Widget _buildCtaButtonsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildCtaCard(
              label: 'Logs',
              subtitle: 'Blocked events',
              icon: Icons.block,
              color: Colors.redAccent,
              onTap: _openLogs,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildCtaCard(
              label: 'Live Activity',
              subtitle: 'All requests',
              icon: Icons.insights,
              color: Colors.tealAccent,
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
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 10),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // MARK: - Section C: Three Statistics Chips

  Widget _buildStatisticsSection(BuildContext context, DashboardState state) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.analytics,
                  size: 20,
                  color: Colors.indigoAccent,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Firewall Statistics',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (state.isLoadingStats)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: 'Refresh Stats',
                    onPressed: () =>
                        _bloc.add(const DashboardEvent.statsRefreshRequested()),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (state.statsError != null) ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      Text(
                        state.statsError!,
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () => _bloc.add(
                          const DashboardEvent.statsRefreshRequested(),
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: _buildStatChip(
                      context: context,
                      title: 'Blocked Today',
                      value: state.blockedToday != null
                          ? '${state.blockedToday}'
                          : '—',
                      subtitle: 'events today',
                      icon: Icons.today,
                      color: Colors.redAccent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatChip(
                      context: context,
                      title: 'Blocked This Week',
                      value: state.blockedThisWeek != null
                          ? '${state.blockedThisWeek}'
                          : '—',
                      subtitle: 'events this week',
                      icon: Icons.date_range,
                      color: Colors.orangeAccent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatChip(
                      context: context,
                      title: 'Total Blocked Domains',
                      value: state.totalBlockedDomains != null
                          ? '${state.totalBlockedDomains}'
                          : '—',
                      subtitle: 'unique domains',
                      icon: Icons.public_off,
                      color: Colors.purpleAccent,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip({
    required BuildContext context,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 9),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
