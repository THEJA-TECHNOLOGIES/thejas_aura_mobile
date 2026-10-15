import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:theja_aura/core/services/aura_default_categories.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/core/utils/app_toast.dart';

import '../bloc/blocklist_bloc.dart';

class BlocklistPage extends StatefulWidget {
  const BlocklistPage({super.key});

  @override
  State<BlocklistPage> createState() => _BlocklistPageState();
}

class _BlocklistPageState extends State<BlocklistPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 2, vsync: this);
    context.read<BlocklistBloc>().add(const BlocklistEvent.started());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openCategoryDomainBottomSheet(
    AuraDefaultCategory category,
    Set<String> disabledDomains,
  ) {
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
          disabledDomains: disabledDomains,
          bloc: context.read<BlocklistBloc>(),
        );
      },
    );
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
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade400,
                      ),
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
                            final isValid = await context
                                .read<BlocklistBloc>()
                                .validateDomain(rawDomain);
                            if (!isValid) {
                              setDialogState(() {
                                isSubmitting = false;
                                validationError =
                                    'Invalid domain or public suffix rejected.';
                              });
                              return;
                            }
                            final success = await context
                                .read<BlocklistBloc>()
                                .addRule(
                                  domain: rawDomain,
                                  isBlocked: isBlocked,
                                );

                            if (!dialogContext.mounted || !mounted) return;
                            Navigator.of(dialogContext).pop();

                            if (success) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text('Added rule for $rawDomain'),
                                  backgroundColor: isBlocked
                                      ? Colors.red.shade900
                                      : Colors.green.shade900,
                                ),
                              );
                            }
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
    final success = await context.read<BlocklistBloc>().deleteRule(rule.id);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted rule for ${rule.domain}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typo = context.appTypography;
    return BlocConsumer<BlocklistBloc, BlocklistState>(
      listener: (context, state) {
        if (state.actionError != null) {
          showErrorToast(message: state.actionError!);
          context.read<BlocklistBloc>().add(
            const BlocklistEvent.actionErrorDismissed(),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(title: const Text('Block lists')),
          body: Column(
            children: [
              Container(
                padding: .all(4),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.segmentBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.border, width: 1),
                ),
                child: TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'Default'),
                    Tab(text: 'Custom'),
                  ],
                  labelStyle: typo.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  unselectedLabelStyle: typo.titleMedium.copyWith(
                    color: colors.textSecondary,
                  ),
                  dividerColor: Colors.transparent,
                  dividerHeight: 0.0,
                  indicator: BoxDecoration(
                    color: colors.card,
                    borderRadius: .circular(12),
                  ),
                  indicatorSize: .tab,
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildDefaultDomainsTab(state),
                    _buildCustomDomainsTab(state),
                  ],
                ),
              ),
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
      },
    );
  }

  Widget _buildDefaultDomainsTab(BlocklistState state) {
    final colors = context.appColors;
    final typo = context.appTypography;
    if (state.isLoadingOverrides) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.overridesError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 12),
              Text(
                state.overridesError!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => context.read<BlocklistBloc>().add(
                  const BlocklistEvent.defaultDomainOverridesRefreshRequested(),
                ),
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
      onRefresh: () async => context.read<BlocklistBloc>().add(
        const BlocklistEvent.defaultDomainOverridesRefreshRequested(),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...categories.map((category) {
            return GestureDetector(
              onTap: () => _openCategoryDomainBottomSheet(
                category,
                state.disabledDefaultDomains,
              ),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: colors.segmentBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.border, width: 1),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(category.icon, color: Colors.blue, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            category.name,
                            style: typo.titleMedium.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            category.description,
                            style: typo.bodySmall.copyWith(
                              color: colors.textSecondary,
                            ),
                            overflow: .ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      category.domainCount.toString(),
                      style: typo.titleSmall.copyWith(
                        fontWeight: .w600,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right, color: colors.textPrimary),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCustomDomainsTab(BlocklistState state) {
    final colors = context.appColors;
    final typo = context.appTypography;
    if (state.isLoadingRules) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.rulesError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 12),
              Text(
                state.rulesError!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => context.read<BlocklistBloc>().add(
                  const BlocklistEvent.customRulesRefreshRequested(),
                ),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (state.customRules.isEmpty) {
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
      onRefresh: () async => context.read<BlocklistBloc>().add(
        const BlocklistEvent.customRulesRefreshRequested(),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        itemCount: state.customRules.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final rule = state.customRules[index];
          final isBlocked = rule.isBlocked;
          final isEnabled = rule.isEnabled;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.segmentBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border, width: 1),
            ),
            child: Row(
              spacing: 8,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: [
                      Text(
                        rule.domain,
                        style: typo.titleMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '• ${isEnabled ? "Allowed" : "Blocked"}',
                        style: typo.bodySmall.copyWith(
                          color: isEnabled
                              ? colors.primary
                              : colors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  inactiveThumbColor: colors.textTertiary,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  inactiveTrackColor: colors.trackOff,
                  value: isEnabled,
                  onChanged: (val) => context.read<BlocklistBloc>().add(
                    BlocklistEvent.customRuleToggled(rule),
                  ),
                ),
                GestureDetector(
                  onTap: () => _handleDeleteRule(rule),
                  child: Icon(
                    CupertinoIcons.delete,
                    color: colors.textSecondary,
                    size: 24,
                  ),
                ),
              ],
            ),
          );

          // return ListTile(
          //   contentPadding: const EdgeInsets.symmetric(
          //     horizontal: 4,
          //     vertical: 4,
          //   ),
          //   leading: Icon(
          //     isBlocked ? Icons.block : Icons.check_circle_outline,
          //     color: isEnabled
          //         ? (isBlocked ? Colors.redAccent : Colors.greenAccent)
          //         : Colors.grey,
          //     size: 22,
          //   ),
          //   title: Text(
          //     rule.domain,
          //     style: TextStyle(
          //       fontWeight: FontWeight.w600,
          //       fontSize: 14,
          //       decoration: isEnabled ? null : TextDecoration.lineThrough,
          //       color: isEnabled ? null : Colors.grey,
          //     ),
          //   ),
          //   subtitle: Row(
          //     children: [
          //       Container(
          //         padding: const EdgeInsets.symmetric(
          //           horizontal: 6,
          //           vertical: 1,
          //         ),
          //         decoration: BoxDecoration(
          //           color: isBlocked
          //               ? Colors.red.shade900.withValues(alpha: 0.5)
          //               : Colors.green.shade900.withValues(alpha: 0.5),
          //           borderRadius: BorderRadius.circular(4),
          //         ),
          //         child: Text(
          //           isBlocked ? 'BLOCK' : 'ALLOW',
          //           style: TextStyle(
          //             fontSize: 10,
          //             fontWeight: FontWeight.bold,
          //             color: isBlocked ? Colors.redAccent : Colors.greenAccent,
          //           ),
          //         ),
          //       ),
          //       const SizedBox(width: 8),
          //       Text(
          //         isEnabled ? 'Active' : 'Disabled',
          //         style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
          //       ),
          //     ],
          //   ),
          //   trailing: Row(
          //     mainAxisSize: MainAxisSize.min,
          //     children: [
          //       Switch(
          //         value: isEnabled,
          //         onChanged: (_) => context.read<BlocklistBloc>().add(
          //           BlocklistEvent.customRuleToggled(rule),
          //         ),
          //       ),
          //       IconButton(
          //         icon: const Icon(Icons.delete_outline, size: 20),
          //         tooltip: 'Delete Rule',
          //         onPressed: () => _handleDeleteRule(rule),
          //       ),
          //     ],
          //   ),
          // );
        },
      ),
    );
  }
}

class _CategoryDomainBottomSheet extends StatefulWidget {
  final AuraDefaultCategory category;
  final Set<String> disabledDomains;
  final BlocklistBloc bloc;

  const _CategoryDomainBottomSheet({
    required this.category,
    required this.disabledDomains,
    required this.bloc,
  });

  @override
  State<_CategoryDomainBottomSheet> createState() =>
      _CategoryDomainBottomSheetState();
}

class _CategoryDomainBottomSheetState
    extends State<_CategoryDomainBottomSheet> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _pendingToggles = {};
  String _filter = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _handleToggleDomain(String domain, bool isEnabled) {
    widget.bloc.add(
      BlocklistEvent.defaultDomainToggled(domain: domain, isEnabled: isEnabled),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typo = context.appTypography;
    final allDomains = widget.category.domains;
    final filteredDomains = _filter.isEmpty
        ? allDomains
        : allDomains.where((d) => d.contains(_filter.toLowerCase())).toList();

    return BlocBuilder<BlocklistBloc, BlocklistState>(
      bloc: widget.bloc,
      builder: (context, state) {
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(widget.category.icon, color: Colors.blue),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
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
                          separatorBuilder: (context, index) =>
                              SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final domain = filteredDomains[index];
                            final isDomainEnabled = !state
                                .disabledDefaultDomains
                                .contains(domain);
                            final isPending = _pendingToggles.contains(domain);
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              margin: .symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: colors.segmentBg,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: colors.border,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: .start,
                                      children: [
                                        Text(
                                          domain,
                                          style: typo.titleMedium.copyWith(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '• ${isDomainEnabled ? "Allowed" : "Blocked"}',
                                          style: typo.bodySmall.copyWith(
                                            color: isDomainEnabled
                                                ? colors.primary
                                                : colors.textSecondary,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    inactiveThumbColor: colors.textTertiary,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    inactiveTrackColor: colors.trackOff,
                                    value: isDomainEnabled,
                                    onChanged: isPending
                                        ? null
                                        : (val) =>
                                              _handleToggleDomain(domain, val),
                                  ),
                                ],
                              ),
                            );
                            // return ListTile(
                            //   title: Text(
                            //     domain,
                            //     style: TextStyle(
                            //       fontFamily: 'monospace',
                            //       fontSize: 13,
                            //       fontWeight: FontWeight.w500,
                            //       decoration: isDomainEnabled
                            //           ? null
                            //           : TextDecoration.lineThrough,
                            //       color: isDomainEnabled ? null : Colors.grey,
                            //     ),
                            //   ),
                            //   subtitle: Text(
                            //     isDomainEnabled
                            //         ? 'Blocking active'
                            //         : 'Excluded from blocking',
                            //     style: TextStyle(
                            //       fontSize: 11,
                            //       color: isDomainEnabled
                            //           ? Colors.tealAccent.withValues(alpha: 0.8)
                            //           : Colors.grey.shade500,
                            //     ),
                            //   ),
                            //   trailing: Switch(
                            //     value: isDomainEnabled,
                            //     onChanged: isPending
                            //         ? null
                            //         : (val) => _handleToggleDomain(domain, val),
                            //   ),
                            // );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
