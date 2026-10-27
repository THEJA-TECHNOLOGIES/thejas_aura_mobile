part of 'settings_bloc.dart';

@freezed
abstract class SettingsState with _$SettingsState {
  const factory SettingsState({
    @Default(ThemeMode.system) ThemeMode themeMode,
    @Default(true) bool autoRestartEnabled,
    @Default(30) int retentionPeriodDays,
    @Default(false) bool isLoading,
    @Default(false) bool isPruning,
    String? errorMessage,
  }) = _SettingsState;
}
