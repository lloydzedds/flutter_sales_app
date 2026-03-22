import 'package:flutter/material.dart';

import 'database/database_helper.dart';

class AppSettingsController extends ChangeNotifier {
  AppSettingsController._();

  static final AppSettingsController instance = AppSettingsController._();
  static const _themeModeKey = 'theme_mode';
  static const _defaultDiscountModeKey = 'default_discount_mode';

  ThemeMode _themeMode = ThemeMode.system;
  String _defaultDiscountMode = 'manual';

  ThemeMode get themeMode => _themeMode;
  String get defaultDiscountMode => _defaultDiscountMode;

  Future<void> load() async {
    final savedThemeMode = await DatabaseHelper.instance.getAppSetting(
      _themeModeKey,
    );
    final savedDiscountMode = await DatabaseHelper.instance.getAppSetting(
      _defaultDiscountModeKey,
    );
    _themeMode = _themeModeFromString(savedThemeMode);
    _defaultDiscountMode = _discountModeFromString(savedDiscountMode);
  }

  Future<void> reload() async {
    await load();
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await DatabaseHelper.instance.saveAppSetting(
      _themeModeKey,
      _themeModeToString(mode),
    );
    notifyListeners();
  }

  Future<void> setDefaultDiscountMode(String mode) async {
    _defaultDiscountMode = _discountModeFromString(mode);
    await DatabaseHelper.instance.saveAppSetting(
      _defaultDiscountModeKey,
      _defaultDiscountMode,
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

  String discountModeLabel(String mode) {
    switch (_discountModeFromString(mode)) {
      case 'sold_price':
        return 'Sold Price';
      case 'percentage':
        return 'Percentage';
      default:
        return 'Manual';
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

  String _discountModeFromString(String? value) {
    switch (value) {
      case 'sold_price':
      case 'percentage':
      case 'manual':
        return value!;
      default:
        return 'manual';
    }
  }
}
