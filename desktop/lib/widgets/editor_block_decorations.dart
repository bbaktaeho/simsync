import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A block-level region in the editor text that gets a painted decoration
/// behind the (single, still-editable) TextField: a fenced code block drawn as a
/// box, or a `---` thematic break drawn as a horizontal rule.
class EditorBlockRegion {
  const EditorBlockRegion({
    required this.start,
    required this.end,
    required this.isCode,
  });

  /// Character offset of the first char of the block (inclusive).
  final int start;

  /// Character offset just past the last char of the block (exclusive end of
  /// the selection range used to measure the block).
  final int end;

  /// True for fenced code blocks (drawn as a box); false for `---` rules.
  final bool isCode;

  @override
  bool operator ==(Object other) =>
      other is EditorBlockRegion &&
      other.start == start &&
      other.end == end &&
      other.isCode == isCode;

  @override
  int get hashCode => Object.hash(start, end, isCode);
}

final RegExp _fence = RegExp(r'^\s*(?:```|~~~)');
final RegExp _rule = RegExp(r'^\s*(?:-{3,}|\*{3,}|_{3,})\s*$');

/// Scans [text] for fenced code blocks and `---` rules, returning their exact
/// character ranges. A code block spans from its opening fence line through its
/// closing fence line (or to end-of-text if unterminated).
List<EditorBlockRegion> parseEditorBlockRegions(String text) {
  if (text.isEmpty) return const [];
  final regions = <EditorBlockRegion>[];
  final lines = text.split('\n');
  var offset = 0;
  var inFence = false;
  var codeStart = 0;

  for (final line in lines) {
    final lineStart = offset;
    final lineEnd = offset + line.length;
    if (_fence.hasMatch(line)) {
      if (inFence) {
        regions.add(EditorBlockRegion(
            start: codeStart, end: lineEnd, isCode: true));
        inFence = false;
      } else {
        inFence = true;
        codeStart = lineStart;
      }
    } else if (!inFence && _rule.hasMatch(line)) {
      regions.add(
          EditorBlockRegion(start: lineStart, end: lineEnd, isCode: false));
    }
    offset = lineEnd + 1; // + the '\n'
  }

  // Unterminated fence: treat the rest of the document as the code block.
  if (inFence) {
    regions.add(
        EditorBlockRegion(start: codeStart, end: text.length, isCode: true));
  }
  return regions;
}

/// Paints code-block boxes and `---` rules behind the editor's TextField.
///
/// It lays out a [TextPainter] with the SAME span, strut, width and text scaler
/// as the TextField, so the measured line boxes line up exactly with the
/// rendered text. The drawing is translated by the field's scroll offset.
class EditorBlockDecorationPainter extends CustomPainter {
  EditorBlockDecorationPainter({
    required this.span,
    required this.regions,
    required this.strutStyle,
    required this.textScaler,
    required this.scrollController,
    required this.codeBackground,
    required this.codeBorder,
    required this.ruleColor,
  }) : super(repaint: scrollController);

  final InlineSpan span;
  final List<EditorBlockRegion> regions;
  final StrutStyle strutStyle;
  final TextScaler textScaler;
  final ScrollController scrollController;
  final Color codeBackground;
  final Color codeBorder;
  final Color ruleColor;

  // Layout is cached across scroll repaints; only width changes invalidate it.
  double? _laidOutWidth;
  List<({EditorBlockRegion region, double top, double bottom})>? _measured;

  // RenderEditable lays text out at `width - _caretMargin`, where the margin is
  // `_kCaretGap (1.0) + cursorWidth (2.0)`. Matching it keeps the painter's line
  // wrapping (and therefore every box/rule below) row-aligned with the field.
  static const double _caretMargin = 3.0;

  void _measure(double width) {
    final painter = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      strutStyle: strutStyle,
      textScaler: textScaler,
    )..layout(maxWidth: math.max(0, width - _caretMargin));

    final out = <({EditorBlockRegion region, double top, double bottom})>[];
    for (final region in regions) {
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: region.start, extentOffset: region.end),
        boxHeightStyle: ui.BoxHeightStyle.max,
      );
      if (boxes.isEmpty) continue;
      var top = double.infinity;
      var bottom = double.negativeInfinity;
      for (final box in boxes) {
        top = math.min(top, box.top);
        bottom = math.max(bottom, box.bottom);
      }
      out.add((region: region, top: top, bottom: bottom));
    }
    painter.dispose();
    _measured = out;
    _laidOutWidth = width;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (regions.isEmpty || size.width <= 0) return;
    if (_measured == null || _laidOutWidth != size.width) {
      _measure(size.width);
    }
    final scrollY = scrollController.hasClients ? scrollController.offset : 0.0;
    canvas.clipRect(Offset.zero & size);

    final fill = Paint()..color = codeBackground;
    final stroke = Paint()
      ..color = codeBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rule = Paint()
      ..color = ruleColor
      ..strokeWidth = 1;

    for (final m in _measured!) {
      if (m.region.isCode) {
        final rect = Rect.fromLTRB(
          0,
          m.top - scrollY - 4,
          size.width,
          m.bottom - scrollY + 4,
        );
        if (rect.bottom < 0 || rect.top > size.height) continue;
        final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
        canvas.drawRRect(rrect, fill);
        canvas.drawRRect(rrect, stroke);
      } else {
        final y = (m.top + m.bottom) / 2 - scrollY;
        if (y < 0 || y > size.height) continue;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), rule);
      }
    }
  }

  @override
  bool shouldRepaint(EditorBlockDecorationPainter old) {
    return old.span != span ||
        old.regions.length != regions.length ||
        old.codeBackground != codeBackground ||
        old.codeBorder != codeBorder ||
        old.ruleColor != ruleColor ||
        old.strutStyle != strutStyle;
  }
}
