import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:theja_aura/core/theme/app_colors.dart';
import 'package:theja_aura/core/theme/app_theme.dart';
import 'package:theja_aura/core/theme/app_typography.dart';
import 'package:theja_aura/core/utils/app_button.dart';
import 'package:theja_aura/core/utils/app_utils.dart';
import 'package:theja_aura/features/timeago/timeago.dart';

import 'package:theja_aura/core/services/aura_domain_evaluator.dart';

import '../bloc/activity_bloc.dart';

class ActivityPage extends StatefulWidget {
  final bool isLogsMode;

  const ActivityPage({super.key, this.isLogsMode = false});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    context.read<ActivityBloc>().add(
      ActivityEvent.started(isLogsMode: widget.isLogsMode),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
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
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll >= maxScroll - 200 &&
        bloc.state.hasMore &&
        !bloc.state.isLoading &&
        !bloc.state.isLoadingMore) {
      bloc.add(const ActivityEvent.loadMoreRequested());
    }
  }

  void _onOutcomeChanged(String outcome) {
    if (widget.isLogsMode) return;
    context.read<ActivityBloc>().add(
      ActivityEvent.outcomeFilterChanged(outcome),
    );
  }

  void _onTimeWindowChanged(int? windowMillis) {
    context.read<ActivityBloc>().add(
      ActivityEvent.timeWindowFilterChanged(windowMillis),
    );
  }

  void _clearFilters() {
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

  Color _getOutcomeColor(String outcome) {
    switch (outcome.toLowerCase()) {
      case 'blocked':
        return Colors.redAccent;
      case 'allowed':
        return Colors.greenAccent;
      case 'failed':
        return Colors.amberAccent;
      default:
        return Colors.grey;
    }
  }

  IconData _getOutcomeIcon(String outcome) {
    switch (outcome.toLowerCase()) {
      case 'blocked':
        return Icons.block;
      case 'allowed':
        return Icons.check_circle_outline;
      case 'failed':
        return Icons.error_outline;
      default:
        return Icons.help_outline;
    }
  }

  String _formatTimestamp(DateTime dt) {
    final year = dt.year.toString().padLeft(4, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final second = dt.second.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute:$second';
  }

  @override
  Widget build(BuildContext context) {
    final isLogs = widget.isLogsMode;
    final screenTitle = isLogs ? 'Logs' : 'Live Activity';
    final colors = context.appColors;
    final typo = context.appTypography;

    return BlocConsumer<ActivityBloc, ActivityState>(
      listener: (context, state) {
        if (state.actionError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.actionError!),
              backgroundColor: colors.error,
            ),
          );
          context.read<ActivityBloc>().add(
            const ActivityEvent.actionErrorDismissed(),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: Text(screenTitle),
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
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: isLogs
                          ? 'Search blocked domains...'
                          : 'Search captured domains...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: state.searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                context.read<ActivityBloc>().add(
                                  const ActivityEvent.searchQueryChanged(''),
                                );
                              },
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
                Container(
                  padding: .all(4),
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.segmentBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.border, width: 1),
                  ),
                  child: Row(
                    spacing: 6,
                    children: [
                      FilterWidget(
                        onTap: () => _onOutcomeChanged('all'),
                        isSelected: state.selectedOutcome == 'all',
                        label: 'All',
                      ),

                      FilterWidget(
                        onTap: () => _onOutcomeChanged('allowed'),
                        isSelected: state.selectedOutcome == 'allowed',
                        label: 'Allowed',
                      ),

                      FilterWidget(
                        onTap: () => _onOutcomeChanged('blocked'),
                        isSelected: state.selectedOutcome == 'blocked',
                        label: 'Blocked',
                      ),
                    ],
                  ),
                ),

              Expanded(child: _buildContent(context, state)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, ActivityState state) {
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
      child: ListView.separated(
        controller: _scrollController,
        itemCount: state.records.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (context, index) => SizedBox(height: 6),
        itemBuilder: (context, index) {
          if (index == state.records.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }

          final record = state.records[index];

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            margin: .symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: colors.segmentBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border, width: 1),
            ),
            child: Row(
              spacing: 8,
              children: [
                NameAvatar(name: record.domain, radius: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: [
                      Text(
                        '${record.domain} • ${record.queryType}',
                        style: typo.titleMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        children: [
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
                            formatTimestamp(record.dateTime, locale: "en"),
                            style: typo.bodySmall.copyWith(
                              color: colors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Switch(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  value: state.isDomainBlocked(record.domain, record),
                  onChanged:
                      state.pendingDomainToggles.contains(
                        AuraDomainEvaluator.normalizeDomain(record.domain),
                      )
                      ? null
                      : (value) {
                          context.read<ActivityBloc>().add(
                            ActivityEvent.domainBlockToggled(
                              domain: record.domain,
                              isBlocked: value,
                            ),
                          );
                        },
                  inactiveThumbColor: colors.textTertiary,
                  inactiveTrackColor: colors.trackOff,
                ),
              ],
            ),
          );
          // return ListTile(
          //   leading: const Icon(
          //     Icons.block,
          //     color: Colors.redAccent,
          //     size: 22,
          //   ),
          //   title: Text(
          //     record.domain,
          //     style: const TextStyle(
          //       fontWeight: FontWeight.w600,
          //       fontSize: 14,
          //     ),
          //     overflow: TextOverflow.ellipsis,
          //   ),
          //   subtitle: Text(
          //     _formatTimestamp(record.dateTime),
          //     style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
          //   ),
          //   trailing: Container(
          //     padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          //     decoration: BoxDecoration(
          //       color: Colors.red.shade900.withValues(alpha: 0.3),
          //       borderRadius: BorderRadius.circular(4),
          //     ),
          //     child: const Text(
          //       'BLOCKED',
          //       style: TextStyle(
          //         color: Colors.redAccent,
          //         fontSize: 10,
          //         fontWeight: FontWeight.bold,
          //       ),
          //     ),
          //   ),
          // );

          // // Live Activity mode: Domain, Timestamp, Outcome, QueryType, Categories
          // final outcomeColor = _getOutcomeColor(record.outcome);
          // final outcomeIcon = _getOutcomeIcon(record.outcome);

          // return ListTile(
          //   leading: Icon(outcomeIcon, color: outcomeColor),
          //   title: Row(
          //     children: [
          //       Expanded(
          //         child: Text(
          //           record.domain,
          //           style: const TextStyle(
          //             fontWeight: FontWeight.w600,
          //             fontSize: 14,
          //           ),
          //           overflow: TextOverflow.ellipsis,
          //         ),
          //       ),
          //       Container(
          //         padding: const EdgeInsets.symmetric(
          //           horizontal: 6,
          //           vertical: 2,
          //         ),
          //         decoration: BoxDecoration(
          //           color: Colors.grey.shade800,
          //           borderRadius: BorderRadius.circular(4),
          //         ),
          //         child: Text(
          //           record.queryType,
          //           style: TextStyle(
          //             color: Colors.grey.shade300,
          //             fontSize: 10,
          //             fontWeight: FontWeight.bold,
          //           ),
          //         ),
          //       ),
          //     ],
          //   ),
          //   subtitle: Column(
          //     crossAxisAlignment: CrossAxisAlignment.start,
          //     children: [
          //       const SizedBox(height: 4),
          //       Row(
          //         children: [
          //           Text(
          //             record.outcome.toUpperCase(),
          //             style: TextStyle(
          //               color: outcomeColor,
          //               fontWeight: FontWeight.bold,
          //               fontSize: 11,
          //             ),
          //           ),
          //           const SizedBox(width: 8),
          //           Text(
          //             _formatTimestamp(record.dateTime),
          //             style: TextStyle(
          //               color: Colors.grey.shade400,
          //               fontSize: 11,
          //             ),
          //           ),
          //           if (record.matchedSource != 'none') ...[
          //             const SizedBox(width: 8),
          //             Text(
          //               '• ${record.matchedSource}',
          //               style: TextStyle(
          //                 color: Colors.grey.shade400,
          //                 fontSize: 11,
          //               ),
          //             ),
          //           ],
          //         ],
          //       ),
          //       if (record.matchedCategories.isNotEmpty) ...[
          //         const SizedBox(height: 4),
          //         Wrap(
          //           spacing: 4,
          //           runSpacing: 2,
          //           children: record.matchedCategories.map((cat) {
          //             return Container(
          //               padding: const EdgeInsets.symmetric(
          //                 horizontal: 6,
          //                 vertical: 1,
          //               ),
          //               decoration: BoxDecoration(
          //                 color: Colors.deepPurple.shade900,
          //                 borderRadius: BorderRadius.circular(10),
          //               ),
          //               child: Text(
          //                 cat,
          //                 style: const TextStyle(
          //                   fontSize: 9,
          //                   color: Colors.white70,
          //                 ),
          //               ),
          //             );
          //           }).toList(),
          //         ),
          //       ],
          //       if (record.reason != null && record.reason!.isNotEmpty) ...[
          //         const SizedBox(height: 2),
          //         Text(
          //           record.reason!,
          //           style: TextStyle(
          //             color: Colors.grey.shade400,
          //             fontSize: 10,
          //             fontStyle: FontStyle.italic,
          //           ),
          //           overflow: TextOverflow.ellipsis,
          //         ),
          //       ],
          //     ],
          //   ),
          // );
        },
      ),
    );
  }
}

class FilterWidget extends StatelessWidget {
  const new({
    super.key,
    required this.onTap,
    required this.isSelected,
    required this.label,
  });

  final bool isSelected;
  final void Function()? onTap;
  final String label;

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
            color: isSelected ? colors.surfaceRaised : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: !isSelected
                ? []
                : [
                    BoxShadow(
                      color: colors.shadowSegment,
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: typo.titleMedium.copyWith(
              color: isSelected ? colors.textPrimary : colors.textSecondary,
              fontWeight: .w700,
            ),
          ),
        ),
      ),
    );
  }
}
