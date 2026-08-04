// Runnable check for PopoverAnchor.compute — the multi-monitor cases that used
// to break (wrong display, bottom-of-screen y, primary-clamped x) as asserts.
// Compiles the real production file, so it fails if the shipped math regresses.
//
// Run from the repo root:
//   swiftc desktop/macos/Runner/PopoverAnchor.swift \
//     desktop/tool/popover_anchor_check.swift \
//     -o /tmp/popover_anchor_check && /tmp/popover_anchor_check

import CoreGraphics

@main
enum PopoverAnchorCheck {
  static func geo(
    _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, menuBar: CGFloat
  ) -> ScreenGeometry {
    ScreenGeometry(
      frame: CGRect(x: x, y: y, width: w, height: h),
      visibleFrame: CGRect(x: x, y: y, width: w, height: h - menuBar))
  }

  static func main() {
    let width: CGFloat = 332

    // 1. Notched single display (menu bar 38): popover top sits at y=38,
    //    right-aligned to the icon.
    let notched = [geo(0, 0, 1728, 1117, menuBar: 38)]
    var p = PopoverAnchor.compute(
      mouse: CGPoint(x: 1600, y: 1110), screens: notched,
      iconRight: 1620, width: width)
    assert(p == CGPoint(x: 1288, y: 38), "notched primary: \(p)")

    // 2. Display LEFT of the primary (negative global x): the popover must
    //    stay on it — the old Dart `dx < 8` clamp yanked it onto the primary.
    let leftOfPrimary = [
      geo(0, 0, 2560, 1440, menuBar: 24),
      geo(-1920, 200, 1920, 1080, menuBar: 24),
    ]
    p = PopoverAnchor.compute(
      mouse: CGPoint(x: -500, y: 1270), screens: leftOfPrimary,
      iconRight: -476, width: width)
    assert(p == CGPoint(x: -808, y: 184), "left display: \(p)")

    // 3. Display ABOVE the primary: y is negative in the flipped space — the
    //    old `bounds.bottom > 0` guard discarded exactly this and fell back to
    //    the primary's inset.
    let abovePrimary = [
      geo(0, 0, 2560, 1440, menuBar: 24),
      geo(200, 1440, 1920, 1080, menuBar: 24),
    ]
    p = PopoverAnchor.compute(
      mouse: CGPoint(x: 900, y: 2500), screens: abovePrimary,
      iconRight: 950, width: width)
    assert(p == CGPoint(x: 618, y: -1056), "above display: \(p)")

    // 4. Pointer pinned to a display's very top edge (y == frame.maxY, which
    //    CGRect.contains excludes) still resolves to the clicked display.
    p = PopoverAnchor.compute(
      mouse: CGPoint(x: -500, y: 1280), screens: leftOfPrimary,
      iconRight: -476, width: width)
    assert(p == CGPoint(x: -808, y: 184), "top-edge pin: \(p)")

    // 5. An icon hint far from the pointer (another display's status window)
    //    is ignored in favor of the pointer.
    p = PopoverAnchor.compute(
      mouse: CGPoint(x: -500, y: 1270), screens: leftOfPrimary,
      iconRight: 2400, width: width)
    assert(p == CGPoint(x: -820, y: 184), "mirrored hint: \(p)")

    // 6. Clamped inside the right edge of the clicked display.
    let plain = [geo(0, 0, 2560, 1440, menuBar: 24)]
    p = PopoverAnchor.compute(
      mouse: CGPoint(x: 2550, y: 1430), screens: plain,
      iconRight: 2556, width: width)
    assert(p == CGPoint(x: 2220, y: 24), "right clamp: \(p)")

    // 7. No hint at all: right edge falls half an icon right of the pointer.
    p = PopoverAnchor.compute(
      mouse: CGPoint(x: 2000, y: 1430), screens: plain,
      iconRight: nil, width: width)
    assert(p == CGPoint(x: 1680, y: 24), "no hint: \(p)")

    print("popover_anchor_check: 7 scenarios OK")
  }
}
