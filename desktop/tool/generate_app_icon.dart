// Generates the SimSync macOS app icon: a white circular "sync" loop (two
// chasing arrows) on a Notion-Blue → Deep-Navy squircle. Pure dart:ui drawing,
// so it needs no extra packages — but it needs the Flutter engine for
// Picture.toImage, hence it runs under the test harness:
//
//   cd desktop && flutter test tool/generate_app_icon.dart
//
// It overwrites the PNGs referenced by AppIcon.appiconset/Contents.json. Each
// size is rendered natively (not downscaled) so small icons stay crisp.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Brand palette (see DESIGN.md): Notion Blue accent, Deep Navy for depth.
const _blueTop = Color(0xFF2E9BF2);
const _blueMid = Color(0xFF0075DE); // Notion Blue — the brand anchor
const _navy = Color(0xFF1C3C86); // ≈ Deep Navy #213183

void _paintIcon(Canvas canvas, double s) {
  // macOS squircle: centered rounded square with a transparent margin; the
  // system adds its own drop shadow, so we don't.
  final margin = s * 0.092;
  final side = s - margin * 2;
  final rect = Rect.fromLTWH(margin, margin, side, side);
  final radius = Radius.circular(side * 0.2237); // Apple superellipse approx.
  final rrect = RRect.fromRectAndRadius(rect, radius);

  canvas.drawRRect(
    rrect,
    Paint()
      ..shader = ui.Gradient.linear(
        rect.topCenter,
        rect.bottomCenter,
        const [_blueTop, _blueMid, _navy],
        const [0.0, 0.52, 1.0],
      ),
  );
  // Faint top sheen for depth (no skeuomorphic gloss).
  canvas.drawRRect(
    rrect,
    Paint()
      ..shader = ui.Gradient.linear(
        rect.topCenter,
        rect.center,
        const [Color(0x24FFFFFF), Color(0x00FFFFFF)],
      ),
  );

  // The sync loop: two 150° arcs, rotationally symmetric, each ending in an
  // arrowhead — a clockwise "in sync" cycle.
  final c = rect.center;
  final r = s * 0.232;
  final w = s * 0.082;

  void drawSyncArrow(double startDeg, Paint stroke, Paint fill, Offset shift) {
    final center = c + shift;
    final start = startDeg * math.pi / 180;
    final sweep = 150 * math.pi / 180;
    canvas.drawArc(
        Rect.fromCircle(center: center, radius: r), start, sweep, false, stroke);

    // Triangular head at the leading end, pointing along the tangent.
    final end = start + sweep;
    final p = Offset(center.dx + r * math.cos(end), center.dy + r * math.sin(end));
    final tangent = Offset(-math.sin(end), math.cos(end)); // direction of motion
    final radial = Offset(math.cos(end), math.sin(end));
    final tip = p + tangent * (w * 1.45);
    final back = p - tangent * (w * 0.15);
    final head = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(back.dx + radial.dx * w * 1.15, back.dy + radial.dy * w * 1.15)
      ..lineTo(back.dx - radial.dx * w * 1.15, back.dy - radial.dy * w * 1.15)
      ..close();
    canvas.drawPath(head, fill);
  }

  // Soft shadow pass for legibility on the gradient, then the white mark.
  final shadowStroke = Paint()
    ..color = const Color(0x33001A3A)
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.010);
  final shadowFill = Paint()
    ..color = const Color(0x33001A3A)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.010);
  final whiteStroke = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round;
  final whiteFill = Paint()..color = Colors.white;

  final shadowShift = Offset(0, s * 0.012);
  drawSyncArrow(200, shadowStroke, shadowFill, shadowShift);
  drawSyncArrow(20, shadowStroke, shadowFill, shadowShift);
  drawSyncArrow(200, whiteStroke, whiteFill, Offset.zero);
  drawSyncArrow(20, whiteStroke, whiteFill, Offset.zero);
}

Future<void> _writeIcon(int size, String path) async {
  final recorder = ui.PictureRecorder();
  _paintIcon(Canvas(recorder), size.toDouble());
  final image = await recorder.endRecording().toImage(size, size);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(png!.buffer.asUint8List());
  image.dispose();
}

void main() {
  test('generate SimSync app icons', () async {
    const dir = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
    const sizes = [16, 32, 64, 128, 256, 512, 1024];
    for (final size in sizes) {
      await _writeIcon(size, '$dir/app_icon_$size.png');
    }
    expect(File('$dir/app_icon_1024.png').existsSync(), isTrue);
  });
}
