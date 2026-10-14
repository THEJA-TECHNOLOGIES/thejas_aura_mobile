import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/screens/aura_activity_screen.dart';
import 'package:theja_aura/screens/aura_rules_screen.dart';
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
          builder: (context, state) =>  Scaffold(
            appBar: AppBar(title: Text("data")),
          ),
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
        return child ?? Text('child');
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
  final TextEditingController _domainInputController = TextEditingController();
  StreamSubscription<TunnelStatus>? _statusSubscription;

  // Default seed rules for first launch
  static const List<AuraRuleItem> _defaultRules = [
    AuraRuleItem(
      domain: 'googleads.g.doubleclick.net',
      isEnabled: true,
      isBlocked: true,
    ),
    AuraRuleItem(
      domain: 'pagead2.googlesyndication.com',
      isEnabled: true,
      isBlocked: true,
    ),
    AuraRuleItem(
      domain: 'analytics.facebook.com',
      isEnabled: true,
      isBlocked: true,
    ),
    AuraRuleItem(domain: 'telemetry.app.com', isEnabled: true, isBlocked: true),
  ];

  List<AuraRuleItem> _rules = [];
  bool _isInitialized = false;

  // Category Preferences State
  Map<String, bool> _categories = {
    'Ads': true,
    'Trackers': true,
    'Analytics': true,
  };

  // Dashboard Activity Statistics State
  DashboardStatsData? _stats;
  List<TopBlockedDomainItem> _topBlocked = [];
  bool _isLoadingStats = false;
  String? _statsError;
  int _selectedStatsWindowMillis = 86400000; // 24 Hours default

  @override
  void initState() {
    super.initState();
    _tunnelService = widget.tunnelService ?? AuraTunnelService();
    _activityService = widget.activityService ?? AuraActivityService();

    WidgetsBinding.instance.addObserver(this);
    _initStatus();
    _statusSubscription = _tunnelService.statusStream.listen((newStatus) {
      if (mounted) setState(() => _status = newStatus);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusSubscription?.cancel();
    _domainInputController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initStatus();
    }
  }

  Future<void> _initStatus() async {
    final current = await _tunnelService.getStatus();
    final savedRules = await _tunnelService.getRules();
    final categories = await _tunnelService.getCategories();

    if (!mounted) return;

    setState(() {
      _categories = categories;
    });

    if (savedRules == null) {
      setState(() {
        _status = current;
        _isInitialized = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Warning: Failed to read rule store. Existing rules preserved.',
          ),
        ),
      );
      _loadStats();
      return;
    }

    setState(() {
      _status = current;
      if (savedRules.isNotEmpty) {
        _rules = savedRules;
      } else {
        _rules = List.of(_defaultRules);
      }
      _isInitialized = true;
    });

    if (savedRules.isEmpty) {
      await _tunnelService.syncRules(_rules);
    }

    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoadingStats = true;
      _statsError = null;
    });

    try {
      final stats = await _activityService.getDashboardStats(
        timeWindowMillis: _selectedStatsWindowMillis,
      );
      final top = await _activityService.getTopBlockedDomains(
        limit: 5,
        timeWindowMillis: _selectedStatsWindowMillis,
      );

      if (!mounted) return;
      setState(() {
        _stats = stats;
        _topBlocked = top;
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
    if (!_isInitialized) return;

    try {
      if (_status == TunnelStatus.connected) {
        await _tunnelService.stopTunnel();
      } else {
        await _tunnelService.syncRules(_rules);
        await _tunnelService.startTunnel();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Tunnel Action Failed: $e')));
      }
      debugPrint('Tunnel toggle error: $e');
    }
  }

  Future<void> _addCustomDomain() async {
    final rawDomain = _domainInputController.text.trim();
    if (rawDomain.isEmpty) return;

    try {
      final validated = await _tunnelService.validateDomain(rawDomain);
      final newRule = await _tunnelService.addRule(
        domain: validated,
        isBlocked: true,
      );
      if (!mounted) return;
      setState(() {
        _rules.removeWhere((r) => r.id == newRule.id);
        _rules.insert(0, newRule);
        _domainInputController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added block rule for ${newRule.domain}'),
          backgroundColor: Colors.red.shade900,
        ),
      );
    } on AuraRuleException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red.shade900,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error adding rule: $e'),
          backgroundColor: Colors.red.shade900,
        ),
      );
    }
  }

  Future<void> _toggleRule(int index, bool val) async {
    if (index < 0 || index >= _rules.length) return;
    final rule = _rules[index];
    try {
      final updated = await _tunnelService.toggleRule(rule.id, val);
      if (!mounted) return;
      setState(() {
        _rules[index] = updated;
      });
    } on AuraRuleException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update rule: ${e.message}')),
      );
    }
  }

  Future<void> _deleteRule(int index) async {
    if (index < 0 || index >= _rules.length) return;
    final rule = _rules[index];
    try {
      await _tunnelService.deleteRule(rule.id);
      if (!mounted) return;
      setState(() {
        _rules.removeAt(index);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted rule for ${rule.domain}')),
      );
    } on AuraRuleException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete rule: ${e.message}')),
      );
    }
  }

  Future<void> _toggleCategory(String category, bool newValue) async {
    final previousValue = _categories[category] ?? true;
    setState(() {
      _categories[category] = newValue;
    });

    try {
      final updated = await _tunnelService.setCategoryPreference(
        category,
        newValue,
      );
      if (!mounted) return;
      setState(() {
        _categories = updated;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _categories[category] = previousValue;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update $category: $e'),
          backgroundColor: Colors.red.shade900,
        ),
      );
    }
  }

  void _openRulesScreen() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AuraRulesScreen()))
        .then((_) {
          _refreshRules();
        });
  }

  Future<void> _refreshRules() async {
    final savedRules = await _tunnelService.getRules();
    if (savedRules != null && mounted) {
      setState(() {
        _rules = savedRules;
      });
    }
  }

  void _onWindowSelected(int windowMillis) {
    if (_selectedStatsWindowMillis == windowMillis) return;
    setState(() {
      _selectedStatsWindowMillis = windowMillis;
    });
    _loadStats();
  }

  void _openActivityLog() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) =>
                AuraActivityScreen(activityService: _activityService),
          ),
        )
        .then((_) {
          _loadStats();
        });
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _status == TunnelStatus.connected;
    final isBusy =
        !_isInitialized ||
        _status == TunnelStatus.connecting ||
        _status == TunnelStatus.disconnecting;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Theja's Aura"),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Firewall Rules',
            onPressed: _openRulesScreen,
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'DNS Activity Log',
            onPressed: _openActivityLog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _initStatus,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Status Shield Card
            Card(
              margin: const EdgeInsets.all(16),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(
                      isConnected ? Icons.shield : Icons.shield_outlined,
                      size: 72,
                      color: isConnected ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isConnected ? 'Protection Active' : 'Protection Disabled',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Upstream: Quad9 (9.9.9.9) • Local Split-Tunnel DNS',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: isBusy ? null : _toggleTunnel,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isConnected
                            ? Colors.red.shade900
                            : Colors.deepPurple,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(180, 46),
                      ),
                      child: Text(
                        !_isInitialized
                            ? 'Loading...'
                            : isBusy
                            ? 'Please Wait...'
                            : isConnected
                            ? 'Stop Firewall'
                            : 'Enable Firewall',
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Category Protection Controls Card
            _buildCategoryControlsCard(),

            // Custom Firewall Rules Summary Card
            _buildCustomRulesCard(),

            // DNS Activity Statistics Card
            _buildStatsCard(),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryControlsCard() {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.category, size: 20, color: Colors.tealAccent),
                const SizedBox(width: 8),
                const Text(
                  'Default Protection Categories',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Bundled blocklists enforced by local DNS engine',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
            const SizedBox(height: 12),
            _buildCategoryRow(
              'Ads',
              'Known advertising servers & ad delivery',
              Icons.ad_units,
            ),
            const Divider(height: 1),
            _buildCategoryRow(
              'Trackers',
              'Cross-site behavioral tracking & telemetry',
              Icons.track_changes,
            ),
            const Divider(height: 1),
            _buildCategoryRow(
              'Analytics',
              'Usage metrics and data broker endpoints',
              Icons.analytics_outlined,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryRow(String key, String description, IconData icon) {
    final isEnabled = _categories[key] ?? true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: isEnabled ? Colors.tealAccent : Colors.grey,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  key,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isEnabled ? null : Colors.grey,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                ),
              ],
            ),
          ),
          Switch(
            value: isEnabled,
            onChanged: (val) => _toggleCategory(key, val),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomRulesCard() {
    final blockCount = _rules.where((r) => r.isBlocked).length;
    final allowCount = _rules.where((r) => !r.isBlocked).length;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.security,
                  size: 20,
                  color: Colors.indigoAccent,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Custom Firewall Rules',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _openRulesScreen,
                  child: const Text(
                    'Manage Rules',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '$blockCount block rules • $allowCount allow rules',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _domainInputController,
                    decoration: const InputDecoration(
                      labelText: 'Quick Add Block Rule (e.g. google.com)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addCustomDomain(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.add),
                  onPressed: _addCustomDomain,
                  tooltip: 'Add Rule',
                ),
              ],
            ),
            if (_rules.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              ...List.generate(_rules.length > 4 ? 4 : _rules.length, (index) {
                final rule = _rules[index];
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    rule.isBlocked ? Icons.block : Icons.check_circle_outline,
                    color: rule.isEnabled
                        ? (rule.isBlocked
                              ? Colors.redAccent
                              : Colors.greenAccent)
                        : Colors.grey,
                    size: 18,
                  ),
                  title: Text(
                    rule.domain,
                    style: TextStyle(
                      fontSize: 13,
                      decoration: rule.isEnabled
                          ? null
                          : TextDecoration.lineThrough,
                      color: rule.isEnabled ? null : Colors.grey,
                    ),
                  ),
                  subtitle: Text(
                    rule.isEnabled
                        ? (rule.isBlocked ? 'Blocked' : 'Allowed')
                        : 'Disabled',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: rule.isEnabled,
                        onChanged: (val) => _toggleRule(index, val),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => _deleteRule(index),
                      ),
                    ],
                  ),
                );
              }),
              if (_rules.length > 4) ...[
                const SizedBox(height: 4),
                Center(
                  child: TextButton(
                    onPressed: _openRulesScreen,
                    child: Text(
                      'View all ${_rules.length} rules →',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.insights,
                  size: 20,
                  color: Colors.deepPurpleAccent,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Firewall Activity',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _openActivityLog,
                  child: const Text(
                    'View Logs',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Time Window Selector Chips
            Row(
              children: [
                ChoiceChip(
                  label: const Text('24h', style: TextStyle(fontSize: 12)),
                  selected: _selectedStatsWindowMillis == 86400000,
                  onSelected: (_) => _onWindowSelected(86400000),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('7d', style: TextStyle(fontSize: 12)),
                  selected: _selectedStatsWindowMillis == 604800000,
                  onSelected: (_) => _onWindowSelected(604800000),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('30d', style: TextStyle(fontSize: 12)),
                  selected: _selectedStatsWindowMillis == 2592000000,
                  onSelected: (_) => _onWindowSelected(2592000000),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_isLoadingStats) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(),
                ),
              ),
            ] else if (_statsError != null) ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      Text(
                        _statsError!,
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                        ),
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
            ] else if (_stats != null) ...[
              // Primary 2x2 Aggregate Grid
              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      label: 'Blocked Events',
                      value: '${_stats!.totalBlocked}',
                      color: Colors.redAccent,
                      subtitle:
                          '${_stats!.uniqueBlockedDomains} unique domains',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetricTile(
                      label: 'Allowed Queries',
                      value: '${_stats!.totalAllowed}',
                      color: Colors.greenAccent,
                      subtitle: '${_stats!.totalQueries} total requests',
                    ),
                  ),
                ],
              ),

              if (_topBlocked.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Top Blocked Domains',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 6),
                ...List.generate(_topBlocked.length, (i) {
                  final item = _topBlocked[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Text(
                          '${i + 1}.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade400,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.domain,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade900,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${item.count}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required Color color,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
