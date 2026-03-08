import 'package:flutter/material.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const SimSyncApp());
}

class SimSyncApp extends StatelessWidget {
  const SimSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SimSync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF0E639C),
          surface: Color(0xFF252526),
          onSurface: Color(0xFFD4D4D4),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF252526),
          elevation: 0,
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF252526),
        ),
        dividerColor: const Color(0xFF3C3C3C),
      ),
      home: const LoginScreen(),
    );
  }
}
