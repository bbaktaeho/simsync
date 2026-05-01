import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

ThemeData buildLightTheme() => _buildTheme(AppColorsExtension.light);

ThemeData _buildTheme(AppColorsExtension c) {
  final base = ThemeData.light();
  final baseTextTheme = GoogleFonts.manropeTextTheme(base.textTheme);

  return ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: c.scaffold,
    extensions: [c],
    colorScheme: ColorScheme(
      brightness: Brightness.light,
      primary: c.accent,
      onPrimary: c.textOnAccent,
      surface: c.surface,
      onSurface: c.textPrimary,
      error: c.error,
      onError: Colors.white,
      secondary: c.accent,
      onSecondary: c.textOnAccent,
      outline: c.border,
    ),
    textTheme: baseTextTheme.copyWith(
      headlineLarge: baseTextTheme.headlineLarge?.copyWith(
        color: c.textPrimary,
        fontWeight: FontWeight.w700,
        fontSize: 28,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        color: c.textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 20,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        color: c.textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        color: c.textPrimary,
        fontSize: 15,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        color: c.textSecondary,
        fontSize: 13,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(
        color: c.textMuted,
        fontSize: 12,
      ),
      labelMedium: baseTextTheme.labelMedium?.copyWith(
        color: c.textSecondary,
        fontWeight: FontWeight.w500,
        fontSize: 12,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.accent, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: TextStyle(color: c.textMuted, fontSize: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.textOnAccent,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: GoogleFonts.manrope(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accent,
        textStyle: GoogleFonts.manrope(
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
      ),
    ),
    iconTheme: IconThemeData(color: c.textSecondary, size: 20),
    dividerTheme: DividerThemeData(
      color: c.border,
      thickness: 1,
      space: 1,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(c.borderSubtle),
      radius: const Radius.circular(4),
      thickness: WidgetStateProperty.all(4),
    ),
  );
}
