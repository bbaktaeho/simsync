import 'package:flutter/material.dart';

import 'screens/document_screen.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const SimSyncApp());
}

class SimSyncApp extends StatefulWidget {
  const SimSyncApp({super.key});

  @override
  State<SimSyncApp> createState() => SimSyncAppState();

  /// Allow descendants to toggle theme mode.
  static SimSyncAppState of(BuildContext context) =>
      context.findAncestorStateOfType<SimSyncAppState>()!;
}

class SimSyncAppState extends State<SimSyncApp> {
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  void toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SimSync',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: _themeMode,
      home: const _AppShell(),
    );
  }
}

/// Root shell that manages auth state (login ↔ document screen).
class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  bool _isLoggedIn = false;

  @override
  Widget build(BuildContext context) {
    if (_isLoggedIn) {
      return DocumentScreen(
        onLogout: () => setState(() => _isLoggedIn = false),
      );
    }
    return LoginScreen(
      onLoginSuccess: () => setState(() => _isLoggedIn = true),
    );
  }
}
