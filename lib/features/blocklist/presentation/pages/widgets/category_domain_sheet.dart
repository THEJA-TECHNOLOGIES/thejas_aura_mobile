import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:theja_aura/core/services/aura_default_categories.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/core/utils/check_platforms.dart';
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
  late final FocusNode _searchFocusNode;
  late final FocusNode _clearFocusNode;
  final Set<String> _pendingToggles = {};
  String _filter = '';
  List<String>? _loadedDomains;
  bool _isLoadingDomains = false;
  bool _isSearchEditing = false;
  bool _isCloseFocused = false;

  @override
  void initState() {
    super.initState();
    _searchFocusNode = FocusNode(
      debugLabel: 'CategorySheetSearchFocusNode',
      onKeyEvent: _handleSearchKeyEvent,
    );
    _clearFocusNode = FocusNode(
      debugLabel: 'CategorySheetClearFocusNode',
      onKeyEvent: _handleClearKeyEvent,
    );
    _searchFocusNode.addListener(_onSearchFocusChange);
    if (widget.category.domains.isNotEmpty ||
        widget.category.domainCount == 0) {
      _loadedDomains = widget.category.domains;
    } else {
      _loadDomains();
    }
  }

  void _onSearchFocusChange() {
    if (!_searchFocusNode.hasFocus && _isSearchEditing) {
      setState(() {
        _isSearchEditing = false;
      });
    }
  }

  void _startSearchEditing() {
    if (!_isSearchEditing) {
      setState(() {
        _isSearchEditing = true;
      });
      _searchController.selection = TextSelection.collapsed(
        offset: _searchController.text.length,
      );
    }
  }

  void _stopSearchEditing() {
    if (_isSearchEditing) {
      setState(() {
        _isSearchEditing = false;
      });
    }
  }

  KeyEventResult _handleSearchKeyEvent(FocusNode node, KeyEvent event) {
    if (!PlatformChecker.isAndroidTV) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final isActivationKey =
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA;

    final isBackKey =
        key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack;

    if (!_isSearchEditing) {
      if (isActivationKey) {
        if (event is KeyDownEvent) {
          _startSearchEditing();
        }
        return KeyEventResult.handled;
      }

      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        if (key == LogicalKeyboardKey.arrowDown) {
          final moved = node.focusInDirection(TraversalDirection.down);
          if (moved) return KeyEventResult.handled;
          final next = node.nextFocus();
          return next ? KeyEventResult.handled : KeyEventResult.ignored;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          final moved = node.focusInDirection(TraversalDirection.up);
          if (moved) return KeyEventResult.handled;
          final prev = node.previousFocus();
          return prev ? KeyEventResult.handled : KeyEventResult.ignored;
        }
        if (key == LogicalKeyboardKey.arrowRight && _filter.isNotEmpty) {
          _clearFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
      }

      return KeyEventResult.ignored;
    } else {
      if (isBackKey) {
        if (event is KeyDownEvent) {
          _stopSearchEditing();
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
  }

  KeyEventResult _handleClearKeyEvent(FocusNode node, KeyEvent event) {
    if (!PlatformChecker.isAndroidTV) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final isActivationKey =
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA;

    if (isActivationKey) {
      if (event is KeyDownEvent) {
        _searchController.clear();
        setState(() => _filter = '');
        _searchFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        _searchFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        final moved = node.focusInDirection(TraversalDirection.down);
        if (moved) return KeyEventResult.handled;
        final next = node.nextFocus();
        return next ? KeyEventResult.handled : KeyEventResult.ignored;
      }
    }

    return KeyEventResult.ignored;
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
    _searchFocusNode.removeListener(_onSearchFocusChange);
    _searchFocusNode.dispose();
    _clearFocusNode.dispose();
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
    final isTv = PlatformChecker.isAndroidTV;
    final allDomains = _loadedDomains ?? widget.category.domains;
    final filteredDomains = _filter.isEmpty
        ? allDomains
        : allDomains.where((d) => d.contains(_filter.toLowerCase())).toList();

    return PopScope(
      canPop: !(isTv && _isSearchEditing),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && isTv && _isSearchEditing) {
          _stopSearchEditing();
        }
      },
      child: BlocBuilder<BlocklistBloc, BlocklistState>(
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
                        Material(
                          color: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: (isTv && _isCloseFocused)
                                  ? colors.primary
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onFocusChange: (f) =>
                                setState(() => _isCloseFocused = f),
                            onTap: () => Navigator.of(context).pop(),
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.close),
                            ),
                          ),
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
                      focusNode: _searchFocusNode,
                      controller: _searchController,
                      readOnly: isTv && !_isSearchEditing,
                      showCursor: !isTv || _isSearchEditing,
                      onTap: () {
                        if (isTv && !_isSearchEditing) {
                          _startSearchEditing();
                        }
                      },
                      onSubmitted: (_) {
                        if (isTv) {
                          _stopSearchEditing();
                        }
                      },
                      decoration: InputDecoration(
                        hintText:
                            'Search domains in ${widget.category.name}...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _filter.isNotEmpty
                            ? IconButton(
                                focusNode: _clearFocusNode,
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _filter = '');
                                  if (isTv) {
                                    _searchFocusNode.requestFocus();
                                  }
                                },
                              )
                            : null,
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: colors.primary,
                            width: 2,
                          ),
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
                                if (index < 0 ||
                                    index >= filteredDomains.length) {
                                  return const SizedBox.shrink();
                                }
                                final domain = filteredDomains[index];
                                final isDomainEnabled = !state
                                    .disabledDefaultDomains
                                    .contains(domain);
                                final isPending = _pendingToggles.contains(
                                  domain,
                                );
                                return _CategoryDomainCard(
                                  key: ValueKey(domain),
                                  domain: domain,
                                  isDomainEnabled: isDomainEnabled,
                                  isPending: isPending,
                                  onToggle: (val) =>
                                      _handleToggleDomain(domain, val),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _CategoryDomainCard extends StatefulWidget {
  final String domain;
  final bool isDomainEnabled;
  final bool isPending;
  final ValueChanged<bool> onToggle;

  const _CategoryDomainCard({
    super.key,
    required this.domain,
    required this.isDomainEnabled,
    required this.isPending,
    required this.onToggle,
  });

  @override
  State<_CategoryDomainCard> createState() => _CategoryDomainCardState();
}

class _CategoryDomainCardState extends State<_CategoryDomainCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typo = context.appTypography;
    final isTv = PlatformChecker.isAndroidTV;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: (isTv && _isFocused) ? colors.surfaceRaised : colors.segmentBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isTv && _isFocused) ? colors.primary : colors.border,
          width: isTv ? 2 : 1,
        ),
        boxShadow: (isTv && _isFocused)
            ? [
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onFocusChange: (focused) {
            setState(() => _isFocused = focused);
            if (focused && isTv) {
              Scrollable.ensureVisible(
                context,
                alignment: 0.5,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
              );
            }
          },
          onTap: widget.isPending
              ? null
              : () => widget.onToggle(!widget.isDomainEnabled),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.domain,
                        style: typo.titleMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '• ${!widget.isDomainEnabled ? "Allowed" : "Blocked"}',
                        style: typo.bodySmall.copyWith(
                          color: widget.isDomainEnabled
                              ? colors.primary
                              : colors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                ExcludeFocus(
                  excluding: isTv,
                  child: IgnorePointer(
                    ignoring: isTv,
                    child: Switch(
                      inactiveThumbColor: colors.textTertiary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      inactiveTrackColor: colors.trackOff,
                      value: widget.isDomainEnabled,
                      onChanged: widget.isPending
                          ? null
                          : (val) => widget.onToggle(val),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
