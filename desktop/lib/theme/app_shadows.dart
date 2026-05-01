import 'package:flutter/material.dart';

/// Multi-layer shadow stacks per DESIGN.md §6 (Depth & Elevation).
///
/// Notion's shadow philosophy: many low-opacity layers (≤ 0.05) accumulate
/// into soft, natural depth — not a single hard shadow.
abstract final class AppShadows {
  /// Soft Card (Level 2) — 4-layer stack, max opacity 0.04, blur up to 18px.
  /// Use for content cards and feature blocks.
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x0A000000), // rgba(0,0,0,0.04)
      offset: Offset(0, 4),
      blurRadius: 18,
    ),
    BoxShadow(
      color: Color(0x07000000), // rgba(0,0,0,0.027)
      offset: Offset(0, 2.025),
      blurRadius: 7.84688,
    ),
    BoxShadow(
      color: Color(0x05000000), // rgba(0,0,0,0.02)
      offset: Offset(0, 0.8),
      blurRadius: 2.925,
    ),
    BoxShadow(
      color: Color(0x03000000), // rgba(0,0,0,0.01)
      offset: Offset(0, 0.175),
      blurRadius: 1.04062,
    ),
  ];

  /// Deep Card (Level 3) — 5-layer stack, max opacity 0.05, blur up to 52px.
  /// Use for modals, featured panels, hero elements.
  static const List<BoxShadow> deep = [
    BoxShadow(
      color: Color(0x03000000), // rgba(0,0,0,0.01)
      offset: Offset(0, 1),
      blurRadius: 3,
    ),
    BoxShadow(
      color: Color(0x05000000), // rgba(0,0,0,0.02)
      offset: Offset(0, 3),
      blurRadius: 7,
    ),
    BoxShadow(
      color: Color(0x05000000), // rgba(0,0,0,0.02)
      offset: Offset(0, 7),
      blurRadius: 15,
    ),
    BoxShadow(
      color: Color(0x0A000000), // rgba(0,0,0,0.04)
      offset: Offset(0, 14),
      blurRadius: 28,
    ),
    BoxShadow(
      color: Color(0x0D000000), // rgba(0,0,0,0.05)
      offset: Offset(0, 23),
      blurRadius: 52,
    ),
  ];
}
