import 'dart:async';
import 'package:flutter/material.dart';
import 'package:theja_aura/core/services/aura_activity_service.dart';

class AuraActivityScreen extends StatefulWidget {
  final AuraActivityService? activityService;

  const AuraActivityScreen({
    super.key,
    this.activityService,
  });

  @override
  State<AuraActivityScreen> createState() => _AuraActivityScreenState();
}

class _AuraActivityScreenState extends State<AuraActivityScreen> {
  late final AuraActivityService _service;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  List<DnsActivityRecord> _records = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  String? _errorMessage;

  int? _nextCursorTimestamp;
  int? _nextCursorId;

  // Active filters
  String _selectedOutcome = 'all'; // all, blocked, allowed, failed
  int? _selectedTimeWindowMillis; // null (all), 86400000 (24h), 604800000 (7d), 2592000000 (30d)
  String _searchQuery = '';
  Timer? _searchDebounceTimer;

  // Request race-condition guard
  int _activeRequestId = 0;

  @override
  void initState() {
    super.initState();
    _service = widget.activityService ?? AuraActivityService();
    _scrollController.addListener(_onScroll);
    _loadInitialPage();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll >= maxScroll - 200 && _hasMore && !_isLoading && !_isLoadingMore) {
      _loadMore();
    }
  }

  int? get _startTimeForFilter {
    if (_selectedTimeWindowMillis == null) return null;
    return DateTime.now().toUtc().millisecondsSinceEpoch - _selectedTimeWindowMillis!;
  }

  Future<void> _loadInitialPage() async {
    final int requestId = ++_activeRequestId;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _service.getActivity(
        limit: 25,
        outcome: _selectedOutcome == 'all' ? null : _selectedOutcome,
        searchDomain: _searchQuery.isEmpty ? null : _searchQuery,
        startTime: _startTimeForFilter,
      );

      if (!mounted || requestId != _activeRequestId) return;

      setState(() {
        _records = result.records;
        _hasMore = result.hasMore;
        _nextCursorTimestamp = result.nextCursorTimestamp;
        _nextCursorId = result.nextCursorId;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || requestId != _activeRequestId) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load activity: $e';
      });
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoadingMore || _nextCursorTimestamp == null || _nextCursorId == null) {
      return;
    }

    final int requestId = _activeRequestId;
    setState(() {
      _isLoadingMore = true;
    });

    try {
      final result = await _service.getActivity(
        limit: 25,
        cursorTimestamp: _nextCursorTimestamp,
        cursorId: _nextCursorId,
        outcome: _selectedOutcome == 'all' ? null : _selectedOutcome,
        searchDomain: _searchQuery.isEmpty ? null : _searchQuery,
        startTime: _startTimeForFilter,
      );

      if (!mounted || requestId != _activeRequestId) return;

      setState(() {
        _records.addAll(result.records);
        _hasMore = result.hasMore;
        _nextCursorTimestamp = result.nextCursorTimestamp;
        _nextCursorId = result.nextCursorId;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted || requestId != _activeRequestId) return;
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  void _onOutcomeChanged(String outcome) {
    if (_selectedOutcome == outcome) return;
    setState(() {
      _selectedOutcome = outcome;
    });
    _loadInitialPage();
  }

  void _onTimeWindowChanged(int? windowMillis) {
    if (_selectedTimeWindowMillis == windowMillis) return;
    setState(() {
      _selectedTimeWindowMillis = windowMillis;
    });
    _loadInitialPage();
  }

  void _onSearchChanged(String text) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      final trimmed = text.trim();
      if (_searchQuery != trimmed) {
        setState(() {
          _searchQuery = trimmed;
        });
        _loadInitialPage();
      }
    });
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _selectedOutcome = 'all';
      _selectedTimeWindowMillis = null;
      _searchQuery = '';
    });
    _loadInitialPage();
  }

  Color _getOutcomeColor(String outcome) {
    switch (outcome.toLowerCase()) {
      case 'blocked':
        return Colors.redAccent;
      case 'allowed':
        return Colors.greenAccent;
      case 'failed':
        return Colors.orangeAccent;
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
    final now = DateTime.now();
    final difference = now.difference(dt);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      final month = dt.month.toString().padLeft(2, '0');
      final day = dt.day.toString().padLeft(2, '0');
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$month/$day $hour:$minute';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DNS Activity Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadInitialPage,
            tooltip: 'Refresh Activity',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search domains (e.g. google.com)...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _onSearchChanged,
            ),
          ),

          // Filter Chips (Outcome & Time Range)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                // Outcome filters
                ChoiceChip(
                  label: const Text('All'),
                  selected: _selectedOutcome == 'all',
                  onSelected: (_) => _onOutcomeChanged('all'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Blocked'),
                  selected: _selectedOutcome == 'blocked',
                  selectedColor: Colors.red.shade900,
                  onSelected: (_) => _onOutcomeChanged('blocked'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Allowed'),
                  selected: _selectedOutcome == 'allowed',
                  selectedColor: Colors.green.shade900,
                  onSelected: (_) => _onOutcomeChanged('allowed'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Failed'),
                  selected: _selectedOutcome == 'failed',
                  selectedColor: Colors.orange.shade900,
                  onSelected: (_) => _onOutcomeChanged('failed'),
                ),
                const SizedBox(width: 16),
                const VerticalDivider(width: 1),
                const SizedBox(width: 16),

                // Time window filters
                FilterChip(
                  label: const Text('Last 24h'),
                  selected: _selectedTimeWindowMillis == 86400000,
                  onSelected: (sel) => _onTimeWindowChanged(sel ? 86400000 : null),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Last 7d'),
                  selected: _selectedTimeWindowMillis == 604800000,
                  onSelected: (sel) => _onTimeWindowChanged(sel ? 604800000 : null),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Last 30d'),
                  selected: _selectedTimeWindowMillis == 2592000000,
                  onSelected: (sel) => _onTimeWindowChanged(sel ? 2592000000 : null),
                ),
              ],
            ),
          ),

          const Divider(height: 8),

          // Content Area
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadInitialPage,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_records.isEmpty) {
      final isFiltered = _selectedOutcome != 'all' ||
          _selectedTimeWindowMillis != null ||
          _searchQuery.isNotEmpty;

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.history, size: 56, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                isFiltered ? 'No activity matching filters' : 'No DNS activity recorded yet',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                isFiltered
                    ? 'Try adjusting your search keywords or filter settings.'
                    : 'Enable the firewall tunnel to record DNS requests.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
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
      onRefresh: _loadInitialPage,
      child: ListView.separated(
        controller: _scrollController,
        itemCount: _records.length + (_hasMore ? 1 : 0),
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == _records.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }

          final record = _records[index];
          final outcomeColor = _getOutcomeColor(record.outcome);
          final outcomeIcon = _getOutcomeIcon(record.outcome);

          return ListTile(
            leading: Icon(outcomeIcon, color: outcomeColor),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    record.domain,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade800,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    record.queryType,
                    style: TextStyle(
                      color: Colors.grey.shade300,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      record.outcome.toUpperCase(),
                      style: TextStyle(
                        color: outcomeColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTimestamp(record.dateTime),
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                    ),
                    if (record.matchedSource != 'none') ...[
                      const SizedBox(width: 8),
                      Text(
                        '• ${record.matchedSource}',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                      ),
                    ],
                  ],
                ),
                if (record.matchedCategories.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: record.matchedCategories.map((cat) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.shade900,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          cat,
                          style: const TextStyle(fontSize: 9, color: Colors.white70),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                if (record.reason != null && record.reason!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    record.reason!,
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
