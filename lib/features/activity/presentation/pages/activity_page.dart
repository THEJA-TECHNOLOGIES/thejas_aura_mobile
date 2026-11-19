import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/core/utils/app_button.dart';
import 'package:theja_aura/core/utils/app_toast.dart';
import 'package:theja_aura/core/utils/app_utils.dart';
import 'package:theja_aura/core/utils/check_platforms.dart';
import 'package:theja_aura/features/timeago/timeago.dart';

import 'package:theja_aura/core/services/aura_activity_service.dart';
import 'package:theja_aura/core/services/aura_domain_evaluator.dart';

import '../bloc/activity_bloc.dart';

class ActivityPage extends StatefulWidget {
  final bool isLogsMode;
  final bool isModal;
  final bool shrinkWrap;
  const ActivityPage({
    super.key,
    this.isLogsMode = false,
    this.isModal = false,
    this.shrinkWrap = false,
  });
  static Future<void> show({
    required BuildContext context,
    bool isLogsMode = false,
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
      builder: (sheetContext) =>
          ActivityPage(isLogsMode: isLogsMode, isModal: true),
    );
  }

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  late final FocusNode _searchFocusNode;
  late final FocusNode _clearSearchFocusNode;
  bool _isLoadMoreRequested = false;
  bool _isSearchEditing = false;

  @override
  void initState() {
    super.initState();
    _searchFocusNode = FocusNode(
      debugLabel: 'ActivitySearchFocusNode',
      onKeyEvent: _handleSearchKeyEvent,
    );
    _searchFocusNode.addListener(_onSearchFocusChanged);
    _clearSearchFocusNode = FocusNode(
      debugLabel: 'ActivitySearchClearFocusNode',
      onKeyEvent: _handleClearSearchKeyEvent,
    );
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    context.read<ActivityBloc>().add(
      ActivityEvent.started(isLogsMode: widget.isLogsMode),
    );
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchFocusNode.dispose();
    _clearSearchFocusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchFocusChanged() {
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
        if (key == LogicalKeyboardKey.arrowRight) {
          final bloc = context.read<ActivityBloc>();
          if (bloc.state.searchQuery.isNotEmpty) {
            _clearSearchFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          final moved = node.focusInDirection(TraversalDirection.right);
          return moved ? KeyEventResult.handled : KeyEventResult.ignored;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          final moved = node.focusInDirection(TraversalDirection.left);
          return moved ? KeyEventResult.handled : KeyEventResult.ignored;
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

  KeyEventResult _handleClearSearchKeyEvent(FocusNode node, KeyEvent event) {
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
        _onClearSearchPressed();
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
      if (key == LogicalKeyboardKey.arrowUp) {
        final moved = node.focusInDirection(TraversalDirection.up);
        if (moved) return KeyEventResult.handled;
        final prev = node.previousFocus();
        return prev ? KeyEventResult.handled : KeyEventResult.ignored;
      }
    }

    return KeyEventResult.ignored;
  }

  void _onClearSearchPressed() {
    _searchController.clear();
    context.read<ActivityBloc>().add(
      const ActivityEvent.searchQueryChanged(''),
    );
    if (PlatformChecker.isAndroidTV) {
      _searchFocusNode.requestFocus();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<ActivityBloc>().add(const ActivityEvent.appResumed());
    }
  }

  void _onScroll() {
    final bloc = context.read<ActivityBloc>();
    if (!_scrollController.hasClients) return;
    if (_isLoadMoreRequested) return;

    final position = _scrollController.position;
    final maxScroll = position.maxScrollExtent;
    final currentScroll = position.pixels;

    if (currentScroll >= maxScroll - 200 &&
        bloc.state.hasMore &&
        !bloc.state.isLoading &&
        !bloc.state.isLoadingMore) {
      _isLoadMoreRequested = true;
      bloc.add(const ActivityEvent.loadMoreRequested());
    }
  }

  void _onOutcomeChanged(String outcome) {
    if (widget.isLogsMode) return;
    context.read<ActivityBloc>().add(
      ActivityEvent.outcomeFilterChanged(outcome),
    );
  }

  void _clearFilters() {
    _stopSearchEditing();
    _searchController.clear();
    context.read<ActivityBloc>().add(
      const ActivityEvent.searchQueryChanged(''),
    );
    context.read<ActivityBloc>().add(
      ActivityEvent.outcomeFilterChanged(widget.isLogsMode ? 'blocked' : 'all'),
    );
    context.read<ActivityBloc>().add(
      const ActivityEvent.timeWindowFilterChanged(null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLogs = widget.isLogsMode;
    final screenTitle = isLogs ? 'Logs' : 'Live Activity';

    return BlocConsumer<ActivityBloc, ActivityState>(
      listener: (context, state) {
        if (!state.isLoadingMore) {
          _isLoadMoreRequested = false;
        }
        if (state.actionError != null) {
          showErrorToast(message: state.actionError!);
          context.read<ActivityBloc>().add(
            const ActivityEvent.actionErrorDismissed(),
          );
        }
      },
      builder: (context, state) {
        final isTv = PlatformChecker.isAndroidTV;

        return PopScope(
          canPop: !(isTv && _isSearchEditing),
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && isTv && _isSearchEditing) {
              _stopSearchEditing();
            }
          },
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),

            child: Scaffold(
              appBar: AppBar(
                title: Text(screenTitle),
                leading:
                    (isTv && (widget.isModal || Navigator.of(context).canPop()))
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Close',
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                      )
                    : null,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh',
                    onPressed: () => context.read<ActivityBloc>().add(
                      const ActivityEvent.refreshRequested(),
                    ),
                  ),
                ],
              ),
              body: Column(
                children: [
                  if (isLogs)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                          hintText: isLogs
                              ? 'Search blocked domains...'
                              : 'Search captured domains...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: state.searchQuery.isNotEmpty
                              ? IconButton(
                                  focusNode: _clearSearchFocusNode,
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: _onClearSearchPressed,
                                )
                              : null,
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onChanged: (val) => context.read<ActivityBloc>().add(
                          ActivityEvent.searchQueryChanged(val),
                        ),
                      ),
                    ),

                  if (!isLogs)
                    _ActivityFilterBar(
                      key: const ValueKey('activity_outcome_filter_bar'),
                      selectedOutcome: state.selectedOutcome,
                      onOutcomeChanged: _onOutcomeChanged,
                    ),

                  Expanded(
                    child: _buildContent(context, state, widget.shrinkWrap),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    ActivityState state,
    bool shrinkWrap,
  ) {
    final colors = context.appColors;
    final typo = context.appTypography;
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: colors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: colors.error, width: 1),
                ),
                padding: const EdgeInsets.all(24),
                child: Icon(Icons.cloud_off, size: 30, color: colors.error),
              ),
              const SizedBox(height: 12),
              Text(
                "Couldn't load log records",
                textAlign: TextAlign.center,
                style: typo.titleLarge.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                state.errorMessage ?? "fg",
                textAlign: TextAlign.center,
                style: typo.caption.copyWith(fontSize: 14),
              ),
              const SizedBox(height: 16),
              AppButton(
                text: "Retry",
                color: colors.primary,
                onPressed: () {
                  context.read<ActivityBloc>().add(
                    const ActivityEvent.refreshRequested(),
                  );
                },
                width: double.infinity - 46,
                icon: const Icon(Icons.refresh, size: 18, color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    if (state.records.isEmpty) {
      final isLogs = widget.isLogsMode;
      final isFiltered =
          state.searchQuery.isNotEmpty ||
          (!isLogs &&
              (state.selectedOutcome != 'all' ||
                  state.selectedTimeWindowMillis != null));

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isLogs ? Icons.block : Icons.history,
                size: 56,
                color: Colors.grey,
              ),
              const SizedBox(height: 12),
              Text(
                isFiltered
                    ? 'No records matching filters'
                    : (isLogs
                          ? 'Nothing blocked yet'
                          : 'Live activity is paused'),
                style: typo.titleLarge.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isFiltered
                    ? 'Try adjusting your search keywords.'
                    : (isLogs
                          ? "When apps try to reach trackers or ads,\nthey'll show up here."
                          : 'Enable the firewall tunnel to record DNS requests.'),
                textAlign: TextAlign.center,
                style: typo.caption.copyWith(fontSize: 14),
              ),
              if (isFiltered) ...[
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _clearFilters,
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith<Color?>((
                      states,
                    ) {
                      if (states.contains(WidgetState.focused)) {
                        return colors.primary;
                      }
                      return Colors.transparent;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith<Color?>((
                      states,
                    ) {
                      if (states.contains(WidgetState.focused)) {
                        return colors.white;
                      }
                      return colors.primary;
                    }),
                    side: WidgetStateProperty.resolveWith<BorderSide?>((
                      states,
                    ) {
                      if (states.contains(WidgetState.focused)) {
                        return BorderSide(color: colors.primary, width: 2);
                      }
                      return BorderSide(color: colors.primary, width: 2);
                    }),
                    padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    ),
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                    ),
                  ),
                  child: const Text('Clear Filters'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => context.read<ActivityBloc>().add(
        const ActivityEvent.refreshRequested(),
      ),
      child: Scrollbar(
        controller: _scrollController,
        thickness: 8.0,
        thumbVisibility: true,
        trackVisibility: true,
        interactive: true,
        child: ListView.separated(
          controller: _scrollController,
          shrinkWrap: shrinkWrap,
          itemCount: state.records.length + (state.hasMore ? 1 : 0),
          separatorBuilder: (context, index) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            if (index < 0) {
              return const SizedBox.shrink();
            }

            if (index >= state.records.length) {
              if (state.hasMore && index == state.records.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              return const SizedBox.shrink();
            }

            final record = state.records[index];
            final isBlocked = state.isDomainBlocked(record.domain, record);
            final isPending = state.pendingDomainToggles.contains(
              AuraDomainEvaluator.normalizeDomain(record.domain),
            );

            return _ActivityRecordCard(
              key: ValueKey(record.id),
              record: record,
              isBlocked: isBlocked,
              isPending: isPending,
              onToggle: () {
                if (isPending) return;
                context.read<ActivityBloc>().add(
                  ActivityEvent.domainBlockToggled(
                    domain: record.domain,
                    isBlocked: !isBlocked,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ActivityRecordCard extends StatefulWidget {
  final DnsActivityRecord record;
  final bool isBlocked;
  final bool isPending;
  final VoidCallback onToggle;

  const _ActivityRecordCard({
    super.key,
    required this.record,
    required this.isBlocked,
    required this.isPending,
    required this.onToggle,
  });

  @override
  State<_ActivityRecordCard> createState() => _ActivityRecordCardState();
}

class _ActivityRecordCardState extends State<_ActivityRecordCard>
    with AutomaticKeepAliveClientMixin {
  late final FocusNode _focusNode;
  bool _isFocused = false;

  @override
  bool get wantKeepAlive => _isFocused;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(
      debugLabel: 'ActivityRecordCard_${widget.record.id}',
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange(bool hasFocus) {
    if (_isFocused != hasFocus) {
      setState(() {
        _isFocused = hasFocus;
      });
      updateKeepAlive();
      if (hasFocus) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
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
        widget.onToggle();
      }
      return KeyEventResult.handled;
    }

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (key == LogicalKeyboardKey.arrowUp) {
        final moved = node.focusInDirection(TraversalDirection.up);
        if (moved) return KeyEventResult.handled;
        final prev = node.previousFocus();
        return prev ? KeyEventResult.handled : KeyEventResult.ignored;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isTv = PlatformChecker.isAndroidTV;
    final colors = context.appColors;
    final typo = context.appTypography;
    final record = widget.record;

    Widget cardContent = Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      margin: EdgeInsets.symmetric(horizontal: isTv && _isFocused ? 20 : 16),
      decoration: BoxDecoration(
        color: isTv && _isFocused ? colors.surfaceRaised : colors.segmentBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Row(
        spacing: 8,
        children: [
          NameAvatar(name: record.domain, radius: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        record.domain,
                        style: typo.titleMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(" • ${record.queryType}"),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      '${!widget.isBlocked ? "Allowed" : "Blocked"} • ',
                      style: typo.bodySmall.copyWith(
                        color: !widget.isBlocked
                            ? colors.primary
                            : colors.error,
                        fontSize: 11,
                      ),
                    ),
                    if (record.matchedSource != 'none') ...[
                      Text(
                        '${record.matchedSource} • ',
                        style: typo.bodySmall.copyWith(
                          color: colors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    Text(
                      formatTimestamp(record.dateTime, locale: "en_short"),
                      style: typo.bodySmall.copyWith(
                        color: colors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                if (record.matchedCategories.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: record.matchedCategories.map((cat) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          cat,
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.blue,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          ExcludeFocus(
            excluding: isTv,
            child: IgnorePointer(
              ignoring: isTv,
              child: Switch(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                value: widget.isBlocked,
                onChanged: widget.isPending ? null : (_) => widget.onToggle(),
                inactiveThumbColor: colors.textTertiary,
                inactiveTrackColor: colors.trackOff,
              ),
            ),
          ),
        ],
      ),
    );

    if (isTv) {
      cardContent = Focus(
        focusNode: _focusNode,
        canRequestFocus: true,
        onFocusChange: _handleFocusChange,
        onKeyEvent: _handleKeyEvent,
        child: GestureDetector(onTap: widget.onToggle, child: cardContent),
      );
    }

    return cardContent;
  }
}

class _ActivityFilterBar extends StatefulWidget {
  final String selectedOutcome;
  final ValueChanged<String> onOutcomeChanged;

  const _ActivityFilterBar({
    super.key,
    required this.selectedOutcome,
    required this.onOutcomeChanged,
  });

  @override
  State<_ActivityFilterBar> createState() => _ActivityFilterBarState();
}

class _ActivityFilterBarState extends State<_ActivityFilterBar> {
  late final FocusNode _focusNode;
  bool _isFocused = false;
  late int _focusedIndex;

  static const _options = [
    (outcome: 'all', label: 'All', key: ValueKey('activity_filter_all')),
    (
      outcome: 'allowed',
      label: 'Allowed',
      key: ValueKey('activity_filter_allowed'),
    ),
    (
      outcome: 'blocked',
      label: 'Blocked',
      key: ValueKey('activity_filter_blocked'),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _focusedIndex = _indexForOutcome(widget.selectedOutcome);
    _focusNode = FocusNode(debugLabel: 'ActivityOutcomeFilter');
  }

  @override
  void didUpdateWidget(_ActivityFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isFocused && oldWidget.selectedOutcome != widget.selectedOutcome) {
      _focusedIndex = _indexForOutcome(widget.selectedOutcome);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  int _indexForOutcome(String outcome) {
    final idx = _options.indexWhere((o) => o.outcome == outcome);
    return idx >= 0 ? idx : 0;
  }

  void _handleFocusChange(bool hasFocus) {
    if (_isFocused != hasFocus) {
      setState(() {
        _isFocused = hasFocus;
        if (hasFocus) {
          _focusedIndex = _indexForOutcome(widget.selectedOutcome);
        }
      });
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
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
        widget.onOutcomeChanged(_options[_focusedIndex].outcome);
      }
      return KeyEventResult.handled;
    }

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (key == LogicalKeyboardKey.arrowRight) {
        if (_focusedIndex < _options.length - 1) {
          setState(() {
            _focusedIndex++;
          });
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        if (_focusedIndex > 0) {
          setState(() {
            _focusedIndex--;
          });
        }
        return KeyEventResult.handled;
      }
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
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isTv = PlatformChecker.isAndroidTV;

    Widget content = Container(
      padding: const EdgeInsets.all(4),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: colors.segmentBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Row(
        spacing: 6,
        children: [
          for (var i = 0; i < _options.length; i++)
            FilterWidget(
              key: _options[i].key,
              onTap: () {
                if (isTv) {
                  _focusNode.requestFocus();
                  setState(() {
                    _focusedIndex = i;
                  });
                }
                widget.onOutcomeChanged(_options[i].outcome);
              },
              isSelected: widget.selectedOutcome == _options[i].outcome,
              isFocused: isTv && _isFocused && _focusedIndex == i,
              label: _options[i].label,
            ),
        ],
      ),
    );

    if (isTv) {
      content = Focus(
        focusNode: _focusNode,
        canRequestFocus: true,
        onFocusChange: _handleFocusChange,
        onKeyEvent: _handleKeyEvent,
        child: content,
      );
    }

    return content;
  }
}

class FilterWidget extends StatelessWidget {
  final bool isSelected;
  final bool isFocused;
  final void Function()? onTap;
  final String label;

  const FilterWidget({
    super.key,
    required this.onTap,
    required this.isSelected,
    required this.label,
    this.isFocused = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typo = context.appTypography;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isFocused
                ? colors.surfaceRaised
                : (isSelected ? colors.surfaceRaised : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
            border: isFocused
                ? Border.all(color: colors.primary, width: 2)
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: typo.titleMedium.copyWith(
              color: isFocused
                  ? colors.primary
                  : (isSelected ? colors.textPrimary : colors.textSecondary),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
