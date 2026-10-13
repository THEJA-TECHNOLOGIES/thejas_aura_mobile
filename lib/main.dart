import 'package:flutter/material.dart';
import 'package:theja_aura/services/aura_tunnel_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AuraApp());
}

class AuraApp extends StatelessWidget {
  const AuraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Theja's Aura",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
      ),
      home: const AuraDashboardScreen(),
    );
  }
}

class AuraDashboardScreen extends StatefulWidget {
  const AuraDashboardScreen({super.key});

  @override
  State<AuraDashboardScreen> createState() => _AuraDashboardScreenState();
}

class _AuraDashboardScreenState extends State<AuraDashboardScreen> {
  final AuraTunnelService _tunnelService = AuraTunnelService();
  TunnelStatus _status = TunnelStatus.disconnected;
  final TextEditingController _domainInputController = TextEditingController();

  // Default blocklist seed + user rules
  final List<AuraRuleItem> _rules = [
    const AuraRuleItem(domain: 'googleads.g.doubleclick.net', isEnabled: true, isBlocked: true),
    const AuraRuleItem(domain: 'pagead2.googlesyndication.com', isEnabled: true, isBlocked: true),
    const AuraRuleItem(domain: 'analytics.facebook.com', isEnabled: true, isBlocked: true),
    const AuraRuleItem(domain: 'telemetry.app.com', isEnabled: true, isBlocked: true),
  ];

  @override
  void initState() {
    super.initState();
    _initStatus();
    _tunnelService.statusStream.listen((newStatus) {
      if (mounted) setState(() => _status = newStatus);
    });
  }

  Future<void> _initStatus() async {
    final current = await _tunnelService.getStatus();
    if (mounted) setState(() => _status = current);
    await _tunnelService.syncRules(_rules);
  }

  Future<void> _toggleTunnel() async {
    try {
      if (_status == TunnelStatus.connected) {
        await _tunnelService.stopTunnel();
      } else {
        await _tunnelService.syncRules(_rules);
        await _tunnelService.startTunnel();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tunnel Action Failed: $e')),
        );
      }
      print(e);
    }
  }

  Future<void> _addCustomDomain() async {
    final domain = _domainInputController.text.trim();
    if (domain.isEmpty) return;

    setState(() {
      _rules.insert(0, AuraRuleItem(domain: domain, isEnabled: true, isBlocked: true));
      _domainInputController.clear();
    });
    await _tunnelService.syncRules(_rules);
  }

  Future<void> _toggleRule(int index, bool val) async {
    setState(() {
      final old = _rules[index];
      _rules[index] = AuraRuleItem(
        domain: old.domain,
        isEnabled: val,
        isBlocked: old.isBlocked,
      );
    });
    await _tunnelService.syncRules(_rules);
  }

  Future<void> _deleteRule(int index) async {
    setState(() {
      _rules.removeAt(index);
    });
    await _tunnelService.syncRules(_rules);
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _status == TunnelStatus.connected;
    final isBusy = _status == TunnelStatus.connecting || _status == TunnelStatus.disconnecting;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Theja's Aura"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _initStatus,
          ),
        ],
      ),
      body: Column(
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
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Upstream: Quad9 (9.9.9.9) • Local Split-Tunnel DNS',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: isBusy ? null : _toggleTunnel,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isConnected ? Colors.red.shade900 : Colors.deepPurple,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(180, 46),
                    ),
                    child: Text(
                      isBusy
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

          // Custom Domain Input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _domainInputController,
                    decoration: const InputDecoration(
                      labelText: 'Add Custom Domain (e.g. google.com)',
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
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          const Divider(),

          // Active Rules List
          Expanded(
            child: ListView.builder(
              itemCount: _rules.length,
              itemBuilder: (context, index) {
                final rule = _rules[index];
                return ListTile(
                  leading: Icon(
                    rule.isEnabled ? Icons.block : Icons.check_circle_outline,
                    color: rule.isEnabled ? Colors.redAccent : Colors.grey,
                  ),
                  title: Text(rule.domain),
                  subtitle: Text(rule.isEnabled ? 'Blocked' : 'Disabled'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: rule.isEnabled,
                        onChanged: (val) => _toggleRule(index, val),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _deleteRule(index),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
