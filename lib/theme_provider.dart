// lib/theme_provider.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider with ChangeNotifier {
  bool _isDarkMode;

  ThemeProvider({bool isDarkMode = false}) : _isDarkMode = isDarkMode;

  bool get isDarkMode => _isDarkMode;

  void toggleThemeWithPersistence(bool isOn) async {
    _isDarkMode = isOn;
    notifyListeners();

    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', _isDarkMode);
  }
}
