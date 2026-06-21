import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The single source of truth for the SimSync app mark — a white circular
/// "sync" loop on a Notion-Blue → Deep-Navy squircle. Both the in-app logo
/// ([AppLogoMark]) and the generated platform launcher icons paint through the
/// functions here, so they can never drift apart.

const Color _blueTop = Color(0xFF2E9BF2);
const Color _blueMid = Color(0xFF0075DE); // Notion Blue — brand anchor
const Color _navy = Color(0xFF1C3C86); // ≈ Deep Navy #213183

/// Paints the full icon (gradient squircle + sync mark) into an [s]×[s] box.
/// [fullBleed] fills the whole square with no rounded corners — used for iOS
/// and Android, which apply their own mask. macOS uses the rounded squircle.
void paintSyncIcon(Canvas canvas, double s, {bool fullBleed = false}) {
  final margin = fullBleed ? 0.0 : s * 0.092;
  final side = s - margin * 2;
  final rect = Rect.fromLTWH(margin, margin, side, side);
  final radius = fullBleed ? Radius.zero : Radius.circular(side * 0.2237);
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
  // Faint top sheen for depth.
  canvas.drawRRect(
    rrect,
    Paint()
      ..shader = ui.Gradient.linear(
        rect.topCenter,
        rect.center,
        const [Color(0x24FFFFFF), Color(0x00FFFFFF)],
      ),
  );

  _drawSyncMark(
    canvas,
    rect.center,
    side * 0.284,
    side * 0.10,
    withShadow: true,
  );
}

/// Paints only the white sync mark (no background) into an [s]×[s] box, sized
/// for an Android adaptive-icon foreground's safe zone.
void paintSyncForeground(Canvas canvas, double s) {
  _drawSyncMark(
    canvas,
    Offset(s / 2, s / 2),
    s * 0.21,
    s * 0.072,
    withShadow: false,
  );
}

void _drawSyncMark(
  Canvas canvas,
  Offset center,
  double r,
  double w, {
  required bool withShadow,
}) {
  void arrow(double startDeg, Paint stroke, Paint fill, Offset shift) {
    final origin = center + shift;
    final start = startDeg * math.pi / 180;
    final sweep = 150 * math.pi / 180;
    canvas.drawArc(
        Rect.fromCircle(center: origin, radius: r), start, sweep, false, stroke);

    final end = start + sweep;
    final p =
        Offset(origin.dx + r * math.cos(end), origin.dy + r * math.sin(end));
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

  if (withShadow) {
    final blur = w * 0.15;
    final shadowStroke = Paint()
      ..color = const Color(0x33001A3A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    final shadowFill = Paint()
      ..color = const Color(0x33001A3A)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    final shift = Offset(0, w * 0.15);
    arrow(200, shadowStroke, shadowFill, shift);
    arrow(20, shadowStroke, shadowFill, shift);
  }

  final whiteStroke = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round;
  final whiteFill = Paint()..color = Colors.white;
  arrow(200, whiteStroke, whiteFill, Offset.zero);
  arrow(20, whiteStroke, whiteFill, Offset.zero);
}

/// The SimSync mark as an in-app widget (the rounded app-icon form).
class AppLogoMark extends StatelessWidget {
  const AppLogoMark({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _AppLogoPainter()),
    );
  }
}

class _AppLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) =>
      paintSyncIcon(canvas, size.width, fullBleed: false);

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
