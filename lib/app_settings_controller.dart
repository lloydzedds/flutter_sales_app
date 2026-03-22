import 'package:flutter/material.dart';

import 'database/database_helper.dart';

class AppSettingsController extends ChangeNotifier {
  AppSettingsController._();

  static final AppSettingsController instance = AppSettingsController._();

  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  Future<void> load() async {
    final savedMode = await DatabaseHelper.instance.getAppSetting('theme_mode');
    _themeMode = _themeModeFromString(savedMode);
  }

  Future<void> reload() async {
    await load();
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await DatabaseHelper.instance.saveAppSetting(
      'theme_mode',
      _themeModeToString(mode),
    );
    notifyListeners();
  }

  String themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'System Default';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }

  ThemeMode _themeModeFromString(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
