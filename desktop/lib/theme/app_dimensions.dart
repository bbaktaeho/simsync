/// Layout constants for consistent spacing and sizing.
abstract final class AppDimensions {
  // ── Spacing (DESIGN.md: 8px base scale) ──
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 12.0;
  static const double spacingLg = 16.0;
  static const double spacingXl = 24.0;
  static const double spacingXxl = 32.0;
  static const double spacingXxxl = 48.0;
  static const double spacingHero = 80.0; // section vertical rhythm (desktop)

  // ── Layout ──
  static const double sidebarDefaultWidth = 300.0;
  static const double sidebarMinWidth = 200.0;
  static const double sidebarCollapseThreshold = 150.0;
  static const double sidebarMaxRatio = 0.4; // 화면의 40%까지
  static const double resizeHandleWidth = 6.0;

  // ── Border Radius (DESIGN.md: micro 4 / subtle 5 / standard 8 / comfortable 12 / large 16 / pill) ──
  static const double radiusMicro = 4.0;
  static const double radiusSubtle = 5.0;
  static const double radiusStandard = 8.0;
  static const double radiusComfortable = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusPill = 9999.0;

  // ── Animation ──
  static const Duration animFast = Duration(milliseconds: 200);
  static const Duration animMedium = Duration(milliseconds: 300);

  // ── Calendar ──
  static const double calendarCellSize = 32.0;
  static const double calendarDotSize = 5.0;

  // ── Pagination ──
  static const int notesPerPage = 10;

  // ── Editor ──
  static const double editorMaxWidth = 900.0;

  // ── Tag ──
  static const int maxVisibleTags = 2;
}
