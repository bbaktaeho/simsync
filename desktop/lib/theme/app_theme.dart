import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_dimensions.dart';

ThemeData buildLightTheme() =>
    _buildTheme(AppColorsExtension.light, Brightness.light);

ThemeData buildDarkTheme() =>
    _buildTheme(AppColorsExtension.dark, Brightness.dark);

ThemeData _buildTheme(AppColorsExtension c, Brightness brightness) {
  final base =
      brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light();
  final baseTextTheme = GoogleFonts.interTextTheme(base.textTheme);

  // TextTheme mapped from DESIGN.md §3 (16-role hierarchy → 15 Flutter slots).
  // Letter-spacing scales with font size; line-height tightens at display sizes.
  final textTheme = baseTextTheme.copyWith(
    displayLarge: baseTextTheme.displayLarge?.copyWith(
      color: c.textPrimary, fontSize: 64, fontWeight: FontWeight.w700,
      height: 1.00, letterSpacing: -2.125,
    ),
    displayMedium: baseTextTheme.displayMedium?.copyWith(
      color: c.textPrimary, fontSize: 54, fontWeight: FontWeight.w700,
      height: 1.04, letterSpacing: -1.875,
    ),
    displaySmall: baseTextTheme.displaySmall?.copyWith(
      color: c.textPrimary, fontSize: 48, fontWeight: FontWeight.w700,
      height: 1.00, letterSpacing: -1.5,
    ),
    headlineLarge: baseTextTheme.headlineLarge?.copyWith(
      color: c.textPrimary, fontSize: 40, fontWeight: FontWeight.w700,
      height: 1.50,
    ),
    headlineMedium: baseTextTheme.headlineMedium?.copyWith(
      color: c.textPrimary, fontSize: 26, fontWeight: FontWeight.w700,
      height: 1.23, letterSpacing: -0.625,
    ),
    headlineSmall: baseTextTheme.headlineSmall?.copyWith(
      color: c.textPrimary, fontSize: 22, fontWeight: FontWeight.w700,
      height: 1.27, letterSpacing: -0.25,
    ),
    titleLarge: baseTextTheme.titleLarge?.copyWith(
      color: c.textPrimary, fontSize: 20, fontWeight: FontWeight.w600,
      height: 1.40, letterSpacing: -0.125,
    ),
    titleMedium: baseTextTheme.titleMedium?.copyWith(
      color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w600,
      height: 1.33,
    ),
    titleSmall: baseTextTheme.titleSmall?.copyWith(
      color: c.textPrimary, fontSize: 14, fontWeight: FontWeight.w500,
      height: 1.43,
    ),
    bodyLarge: baseTextTheme.bodyLarge?.copyWith(
      color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w500,
      height: 1.50,
    ),
    bodyMedium: baseTextTheme.bodyMedium?.copyWith(
      color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w400,
      height: 1.50,
    ),
    bodySmall: baseTextTheme.bodySmall?.copyWith(
      color: c.textSecondary, fontSize: 14, fontWeight: FontWeight.w400,
      height: 1.43,
    ),
    labelLarge: baseTextTheme.labelLarge?.copyWith(
      color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w600,
      height: 1.50,
    ),
    labelMedium: baseTextTheme.labelMedium?.copyWith(
      color: c.badgeText, fontSize: 12, fontWeight: FontWeight.w600,
      height: 1.33, letterSpacing: 0.125,
    ),
    labelSmall: baseTextTheme.labelSmall?.copyWith(
      color: c.textMuted, fontSize: 12, fontWeight: FontWeight.w400,
      height: 1.33, letterSpacing: 0.125,
    ),
  );

  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: c.scaffold,
    extensions: [c],
    colorScheme: ColorScheme(
      brightness: brightness,
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
    textTheme: textTheme,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
        borderSide: BorderSide(color: c.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
        borderSide: BorderSide(color: c.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
        borderSide: BorderSide(color: c.focus, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: TextStyle(color: c.textMuted, fontSize: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.textOnAccent,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
        ),
        textStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accent,
        textStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w500,
          fontSize: 14,
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
      radius: const Radius.circular(AppDimensions.radiusMicro),
      thickness: WidgetStateProperty.all(4),
    ),
  );
}
