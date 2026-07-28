// lib/theme_provider.dart
// this class manage the app theme. light, dark, or just follow the phone setting.
// importente kaayo -- without this, the whole app stuck in one theme forever.
import 'package:flutter/material.dart';

// ThemeProvider -- listens to theme changes and tells the whole app to rebuild.
// extends ChangeNotifier so widgets can watch it and react when theme switch happen.
class ThemeProvider extends ChangeNotifier {
  // Default to system theme! let the phone decide, bahala na what it picks
  ThemeMode _themeMode = ThemeMode.system;

  // getter so other widgets can read the current theme mode without touching the private field
  ThemeMode get themeMode => _themeMode;

  // update the theme mode and notify all listeners to rebuild.
  // call this when user pick light, dark, or system in settings.
  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners(); // Tells the whole app to rebuild with the new theme -- very importente, ayaw remove this
  }
}