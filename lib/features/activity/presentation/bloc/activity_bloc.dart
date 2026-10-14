import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:injectable/injectable.dart';

import '../../domain/repositories/i_activity_repository.dart';
import 'activity_event.dart';
import 'activity_state.dart';

export 'activity_event.dart';
export 'activity_state.dart';

@injectable
class ActivityBloc extends Bloc<ActivityEvent, ActivityState> {
  final IActivityRepository _repository;
  int _activeRequestId = 0;
  Timer? _searchDebounceTimer;

  ActivityBloc(this._repository) : super(const ActivityState()) {
    on<ActivityEvent>((event, emit) async {
      await event.when(
        started: (isLogsMode) => _onStarted(isLogsMode, emit),
        initialPageRequested: () => _onInitialPageRequested(emit),
        loadMoreRequested: () => _onLoadMoreRequested(emit),
        refreshRequested: () => _onRefreshRequested(emit),
        outcomeFilterChanged: (outcome) => _onOutcomeChanged(outcome, emit),
        timeWindowFilterChanged: (timeWindowMillis) =>
            _onTimeWindowChanged(timeWindowMillis, emit),
        searchQueryChanged: (query) => _onSearchChanged(query, emit),
        appResumed: () => _onAppResumed(emit),
      );
    });
  }

  int? get _startTimeForFilter {
    if (state.selectedTimeWindowMillis == null) return null;
    return DateTime.now().toUtc().millisecondsSinceEpoch -
        state.selectedTimeWindowMillis!;
  }

  Future<void> _onStarted(bool isLogsMode, Emitter<ActivityState> emit) async {
    emit(
      state.copyWith(
        isLogsMode: isLogsMode,
        selectedOutcome: isLogsMode ? 'blocked' : 'all',
      ),
    );
    await _fetchInitialPage(emit);
  }

  Future<void> _onInitialPageRequested(Emitter<ActivityState> emit) async {
    await _fetchInitialPage(emit);
  }

  Future<void> _fetchInitialPage(Emitter<ActivityState> emit) async {
    final int requestId = ++_activeRequestId;
    emit(state.copyWith(isLoading: true, errorMessage: null));

    final outcomeQuery = state.isLogsMode
        ? 'blocked'
        : (state.selectedOutcome == 'all' ? null : state.selectedOutcome);

    try {
      final result = await _repository.getActivity(
        limit: 25,
        outcome: outcomeQuery,
        searchDomain: state.searchQuery.isEmpty ? null : state.searchQuery,
        startTime: _startTimeForFilter,
      );

      if (requestId != _activeRequestId) return;

      emit(
        state.copyWith(
          records: result.records,
          hasMore: result.hasMore,
          nextCursorTimestamp: result.nextCursorTimestamp,
          nextCursorId: result.nextCursorId,
          isLoading: false,
        ),
      );
    } catch (e) {
      if (requestId != _activeRequestId) return;
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to load activity: $e',
        ),
      );
    }
  }

  Future<void> _onLoadMoreRequested(Emitter<ActivityState> emit) async {
    if (!state.hasMore ||
        state.isLoadingMore ||
        state.nextCursorTimestamp == null ||
        state.nextCursorId == null) {
      return;
    }

    final int requestId = _activeRequestId;
    emit(state.copyWith(isLoadingMore: true));

    final outcomeQuery = state.isLogsMode
        ? 'blocked'
        : (state.selectedOutcome == 'all' ? null : state.selectedOutcome);

    try {
      final result = await _repository.getActivity(
        limit: 25,
        cursorTimestamp: state.nextCursorTimestamp,
        cursorId: state.nextCursorId,
        outcome: outcomeQuery,
        searchDomain: state.searchQuery.isEmpty ? null : state.searchQuery,
        startTime: _startTimeForFilter,
      );

      if (requestId != _activeRequestId) return;

      emit(
        state.copyWith(
          records: [...state.records, ...result.records],
          hasMore: result.hasMore,
          nextCursorTimestamp: result.nextCursorTimestamp,
          nextCursorId: result.nextCursorId,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      if (requestId != _activeRequestId) return;
      emit(state.copyWith(isLoadingMore: false));
    }
  }

  Future<void> _onOutcomeChanged(
    String outcome,
    Emitter<ActivityState> emit,
  ) async {
    if (state.selectedOutcome == outcome) return;
    emit(state.copyWith(selectedOutcome: outcome));
    await _fetchInitialPage(emit);
  }

  Future<void> _onTimeWindowChanged(
    int? timeWindowMillis,
    Emitter<ActivityState> emit,
  ) async {
    if (state.selectedTimeWindowMillis == timeWindowMillis) return;
    emit(state.copyWith(selectedTimeWindowMillis: timeWindowMillis));
    await _fetchInitialPage(emit);
  }

  Future<void> _onSearchChanged(
    String query,
    Emitter<ActivityState> emit,
  ) async {
    final trimmed = query.trim();
    if (state.searchQuery == trimmed) return;

    emit(state.copyWith(searchQuery: trimmed));
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 350), () {
      add(const ActivityEvent.initialPageRequested());
    });
  }

  Future<void> _onRefreshRequested(Emitter<ActivityState> emit) async {
    await _fetchInitialPage(emit);
  }

  Future<void> _onAppResumed(Emitter<ActivityState> emit) async {
    await _fetchInitialPage(emit);
  }

  @override
  Future<void> close() {
    _searchDebounceTimer?.cancel();
    return super.close();
  }
}
