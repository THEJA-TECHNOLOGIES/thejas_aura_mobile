import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

part 'theme_event.dart';
part 'theme_state.dart';
part 'theme_bloc.freezed.dart';

@injectable
class ThemeBloc extends Bloc<ThemeEvent, ThemeState> {
  final FlutterSecureStorage secureStorage;
  ThemeBloc(this.secureStorage) : super(ThemeState()) {
    on<Load>(_loadTheme);
    on<Change>(_changeTheme);
  }

  Future<void> _loadTheme(Load event, Emitter<ThemeState> emit) async {
    final themeMode = int.parse(
      await secureStorage.read(key: "theme_mode") ?? "0",
    );
    emit(state.copyWith(themeMode: ThemeMode.values[themeMode]));
  }

  Future<void> _changeTheme(Change event, Emitter<ThemeState> emit) async {
    await secureStorage.write(
      key: 'theme_mode',
      value: event.themeMode.index.toString(),
    );
    emit(state.copyWith(themeMode: event.themeMode));
  }
}
