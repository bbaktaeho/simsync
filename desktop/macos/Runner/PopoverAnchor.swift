import CoreGraphics
import Foundation

/// Screen metrics in Cocoa's global space (bottom-left origin, +y up).
/// `visibleFrame` is the frame minus that display's menu bar (and Dock).
struct ScreenGeometry {
  let frame: CGRect
  let visibleFrame: CGRect
}

/// Pure math for anchoring the menu bar popover under the tray icon.
///
/// Kept free of Flutter/AppKit imports so `desktop/tool/popover_anchor_check.swift`
/// can compile this exact file standalone and assert the multi-monitor cases
/// (wrong-display, bottom-of-screen, clamp regressions).
enum PopoverAnchor {
  static let edgeMargin: CGFloat = 8
  /// Fallback right-alignment when the tray-icon hint is missing or bogus: the
  /// pointer sits on the icon, so icon-right ≈ pointer + half an icon.
  static let halfIconWidth: CGFloat = 12
  /// A hint farther than this from the pointer belongs to another display's
  /// status-bar window (or is otherwise stale) — ignore it.
  static let hintTolerance: CGFloat = 50

  /// Top-left for the popover in window_manager's coordinate space: x as
  /// Cocoa, y flipped with the primary screen's height — the exact inverse of
  /// window_manager's `NSRect.topLeft` setter, so `setPosition` lands the
  /// panel here on any display.
  ///
  /// The clicked display is the one under the pointer; the popover hangs from
  /// that display's own menu bar bottom (`visibleFrame.maxY`, which tracks
  /// per-display bar heights — plain vs. notched — and resolution changes) and
  /// is clamped inside that display horizontally.
  ///
  /// `screens` must be non-empty with the primary screen first (as
  /// `NSScreen.screens` guarantees).
  static func compute(
    mouse: CGPoint,
    screens: [ScreenGeometry],
    iconRight: CGFloat?,
    width: CGFloat
  ) -> CGPoint {
    let primary = screens[0]
    // A menu bar click can pin the pointer to a display's very top edge
    // (y == frame.maxY, which CGRect.contains excludes) — treat the top edge
    // as inside, and prefer that reading over "bottom edge of the display
    // above" when displays are stacked.
    let screen = screens.first(where: { s in
      mouse.y == s.frame.maxY && mouse.x >= s.frame.minX
        && mouse.x <= s.frame.maxX
    }) ?? screens.first(where: { $0.frame.contains(mouse) }) ?? primary

    var iconRightEdge = iconRight ?? (mouse.x + halfIconWidth)
    if abs(iconRightEdge - mouse.x) > hintTolerance {
      iconRightEdge = mouse.x + halfIconWidth
    }

    // Right-align to the icon, kept fully on the clicked display.
    var x = iconRightEdge - width
    let minX = screen.frame.minX + edgeMargin
    let maxX = screen.frame.maxX - width - edgeMargin
    if x > maxX { x = maxX }
    if x < minX { x = minX }

    // The bar's bottom edge on that display. Equal to frame.maxY when the bar
    // auto-hides — the popover then sits flush with the top, which is fine
    // because the transient bar re-hides over it.
    let topY = screen.visibleFrame.maxY
    return CGPoint(x: x, y: primary.frame.height - topY)
  }
}
