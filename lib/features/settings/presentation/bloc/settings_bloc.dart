import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';
import 'package:theja_aura/core/services/aura_tunnel_service.dart';
import 'package:theja_aura/features/activity/domain/repositories/i_activity_repository.dart';

part 'settings_event.dart';
part 'settings_state.dart';
part 'settings_bloc.freezed.dart';

@injectable
class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final FlutterSecureStorage _secureStorage;
  final AuraTunnelService _tunnelService;
  final IActivityRepository _activityRepository;

  SettingsBloc(
    this._secureStorage,
    this._tunnelService,
    this._activityRepository,
  ) : super(const SettingsState()) {
    on<Load>(_onLoad);
    on<ThemeChanged>(_onThemeChanged);
    on<AutoRestartToggled>(_onAutoRestartToggled);
    on<RetentionPeriodChanged>(_onRetentionPeriodChanged);
    on<ClearActivityHistory>(_onClearActivityHistory);
    on<ErrorMessageDismissed>(_onErrorMessageDismissed);
  }

  Future<void> _onLoad(Load event, Emitter<SettingsState> emit) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));

    ThemeMode themeMode = ThemeMode
        .values[int.parse(await _secureStorage.read(key: "theme_mode") ?? "0")];
    bool autoRestart = state.autoRestartEnabled;
    int retentionDays = state.retentionPeriodDays;

    try {
      autoRestart = await _tunnelService.isAutoRestartEnabled();
    } catch (e) {
      debugPrint('Failed to load auto-restart preference: $e');
    }

    try {
      retentionDays = await _activityRepository.getRetentionPeriodDays();
    } catch (e) {
      debugPrint('Failed to load retention period: $e');
    }

    emit(
      state.copyWith(
        isLoading: false,
        themeMode: themeMode,
        autoRestartEnabled: autoRestart,
        retentionPeriodDays: retentionDays,
      ),
    );
  }

  Future<void> _onThemeChanged(
    ThemeChanged event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(themeMode: event.themeMode));
    try {
      await _secureStorage.write(
        key: 'theme_mode',
        value: event.themeMode.index.toString(),
      );
    } catch (e) {
      debugPrint('Failed to persist theme mode: $e');
    }
  }

  Future<void> _onAutoRestartToggled(
    AutoRestartToggled event,
    Emitter<SettingsState> emit,
  ) async {
    final previous = state.autoRestartEnabled;
    emit(state.copyWith(autoRestartEnabled: event.enabled, errorMessage: null));
    try {
      await _tunnelService.setAutoRestartEnabled(event.enabled);
    } catch (e) {
      emit(
        state.copyWith(
          autoRestartEnabled: previous,
          errorMessage: 'Failed to update auto-restart preference: $e',
        ),
      );
    }
  }

  Future<void> _onRetentionPeriodChanged(
    RetentionPeriodChanged event,
    Emitter<SettingsState> emit,
  ) async {
    if (event.days != 7 && event.days != 30) return;
    final previous = state.retentionPeriodDays;
    emit(state.copyWith(retentionPeriodDays: event.days, errorMessage: null));
    try {
      await _activityRepository.setRetentionPeriodDays(event.days);
    } catch (e) {
      emit(
        state.copyWith(
          retentionPeriodDays: previous,
          errorMessage: 'Failed to update retention period: $e',
        ),
      );
    }
  }

  Future<void> _onClearActivityHistory(
    ClearActivityHistory event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(isPruning: true, errorMessage: null));
    try {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await _activityRepository.pruneRetention(cutoffUtcMillis: now);
      emit(state.copyWith(isPruning: false));
    } catch (e) {
      emit(
        state.copyWith(
          isPruning: false,
          errorMessage: 'Failed to clear activity history: $e',
        ),
      );
    }
  }

  void _onErrorMessageDismissed(
    ErrorMessageDismissed event,
    Emitter<SettingsState> emit,
  ) {
    emit(state.copyWith(errorMessage: null));
  }
}
