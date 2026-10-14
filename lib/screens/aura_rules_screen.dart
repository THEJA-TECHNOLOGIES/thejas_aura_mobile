import 'package:flutter/material.dart';
import '../core/services/aura_tunnel_service.dart';

/// Screen for managing custom DNS allowlist and blocklist rules.
class AuraRulesScreen extends StatefulWidget {
  const AuraRulesScreen({super.key});

  @override
  State<AuraRulesScreen> createState() => _AuraRulesScreenState();
}

class _AuraRulesScreenState extends State<AuraRulesScreen>
    with SingleTickerProviderStateMixin {
  final AuraTunnelService _service = AuraTunnelService();
  late TabController _tabController;

  List<AuraRuleItem> _rules = [];
  bool _isLoading = true;
  String? _errorMessage;
  int _activeRequestId = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadRules();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRules() async {
    final int requestId = ++_activeRequestId;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final rules = await _service.getRules();
      if (!mounted || requestId != _activeRequestId) return;

      if (rules == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to read firewall rules from storage.';
        });
        return;
      }

      setState(() {
        _rules = rules;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || requestId != _activeRequestId) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load rules: $e';
      });
    }
  }

  Future<void> _handleAddRule({required bool isBlockedDefault}) async {
    final domainController = TextEditingController();
    bool isBlocked = isBlockedDefault;
    String? validationError;
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isBlocked ? 'Add Block Rule' : 'Add Allow Rule'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: domainController,
                      autofocus: true,
                      autocorrect: false,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: 'Domain Name',
                        hintText: 'e.g. ads.example.com',
                        border: const OutlineInputBorder(),
                        errorText: validationError,
                      ),
                      onChanged: (val) {
                        if (validationError != null) {
                          setDialogState(() {
                            validationError = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Rule Action: ',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        ChoiceChip(
                          label: const Text('Block'),
                          selected: isBlocked,
                          selectedColor: Colors.red.shade900,
                          onSelected: (sel) {
                            if (sel) {
                              setDialogState(() => isBlocked = true);
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Allow'),
                          selected: !isBlocked,
                          selectedColor: Colors.green.shade900,
                          onSelected: (sel) {
                            if (sel) {
                              setDialogState(() => isBlocked = false);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isBlocked
                          ? 'Queries to this domain and subdomains will be blocked (0.0.0.0).'
                          : 'Queries to this domain and subdomains will bypass category blocking.',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final rawDomain = domainController.text.trim();
                          if (rawDomain.isEmpty) {
                            setDialogState(() {
                              validationError = 'Domain name cannot be empty.';
                            });
                            return;
                          }

                          setDialogState(() {
                            isSubmitting = true;
                            validationError = null;
                          });

                          try {
                            // Validate with native PSL validator
                            final validatedDomain =
                                await _service.validateDomain(rawDomain);

                            // Attempt native add
                            final newRule = await _service.addRule(
                              domain: validatedDomain,
                              isBlocked: isBlocked,
                            );

                            if (!dialogContext.mounted || !mounted) return;
                            Navigator.of(dialogContext).pop();

                            if (!mounted) return;
                            setState(() {
                              _rules.removeWhere((r) => r.id == newRule.id);
                              _rules.add(newRule);
                            });

                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Added rule for ${newRule.domain}',
                                ),
                                backgroundColor: isBlocked
                                    ? Colors.red.shade900
                                    : Colors.green.shade900,
                              ),
                            );
                          } on AuraRuleException catch (e) {
                            setDialogState(() {
                              isSubmitting = false;
                              validationError = e.message;
                            });
                          } catch (e) {
                            setDialogState(() {
                              isSubmitting = false;
                              validationError = 'Error: $e';
                            });
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Add Rule'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleToggleRule(AuraRuleItem rule) async {
    final newEnabled = !rule.isEnabled;

    try {
      final updated = await _service.toggleRule(rule.id, newEnabled);
      if (!mounted) return;

      setState(() {
        final index = _rules.indexWhere((r) => r.id == rule.id);
        if (index != -1) {
          _rules[index] = updated;
        }
      });
    } on AuraRuleException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to toggle rule: ${e.message}'),
          backgroundColor: Colors.red.shade900,
        ),
      );
    }
  }

  Future<void> _handleDeleteRule(AuraRuleItem rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Rule'),
        content: Text(
          'Are you sure you want to delete the rule for "${rule.domain}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade900,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _service.deleteRule(rule.id);
      if (!mounted) return;

      setState(() {
        _rules.removeWhere((r) => r.id == rule.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted rule for ${rule.domain}'),
        ),
      );
    } on AuraRuleException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete rule: ${e.message}'),
          backgroundColor: Colors.red.shade900,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final blockRules = _rules.where((r) => r.isBlocked).toList();
    final allowRules = _rules.where((r) => !r.isBlocked).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Firewall Rules'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRules,
            tooltip: 'Reload Rules',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.block, size: 18),
              text: 'Blocklist (${blockRules.length})',
            ),
            Tab(
              icon: const Icon(Icons.check_circle_outline, size: 18),
              text: 'Allowlist (${allowRules.length})',
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.redAccent),
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _loadRules,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildRuleList(
                      rules: blockRules,
                      isBlocked: true,
                    ),
                    _buildRuleList(
                      rules: allowRules,
                      isBlocked: false,
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final isBlockedDefault = _tabController.index == 0;
          _handleAddRule(isBlockedDefault: isBlockedDefault);
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Rule'),
      ),
    );
  }

  Widget _buildRuleList({
    required List<AuraRuleItem> rules,
    required bool isBlocked,
  }) {
    if (rules.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isBlocked ? Icons.block : Icons.check_circle_outline,
                size: 56,
                color: Colors.grey.shade600,
              ),
              const SizedBox(height: 16),
              Text(
                isBlocked
                    ? 'No custom block rules'
                    : 'No custom allow rules',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isBlocked
                    ? 'Add domains to block them across all apps.'
                    : 'Add domains to bypass default category blocking.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRules,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: rules.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final rule = rules[index];
          return ListTile(
            leading: Icon(
              rule.isBlocked ? Icons.block : Icons.check_circle,
              color: rule.isEnabled
                  ? (rule.isBlocked ? Colors.redAccent : Colors.greenAccent)
                  : Colors.grey,
            ),
            title: Text(
              rule.domain,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                decoration: rule.isEnabled
                    ? TextDecoration.none
                    : TextDecoration.lineThrough,
                color: rule.isEnabled ? null : Colors.grey,
              ),
            ),
            subtitle: Text(
              rule.isEnabled
                  ? (rule.isBlocked ? 'Blocking active' : 'Allowing active')
                  : 'Rule disabled',
              style: TextStyle(
                fontSize: 12,
                color: rule.isEnabled ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: rule.isEnabled,
                  onChanged: (_) => _handleToggleRule(rule),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.redAccent.shade100,
                  onPressed: () => _handleDeleteRule(rule),
                  tooltip: 'Delete Rule',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
