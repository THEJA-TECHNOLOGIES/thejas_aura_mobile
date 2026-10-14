import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/screens/aura_activity_screen.dart';
import 'package:theja_aura/screens/aura_blocklist_screen.dart';
import 'package:theja_aura/core/services/aura_activity_service.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';

import 'core/DI/injection.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();
  runApp(const AuraApp());
}

class AuraApp extends StatefulWidget {
  const AuraApp({super.key});

  @override
  State<AuraApp> createState() => _AuraAppState();
}

class _AuraAppState extends State<AuraApp> {
  late final GoRouter _goRouter;

  @override
  void initState() {
    super.initState();
    _goRouter = GoRouter(
      initialLocation: "/",
      navigatorKey: rootNavigatorKey,
      routes: [
        GoRoute(
          path: "/",
          builder: (context, state) => const AuraDashboardScreen(),
        ),
        GoRoute(
          path: "/logs",
          builder: (context, state) => const AuraActivityScreen(isLogsMode: true),
        ),
        GoRoute(
          path: "/activity",
          builder: (context, state) => const AuraActivityScreen(isLogsMode: false),
        ),
        GoRoute(
          path: "/blocklist",
          builder: (context, state) => const AuraBlocklistScreen(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: _goRouter,
      title: "Theja's Aura",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      builder: (context, child) {
        return child ?? const Text('child');
      },
    );
  }
}

class AuraDashboardScreen extends StatefulWidget {
  final AuraTunnelService? tunnelService;
  final AuraActivityService? activityService;

  const AuraDashboardScreen({
    super.key,
    this.tunnelService,
    this.activityService,
  });

  @override
  State<AuraDashboardScreen> createState() => _AuraDashboardScreenState();
}

class _AuraDashboardScreenState extends State<AuraDashboardScreen>
    with WidgetsBindingObserver {
  late final AuraTunnelService _tunnelService;
  late final AuraActivityService _activityService;

  TunnelStatus _status = TunnelStatus.disconnected;
  StreamSubscription<TunnelStatus>? _statusSubscription;

  bool _isInitialized = false;
  bool _isTogglingTunnel = false;

  // Exactly three statistics
  int? _blockedToday;
  int? _blockedThisWeek;
  int? _totalBlockedDomains;
  bool _isLoadingStats = false;
  String? _statsError;

  @override
  void initState() {
    super.initState();
    _tunnelService = widget.tunnelService ?? AuraTunnelService();
    _activityService = widget.activityService ?? AuraActivityService();

    WidgetsBinding.instance.addObserver(this);
    _initStatus();
    _statusSubscription = _tunnelService.statusStream.listen((newStatus) {
      if (mounted) {
        setState(() {
          _status = newStatus;
          _isTogglingTunnel = false;
        });
        _loadStats();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initStatus();
      _loadStats();
    }
  }

  Future<void> _initStatus() async {
    final current = await _tunnelService.getStatus();

    if (!mounted) return;
    setState(() {
      _status = current;
      _isInitialized = true;
    });

    _loadStats();
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    setState(() {
      _isLoadingStats = true;
      _statsError = null;
    });

    try {
      final now = DateTime.now();

      // 1. Blocked Today: start of local calendar day
      final startOfToday = DateTime(now.year, now.month, now.day);
      final millisToday = now.difference(startOfToday).inMilliseconds;

      // 2. Blocked This Week: start of local calendar week (Monday)
      final startOfWeek = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
      final millisThisWeek = now.difference(startOfWeek).inMilliseconds;

      // 3. Total Blocked Domains: distinct blocked domains overall (retained history)
      final millisAllTime = now.millisecondsSinceEpoch;

      final results = await Future.wait([
        _activityService.getDashboardStats(timeWindowMillis: millisToday),
        _activityService.getDashboardStats(timeWindowMillis: millisThisWeek),
        _activityService.getDashboardStats(timeWindowMillis: millisAllTime),
      ]);

      if (!mounted) return;
      setState(() {
        _blockedToday = results[0].totalBlocked;
        _blockedThisWeek = results[1].totalBlocked;
        _totalBlockedDomains = results[2].uniqueBlockedDomains;
        _isLoadingStats = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingStats = false;
        _statsError = 'Activity stats unavailable';
      });
    }
  }

  Future<void> _toggleTunnel() async {
    if (!_isInitialized || _isTogglingTunnel) return;

    setState(() {
      _isTogglingTunnel = true;
    });

    try {
      if (_status == TunnelStatus.connected) {
        await _tunnelService.stopTunnel();
      } else {
        await _tunnelService.startTunnel();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tunnel Action Failed: $e'),
            backgroundColor: Colors.red.shade900,
          ),
        );
      }
      debugPrint('Tunnel toggle error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isTogglingTunnel = false;
        });
        _loadStats();
      }
    }
  }

  void _openLogs() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => AuraActivityScreen(
              activityService: _activityService,
              isLogsMode: true,
            ),
          ),
        )
        .then((_) => _loadStats());
  }

  void _openLiveActivity() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => AuraActivityScreen(
              activityService: _activityService,
              isLogsMode: false,
            ),
          ),
        )
        .then((_) => _loadStats());
  }

  void _openBlocklist() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => AuraBlocklistScreen(
              tunnelService: _tunnelService,
            ),
          ),
        )
        .then((_) => _loadStats());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Theja's Aura"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              _initStatus();
              _loadStats();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // A. Firewall Enable / Disable Control
            _buildFirewallControlSection(),

            const SizedBox(height: 8),

            // B. Three CTA Buttons
            _buildCtaButtonsSection(),

            const SizedBox(height: 8),

            // C. Three Statistics Chips
            _buildStatisticsSection(),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // MARK: - Section A: Firewall Enable/Disable Control

  Widget _buildFirewallControlSection() {
    final isConnected = _status == TunnelStatus.connected;
    final isBusy = !_isInitialized ||
        _status == TunnelStatus.connecting ||
        _status == TunnelStatus.disconnecting ||
        _isTogglingTunnel;

    final String statusText;
    final String stateBadgeText;
    final Color stateColor;

    if (!_isInitialized) {
      statusText = 'Checking Firewall...';
      stateBadgeText = 'INITIALIZING';
      stateColor = Colors.grey;
    } else if (_isTogglingTunnel || _status == TunnelStatus.connecting) {
      statusText = 'Activating Protection...';
      stateBadgeText = 'CONNECTING';
      stateColor = Colors.amber;
    } else if (_status == TunnelStatus.disconnecting) {
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
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: stateColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: stateColor.withValues(alpha: 0.4)),
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
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: isBusy ? null : _toggleTunnel,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isConnected ? Colors.red.shade900 : Colors.deepPurple,
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
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 10,
                ),
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

  Widget _buildStatisticsSection() {
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
                const Icon(Icons.analytics,
                    size: 20, color: Colors.indigoAccent),
                const SizedBox(width: 8),
                const Text(
                  'Firewall Statistics',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_isLoadingStats)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: 'Refresh Stats',
                    onPressed: _loadStats,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_statsError != null) ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      Text(
                        _statsError!,
                        style: TextStyle(
                            color: Colors.grey.shade400, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _loadStats,
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
                      title: 'Blocked Today',
                      value: _blockedToday != null ? '$_blockedToday' : '—',
                      subtitle: 'events today',
                      icon: Icons.today,
                      color: Colors.redAccent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatChip(
                      title: 'Blocked This Week',
                      value:
                          _blockedThisWeek != null ? '$_blockedThisWeek' : '—',
                      subtitle: 'events this week',
                      icon: Icons.date_range,
                      color: Colors.orangeAccent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatChip(
                      title: 'Total Blocked Domains',
                      value: _totalBlockedDomains != null
                          ? '$_totalBlockedDomains'
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
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 9,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
