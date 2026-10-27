part of 'settings_bloc.dart';

@freezed
abstract class SettingsEvent with _$SettingsEvent {
  const factory SettingsEvent.load() = Load;
  const factory SettingsEvent.themeChanged(ThemeMode themeMode) = ThemeChanged;
  const factory SettingsEvent.autoRestartToggled(bool enabled) =
      AutoRestartToggled;
  const factory SettingsEvent.retentionPeriodChanged(int days) =
      RetentionPeriodChanged;
  const factory SettingsEvent.clearActivityHistory() = ClearActivityHistory;
  const factory SettingsEvent.errorMessageDismissed() = ErrorMessageDismissed;
}
