/// Layout constants for consistent spacing and sizing.
abstract final class AppDimensions {
  // ── Spacing ──
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 12.0;
  static const double spacingLg = 16.0;
  static const double spacingXl = 24.0;
  static const double spacingXxl = 32.0;

  // ── Layout ──
  static const double sidebarDefaultWidth = 300.0;
  static const double sidebarMinWidth = 200.0;
  static const double sidebarCollapseThreshold = 150.0;
  static const double sidebarMaxRatio = 0.4; // 화면의 40%까지
  static const double resizeHandleWidth = 6.0;
  static const double borderRadius = 8.0;
  static const double borderRadiusSm = 4.0;
  static const double borderRadiusLg = 12.0;

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
