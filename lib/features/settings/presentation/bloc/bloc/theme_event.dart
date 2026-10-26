part of 'theme_bloc.dart';

@freezed
class ThemeEvent with _$ThemeEvent {
  const factory ThemeEvent.load() = Load;
  const factory ThemeEvent.change({required ThemeMode themeMode}) = Change;
}
