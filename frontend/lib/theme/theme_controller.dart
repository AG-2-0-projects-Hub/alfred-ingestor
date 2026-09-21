import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ChangeNotifier {
  static const _key = 'alfred_theme_mode';
  ThemeMode _mode = ThemeMode.light;
  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == 'dark') {
      _mode = ThemeMode.dark;
    } else if (raw == 'light') {
      _mode = ThemeMode.light;
    } else {
      // No saved preference yet (first-ever load) — previously always
      // defaulted to light regardless of the host's OS/browser preference,
      // a jarring light flash for a dark-mode system before the toggle even
      // exists to fix it. This is a one-time default, not continuous
      // system-tracking — the manual toggle still fully overrides it and is
      // what gets persisted from here on.
      final platformBrightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
      _mode = platformBrightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light;
    }
    notifyListeners();
  }

  Future<void> toggle() async {
    _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _mode == ThemeMode.dark ? 'dark' : 'light');
  }
}

final themeController = ThemeController();
