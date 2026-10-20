import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:theja_aura/core/services/aura_default_categories.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/features/blocklist/presentation/bloc/blocklist_bloc.dart';

import 'package:theja_aura/core/DI/injection.dart';
import 'package:theja_aura/features/blocklist/domain/repositories/i_blocklist_repository.dart';

class CategoryDomainSheet extends StatefulWidget {
  final AuraDefaultCategory category;
  final Set<String> disabledDomains;

  const CategoryDomainSheet({
    super.key,
    required this.category,
    required this.disabledDomains,
  });
  static Future<void> show({
    required BuildContext context,
    required AuraDefaultCategory category,
    required Set<String> disabledDomains,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // backgroundColor: Colors.transparent,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => CategoryDomainSheet(
        category: category,
        disabledDomains: disabledDomains,
      ),
    );
  }

  @override
  State<CategoryDomainSheet> createState() => _CategoryDomainSheetState();
}

class _CategoryDomainSheetState extends State<CategoryDomainSheet> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _pendingToggles = {};
  String _filter = '';
  List<String>? _loadedDomains;
  bool _isLoadingDomains = false;

  @override
  void initState() {
    super.initState();
    if (widget.category.domains.isNotEmpty ||
        widget.category.domainCount == 0) {
      _loadedDomains = widget.category.domains;
    } else {
      _loadDomains();
    }
  }

  Future<void> _loadDomains() async {
    setState(() => _isLoadingDomains = true);
    try {
      final domains = await getIt<IBlocklistRepository>().getCategoryDomains(
        widget.category.id.isNotEmpty
            ? widget.category.id
            : widget.category.name,
      );
      if (mounted) {
        setState(() {
          _loadedDomains = domains;
          _isLoadingDomains = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadedDomains = const [];
          _isLoadingDomains = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _handleToggleDomain(String domain, bool isEnabled) {
    context.read<BlocklistBloc>().add(
      BlocklistEvent.defaultDomainToggled(domain: domain, isEnabled: isEnabled),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typo = context.appTypography;
    final allDomains = _loadedDomains ?? widget.category.domains;
    final filteredDomains = _filter.isEmpty
        ? allDomains
        : allDomains.where((d) => d.contains(_filter.toLowerCase())).toList();

    return BlocBuilder<BlocklistBloc, BlocklistState>(
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
                              '${widget.category.domainCount} domains',
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
                  child: _isLoadingDomains
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : filteredDomains.isEmpty
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
                      : Scrollbar(
                          controller: scrollController,
                          thumbVisibility: true,
                          trackVisibility: true,
                          interactive: true,
                          thickness: 8.0,
                          child: ListView.separated(
                            controller: scrollController,
                            itemCount: filteredDomains.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              if (index < 0 || index >= filteredDomains.length) {
                                return const SizedBox.shrink();
                              }
                              final domain = filteredDomains[index];
                              final isDomainEnabled = !state
                                  .disabledDefaultDomains
                                  .contains(domain);
                              final isPending = _pendingToggles.contains(
                                domain,
                              );
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
                                            '• ${!isDomainEnabled ? "Allowed" : "Blocked"}',
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
                                          : (val) => _handleToggleDomain(
                                              domain,
                                              val,
                                            ),
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
                ),
              ],
            );
          },
        );
      },
    );
  }
}
