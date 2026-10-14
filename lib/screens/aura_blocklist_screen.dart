import 'package:flutter/material.dart';
import 'package:theja_aura/core/services/aura_default_categories.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';

/// Dedicated Blocklist screen providing two primary tabs:
/// - Default Domains (bundled categories: Ads, Trackers, Analytics with modal domain inspector)
/// - Custom Domains (custom user rules with Allow/Block support, PSL validation, deletion confirmation)
class AuraBlocklistScreen extends StatefulWidget {
  final AuraTunnelService? tunnelService;

  const AuraBlocklistScreen({
    super.key,
    this.tunnelService,
  });

  @override
  State<AuraBlocklistScreen> createState() => _AuraBlocklistScreenState();
}

class _AuraBlocklistScreenState extends State<AuraBlocklistScreen>
    with SingleTickerProviderStateMixin {
  late final AuraTunnelService _service;
  late final TabController _tabController;

  // Default Domain Overrides State
  Set<String> _disabledDefaultDomains = {};
  bool _isLoadingOverrides = true;
  String? _overridesError;

  // Custom Rules State
  List<AuraRuleItem> _customRules = [];
  bool _isLoadingRules = true;
  String? _rulesError;
  int _activeRuleRequestId = 0;

  @override
  void initState() {
    super.initState();
    _service = widget.tunnelService ?? AuraTunnelService();
    _tabController = TabController(length: 2, vsync: this);
    _loadDefaultDomainOverrides();
    _loadCustomRules();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // MARK: - Default Domain Overrides Operations

  Future<void> _loadDefaultDomainOverrides() async {
    setState(() {
      _isLoadingOverrides = true;
      _overridesError = null;
    });

    try {
      final overrides = await _service.getDefaultDomainOverrides();
      if (!mounted) return;
      setState(() {
        _disabledDefaultDomains = overrides;
        _isLoadingOverrides = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingOverrides = false;
        _overridesError = 'Failed to load default domain overrides: $e';
      });
    }
  }

  void _openCategoryDomainBottomSheet(AuraDefaultCategory category) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return _CategoryDomainBottomSheet(
          category: category,
          disabledDomains: _disabledDefaultDomains,
          service: _service,
          onOverridesUpdated: (updated) {
            if (mounted) {
              setState(() {
                _disabledDefaultDomains = updated;
              });
            }
          },
        );
      },
    );
  }

  // MARK: - Custom Rules Operations

  Future<void> _loadCustomRules() async {
    final int requestId = ++_activeRuleRequestId;
    setState(() {
      _isLoadingRules = true;
      _rulesError = null;
    });

    try {
      final rules = await _service.getRules();
      if (!mounted || requestId != _activeRuleRequestId) return;

      if (rules == null) {
        setState(() {
          _isLoadingRules = false;
          _rulesError = 'Failed to read firewall rules from storage.';
        });
        return;
      }

      setState(() {
        _customRules = rules;
        _isLoadingRules = false;
      });
    } catch (e) {
      if (!mounted || requestId != _activeRuleRequestId) return;
      setState(() {
        _isLoadingRules = false;
        _rulesError = 'Failed to load rules: $e';
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
                        hintText: 'e.g. tracker.example.com',
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
                        const Text(
                          'Action: ',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
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
                        ? 'Queries matching this domain and subdomains will be blocked.'
                        : 'Queries matching this domain will bypass category blocking.',
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
                              _customRules.removeWhere((r) => r.id == newRule.id);
                              _customRules.insert(0, newRule);
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
        final index = _customRules.indexWhere((r) => r.id == rule.id);
        if (index != -1) {
          _customRules[index] = updated;
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
              foregroundColor: Colors.white,
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
        _customRules.removeWhere((r) => r.id == rule.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted rule for ${rule.domain}')),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blocklist'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Default Domains'),
            Tab(text: 'Custom Domains'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDefaultDomainsTab(),
          _buildCustomDomainsTab(),
        ],
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          if (_tabController.index != 1) return const SizedBox.shrink();
          return FloatingActionButton.extended(
            onPressed: () => _handleAddRule(isBlockedDefault: true),
            icon: const Icon(Icons.add),
            label: const Text('Add Domain'),
          );
        },
      ),
    );
  }

  // MARK: - Tab A: Default Domains

  Widget _buildDefaultDomainsTab() {
    if (_isLoadingOverrides) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_overridesError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(
                _overridesError!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadDefaultDomainOverrides,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final categories = AuraDefaultCategoryData.categories;

    return RefreshIndicator(
      onRefresh: _loadDefaultDomainOverrides,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Default Protection Categories',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Curated domain blocklists enforced directly on-device by the firewall engine. Tap any category to inspect its domains.',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          ),
          const SizedBox(height: 16),
          ...categories.map((category) {
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Colors.tealAccent.withValues(alpha: 0.2),
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _openCategoryDomainBottomSheet(category),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.tealAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          category.icon,
                          color: Colors.tealAccent,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  category.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade800,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${category.domainCount} domains',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              category.description,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.chevron_right,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // MARK: - Tab B: Custom Domains

  Widget _buildCustomDomainsTab() {
    if (_isLoadingRules) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_rulesError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(
                _rulesError!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadCustomRules,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_customRules.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.rule, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'No Custom Domains',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Add custom allow or block rules to fine-tune your firewall decisions.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => _handleAddRule(isBlockedDefault: true),
                icon: const Icon(Icons.add),
                label: const Text('Add Rule'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCustomRules,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        itemCount: _customRules.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final rule = _customRules[index];
          final isBlocked = rule.isBlocked;
          final isEnabled = rule.isEnabled;

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            leading: Icon(
              isBlocked ? Icons.block : Icons.check_circle_outline,
              color: isEnabled
                  ? (isBlocked ? Colors.redAccent : Colors.greenAccent)
                  : Colors.grey,
              size: 22,
            ),
            title: Text(
              rule.domain,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                decoration: isEnabled ? null : TextDecoration.lineThrough,
                color: isEnabled ? null : Colors.grey,
              ),
            ),
            subtitle: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: isBlocked
                        ? Colors.red.shade900.withValues(alpha: 0.5)
                        : Colors.green.shade900.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isBlocked ? 'BLOCK' : 'ALLOW',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isBlocked ? Colors.redAccent : Colors.greenAccent,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isEnabled ? 'Active' : 'Disabled',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: isEnabled,
                  onChanged: (_) => _handleToggleRule(rule),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: 'Delete Rule',
                  onPressed: () => _handleDeleteRule(rule),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Modal bottom sheet displaying the bundled domains of a default category.
/// Uses a virtualized, performant ListView.builder with instant local search
/// and individual enable/disable switches for each domain.
class _CategoryDomainBottomSheet extends StatefulWidget {
  final AuraDefaultCategory category;
  final Set<String> disabledDomains;
  final AuraTunnelService service;
  final ValueChanged<Set<String>>? onOverridesUpdated;

  const _CategoryDomainBottomSheet({
    required this.category,
    required this.disabledDomains,
    required this.service,
    this.onOverridesUpdated,
  });

  @override
  State<_CategoryDomainBottomSheet> createState() =>
      _CategoryDomainBottomSheetState();
}

class _CategoryDomainBottomSheetState extends State<_CategoryDomainBottomSheet> {
  final TextEditingController _searchController = TextEditingController();
  late Set<String> _disabledDomains;
  final Set<String> _pendingToggles = {};
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _disabledDomains = Set<String>.from(widget.disabledDomains);
  }

  @override
  void didUpdateWidget(covariant _CategoryDomainBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.disabledDomains != oldWidget.disabledDomains) {
      _disabledDomains = Set<String>.from(widget.disabledDomains);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleToggleDomain(String domain, bool isEnabled) async {
    if (_pendingToggles.contains(domain)) return;

    setState(() {
      _pendingToggles.add(domain);
      if (isEnabled) {
        _disabledDomains.remove(domain);
      } else {
        _disabledDomains.add(domain);
      }
    });
    widget.onOverridesUpdated?.call(_disabledDomains);

    try {
      final updated = await widget.service.toggleDefaultDomain(
        domain: domain,
        isEnabled: isEnabled,
      );
      if (!mounted) return;
      setState(() {
        _disabledDomains = updated;
        _pendingToggles.remove(domain);
      });
      widget.onOverridesUpdated?.call(_disabledDomains);
    } catch (e) {
      if (!mounted) return;
      // Rollback optimistic update
      setState(() {
        if (isEnabled) {
          _disabledDomains.add(domain);
        } else {
          _disabledDomains.remove(domain);
        }
        _pendingToggles.remove(domain);
      });
      widget.onOverridesUpdated?.call(_disabledDomains);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update $domain: $e'),
          backgroundColor: Colors.red.shade900,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final allDomains = widget.category.domains;
    final filteredDomains = _filter.isEmpty
        ? allDomains
        : allDomains.where((d) => d.contains(_filter.toLowerCase())).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade600,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(widget.category.icon, color: Colors.tealAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.category.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${widget.category.domainCount} bundled domains',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Search filter
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search domains in ${widget.category.name}...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _filter.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _filter = '');
                          },
                        )
                      : null,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: (val) {
                  setState(() => _filter = val.trim());
                },
              ),
            ),
            const Divider(height: 12),
            // Virtualized Domain List
            Expanded(
              child: filteredDomains.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _filter.isEmpty
                              ? 'No domains available.'
                              : 'No domains match "$_filter".',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: filteredDomains.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final domain = filteredDomains[index];
                        final isDomainEnabled = !_disabledDomains.contains(domain);
                        final isPending = _pendingToggles.contains(domain);

                        return ListTile(
                          dense: true,
                          leading: Icon(
                            isDomainEnabled ? Icons.shield : Icons.shield_outlined,
                            size: 18,
                            color: isDomainEnabled ? Colors.tealAccent : Colors.grey,
                          ),
                          title: Text(
                            domain,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              decoration: isDomainEnabled ? null : TextDecoration.lineThrough,
                              color: isDomainEnabled ? null : Colors.grey,
                            ),
                          ),
                          subtitle: Text(
                            isDomainEnabled ? 'Blocking active' : 'Excluded from blocking',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDomainEnabled
                                  ? Colors.tealAccent.withValues(alpha: 0.8)
                                  : Colors.grey.shade500,
                            ),
                          ),
                          trailing: Switch(
                            value: isDomainEnabled,
                            onChanged: isPending
                                ? null
                                : (val) => _handleToggleDomain(domain, val),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
