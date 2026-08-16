import 'package:flutter/material.dart';

/// Custom color extension attached to ThemeData.
/// Access via `Theme.of(context).extension<AppColorsExtension>()!`.
///
/// Palette mapped from DESIGN.md (Notion-inspired). Light only.
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

  /// 토/일 날짜 글자색. 평일과 구분되는 단일 주말 색.
  final Color calendarWeekend;
  final Color localAccent;
  // ── DESIGN.md additions ──
  final Color focus;
  final Color badgeText;
  final Color linkLight;
  final Color highlight;
  final Color shadowTint;

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
    required this.calendarWeekend,
    required this.localAccent,
    required this.focus,
    required this.badgeText,
    required this.linkLight,
    required this.highlight,
    required this.shadowTint,
  });

  /// Notion-inspired light palette (DESIGN.md §2).
  static const light = AppColorsExtension(
    scaffold: Color(0xFFFFFFFF), // Pure White (page bg)
    surface: Color(0xFFFFFFFF), // Card surface
    surfaceLight: Color(0xFFF6F5F4), // Warm White (alt section bg)
    surfaceHover: Color(0x0D000000), // rgba(0,0,0,0.05) — secondary bg
    border: Color(0x1A000000), // rgba(0,0,0,0.10) — whisper border
    borderSubtle: Color(0x0F000000), // rgba(0,0,0,0.06) — fainter divider
    accent: Color(0xFF0075DE), // Notion Blue (CTA, link)
    accentMuted: Color(0xFF005BAB), // Active Blue (pressed)
    accentSubtle: Color(0xFFF2F9FF), // Badge Blue Bg
    textPrimary: Color(0xF2000000), // rgba(0,0,0,0.95) — Notion Black
    textSecondary: Color(0xFF615D59), // Warm Gray 500
    textMuted: Color(0xFFA39E98), // Warm Gray 300
    textOnAccent: Color(0xFFFFFFFF), // Button text on blue
    error: Color(0xFFDD5B00), // Orange (warning/attention)
    success: Color(0xFF1AAE39), // Green (confirmation)
    calendarToday: Color(0xFF0075DE), // Notion Blue
    calendarDot: Color(0xFF0075DE), // Notion Blue
    calendarSelected: Color(0xFFF2F9FF), // Badge Blue Bg (subtle)
    calendarWeekend: Color(0xFFDD5B00), // Orange (DESIGN.md semantic accent)
    localAccent: Color(0xFFDD5B00), // Orange (local note emphasis)
    focus: Color(0xFF097FE8), // Focus Blue (keyboard ring)
    badgeText: Color(0xFF097FE8), // Pill badge text on accentSubtle
    linkLight: Color(0xFF62AEF0), // Link variant for dark surfaces
    highlight: Color(0xFFFDE68A), // Search match highlight (yellow)
    shadowTint: Color(0x0A000000), // rgba(0,0,0,0.04) — base shadow tint
  );

  /// Notion-inspired dark palette — warm dark surfaces (not pure black),
  /// near-white warm text, blue accent lightened for contrast on dark. Keeps
  /// the same warm-neutral philosophy as [light]; borders are light-on-dark
  /// whispers.
  static const dark = AppColorsExtension(
    scaffold: Color(0xFF1B1A18), // warm near-black page bg
    surface: Color(0xFF242220), // warm dark card surface
    surfaceLight: Color(0xFF2E2C28), // elevated / alt surface
    surfaceHover: Color(0x14FFFFFF), // rgba(255,255,255,0.08) — hover fill
    border: Color(0x24FFFFFF), // rgba(255,255,255,0.14) — whisper border
    borderSubtle: Color(0x14FFFFFF), // rgba(255,255,255,0.08) — fainter divider
    accent: Color(0xFF3B8EEF), // Notion Blue lightened for dark contrast
    accentMuted: Color(0xFF2E6FC7), // pressed
    accentSubtle: Color(0xFF16304C), // deep blue-tinted fill (selected/badge bg)
    textPrimary: Color(0xFFECEAE6), // warm near-white
    textSecondary: Color(0xFFA8A39C), // warm gray
    textMuted: Color(0xFF8A857D), // dim warm gray — raised for dark contrast (~4.4:1 on surface)
    textOnAccent: Color(0xFFFFFFFF), // text on blue
    error: Color(0xFFE8703A), // orange, brightened for dark
    success: Color(0xFF3FBF57), // green, brightened
    calendarToday: Color(0xFF3B8EEF),
    calendarDot: Color(0xFF3B8EEF),
    calendarSelected: Color(0xFF16304C),
    calendarWeekend: Color(0xFFFF8A3D), // Orange lightened for dark contrast
    localAccent: Color(0xFFE8703A),
    focus: Color(0xFF62AEF0),
    badgeText: Color(0xFF7FC0FF),
    linkLight: Color(0xFF7FC0FF),
    highlight: Color(0xFF5A4A12), // dark amber search highlight
    shadowTint: Color(0x33000000), // deeper shadow on dark
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
      calendarWeekend: calendarWeekend,
      localAccent: localAccent ?? this.localAccent,
      focus: focus,
      badgeText: badgeText,
      linkLight: linkLight,
      highlight: highlight,
      shadowTint: shadowTint,
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
      calendarWeekend: Color.lerp(calendarWeekend, other.calendarWeekend, t)!,
      localAccent: Color.lerp(localAccent, other.localAccent, t)!,
      focus: Color.lerp(focus, other.focus, t)!,
      badgeText: Color.lerp(badgeText, other.badgeText, t)!,
      linkLight: Color.lerp(linkLight, other.linkLight, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      shadowTint: Color.lerp(shadowTint, other.shadowTint, t)!,
    );
  }
}

/// Shortcut to access app colors from BuildContext.
extension AppColorsX on BuildContext {
  AppColorsExtension get colors =>
      Theme.of(this).extension<AppColorsExtension>()!;
}
