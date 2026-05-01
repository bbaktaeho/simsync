import 'package:flutter/material.dart';

/// Custom color extension attached to ThemeData.
/// Access via `Theme.of(context).extension<AppColorsExtension>()!`
class AppColorsExtension extends ThemeExtension<AppColorsExtension> {
  final Color scaffold;
  final Color surface;
  final Color surfaceLight;
  final Color surfaceHover;
  final Color border;
  final Color borderSubtle;
  final Color accent;
  final Color accentMuted;
  final Color accentSubtle;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textOnAccent;
  final Color error;
  final Color success;
  final Color calendarToday;
  final Color calendarDot;
  final Color calendarSelected;
  final Color localAccent;

  const AppColorsExtension({
    required this.scaffold,
    required this.surface,
    required this.surfaceLight,
    required this.surfaceHover,
    required this.border,
    required this.borderSubtle,
    required this.accent,
    required this.accentMuted,
    required this.accentSubtle,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textOnAccent,
    required this.error,
    required this.success,
    required this.calendarToday,
    required this.calendarDot,
    required this.calendarSelected,
    required this.localAccent,
  });

  /// Light theme palette.
  static const light = AppColorsExtension(
    scaffold: Color(0xFFF6F8FA),
    surface: Color(0xFFFFFFFF),
    surfaceLight: Color(0xFFF0F2F5),
    surfaceHover: Color(0xFFE8EBF0),
    border: Color(0xFFD8DEE4),
    borderSubtle: Color(0xFFE1E7ED),
    accent: Color(0xFF9C7E56),
    accentMuted: Color(0x339C7E56),
    accentSubtle: Color(0x149C7E56),
    textPrimary: Color(0xFF1F2328),
    textSecondary: Color(0xFF656D76),
    textMuted: Color(0xFF9CA3AF),
    textOnAccent: Color(0xFFFFFFFF),
    error: Color(0xFFCF222E),
    success: Color(0xFF1A7F37),
    calendarToday: Color(0xFF9C7E56),
    calendarDot: Color(0xFF9C7E56),
    calendarSelected: Color(0xFFE8EBF0),
    localAccent: Color(0xFFB45309),
  );

  @override
  AppColorsExtension copyWith({Color? accent, Color? localAccent}) {
    return AppColorsExtension(
      scaffold: scaffold,
      surface: surface,
      surfaceLight: surfaceLight,
      surfaceHover: surfaceHover,
      border: border,
      borderSubtle: borderSubtle,
      accent: accent ?? this.accent,
      accentMuted: accentMuted,
      accentSubtle: accentSubtle,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      textMuted: textMuted,
      textOnAccent: textOnAccent,
      error: error,
      success: success,
      calendarToday: calendarToday,
      calendarDot: calendarDot,
      calendarSelected: calendarSelected,
      localAccent: localAccent ?? this.localAccent,
    );
  }

  @override
  AppColorsExtension lerp(covariant ThemeExtension<AppColorsExtension>? other, double t) {
    if (other is! AppColorsExtension) return this;
    return AppColorsExtension(
      scaffold: Color.lerp(scaffold, other.scaffold, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceLight: Color.lerp(surfaceLight, other.surfaceLight, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentMuted: Color.lerp(accentMuted, other.accentMuted, t)!,
      accentSubtle: Color.lerp(accentSubtle, other.accentSubtle, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textOnAccent: Color.lerp(textOnAccent, other.textOnAccent, t)!,
      error: Color.lerp(error, other.error, t)!,
      success: Color.lerp(success, other.success, t)!,
      calendarToday: Color.lerp(calendarToday, other.calendarToday, t)!,
      calendarDot: Color.lerp(calendarDot, other.calendarDot, t)!,
      calendarSelected: Color.lerp(calendarSelected, other.calendarSelected, t)!,
      localAccent: Color.lerp(localAccent, other.localAccent, t)!,
    );
  }
}

/// Shortcut to access app colors from BuildContext.
extension AppColorsX on BuildContext {
  AppColorsExtension get colors =>
      Theme.of(this).extension<AppColorsExtension>()!;
}
