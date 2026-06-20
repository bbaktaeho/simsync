import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Kind of block decoration painted behind the (still-editable) TextField.
enum EditorBlockKind { code, rule, quote }

/// A block-level region of the editor text that gets a painted decoration: a
/// fenced code block (box), a `---` thematic break (rule), or a `>` blockquote
/// (left bar).
class EditorBlockRegion {
  const EditorBlockRegion({
    required this.start,
    required this.end,
    required this.kind,
  });

  /// Character offset of the first char of the block (inclusive).
  final int start;

  /// Character offset just past the last char of the block (exclusive).
  final int end;

  final EditorBlockKind kind;

  @override
  bool operator ==(Object other) =>
      other is EditorBlockRegion &&
      other.start == start &&
      other.end == end &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(start, end, kind);
}

final RegExp _fence = RegExp(r'^\s*(?:```|~~~)');
final RegExp _rule = RegExp(r'^\s*(?:-{3,}|\*{3,}|_{3,})\s*$');
final RegExp _quote = RegExp(r'^\s*>');

/// Scans [text] for fenced code blocks, `---` rules and `>` blockquotes,
/// returning their exact character ranges. A code block spans both fence lines
/// (or to end-of-text if unterminated); a blockquote groups consecutive `>`
/// lines.
List<EditorBlockRegion> parseEditorBlockRegions(String text) {
  if (text.isEmpty) return const [];
  final regions = <EditorBlockRegion>[];
  final lines = text.split('\n');
  var offset = 0;
  var inFence = false;
  var codeStart = 0;
  int? quoteStart;
  var quoteEnd = 0;

  void flushQuote() {
    if (quoteStart != null) {
      regions.add(EditorBlockRegion(
          start: quoteStart!, end: quoteEnd, kind: EditorBlockKind.quote));
      quoteStart = null;
    }
  }

  for (final line in lines) {
    final lineStart = offset;
    final lineEnd = offset + line.length;
    if (_fence.hasMatch(line)) {
      flushQuote();
      if (inFence) {
        regions.add(EditorBlockRegion(
            start: codeStart, end: lineEnd, kind: EditorBlockKind.code));
        inFence = false;
      } else {
        inFence = true;
        codeStart = lineStart;
      }
    } else if (inFence) {
      // code content — part of the open code block
    } else if (_quote.hasMatch(line)) {
      quoteStart ??= lineStart;
      quoteEnd = lineEnd;
    } else if (_rule.hasMatch(line)) {
      flushQuote();
      regions.add(EditorBlockRegion(
          start: lineStart, end: lineEnd, kind: EditorBlockKind.rule));
    } else {
      flushQuote();
    }
    offset = lineEnd + 1; // + the '\n'
  }

  flushQuote();
  if (inFence) {
    regions.add(EditorBlockRegion(
        start: codeStart, end: text.length, kind: EditorBlockKind.code));
  }
  return regions;
}

/// Paints code-block boxes, `---` rules and `>` quote bars behind the editor's
/// TextField.
///
/// It lays out a [TextPainter] with the SAME span, strut and width as the field
/// (minus the caret margin) so the measured line boxes line up exactly with the
/// rendered text. Drawing is translated by the field's scroll offset.
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
    required this.quoteBar,
  }) : super(repaint: scrollController);

  final InlineSpan span;
  final List<EditorBlockRegion> regions;
  final StrutStyle strutStyle;
  final TextScaler textScaler;
  final ScrollController scrollController;
  final Color codeBackground;
  final Color codeBorder;
  final Color ruleColor;
  final Color quoteBar;

  // RenderEditable lays text out at `width - _caretMargin` (_kCaretGap 1.0 +
  // cursorWidth 2.0). Matching it keeps line wrapping — and every decoration
  // below — aligned with the field.
  static const double _caretMargin = 3.0;

  double? _laidOutWidth;
  List<({EditorBlockRegion region, double top, double bottom})>? _measured;

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
    final bar = Paint()..color = quoteBar;

    for (final m in _measured!) {
      final top = m.top - scrollY;
      final bottom = m.bottom - scrollY;
      if (bottom < 0 || top > size.height) continue;
      switch (m.region.kind) {
        case EditorBlockKind.code:
          final rect = Rect.fromLTRB(0, top - 4, size.width, bottom + 4);
          final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
          canvas.drawRRect(rrect, fill);
          canvas.drawRRect(rrect, stroke);
        case EditorBlockKind.rule:
          final y = (top + bottom) / 2;
          canvas.drawLine(Offset(0, y), Offset(size.width, y), rule);
        case EditorBlockKind.quote:
          final rect = Rect.fromLTRB(2, top + 1, 5, bottom - 1);
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
            bar,
          );
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
        old.quoteBar != quoteBar ||
        old.strutStyle != strutStyle;
  }
}
