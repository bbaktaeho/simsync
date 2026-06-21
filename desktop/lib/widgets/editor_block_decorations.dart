import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/markdown_editing.dart';

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
/// returning their character ranges. A code block's range is its CONTENT lines
/// (between the fences) so the painted box wraps just the code — the fence lines
/// stay full-height but outside the box. An empty block falls back to the fence
/// line. A blockquote groups consecutive `>` lines.
List<EditorBlockRegion> parseEditorBlockRegions(String text) {
  if (text.isEmpty) return const [];
  final regions = <EditorBlockRegion>[];
  final lines = text.split('\n');
  var offset = 0;
  var inFence = false;
  var fenceStart = 0; // open-fence line start (fallback for an empty block)
  var contentStart = 0; // first content line start
  var contentEnd = -1; // last content line end (-1 = no content seen yet)
  int? quoteStart;
  var quoteEnd = 0;

  void flushQuote() {
    if (quoteStart != null) {
      regions.add(EditorBlockRegion(
          start: quoteStart!, end: quoteEnd, kind: EditorBlockKind.quote));
      quoteStart = null;
    }
  }

  void closeCode(int fallbackEnd) {
    final hasContent = contentEnd >= contentStart;
    regions.add(EditorBlockRegion(
      start: hasContent ? contentStart : fenceStart,
      end: hasContent ? contentEnd : fallbackEnd,
      kind: EditorBlockKind.code,
    ));
  }

  for (final line in lines) {
    final lineStart = offset;
    final lineEnd = offset + line.length;
    if (_fence.hasMatch(line)) {
      flushQuote();
      if (inFence) {
        closeCode(lineEnd);
        inFence = false;
      } else {
        inFence = true;
        fenceStart = lineStart;
        contentStart = lineEnd + 1; // the line after the open fence
        contentEnd = -1;
      }
    } else if (inFence) {
      contentEnd = lineEnd; // extend the content range
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
  if (inFence) closeCode(text.length); // unterminated: content runs to the end
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
    required this.tables,
    required this.strutStyle,
    required this.textScaler,
    required this.scrollController,
    required this.codeBackground,
    required this.codeBorder,
    required this.ruleColor,
    required this.quoteBar,
    required this.tableFill,
    required this.tableHeaderFill,
    required this.tableBorder,
    required this.tableTextStyle,
    required this.tableHeaderStyle,
  }) : super(repaint: scrollController);

  final InlineSpan span;
  final List<EditorBlockRegion> regions;
  final List<TableRegion> tables;
  final StrutStyle strutStyle;
  final TextScaler textScaler;
  final ScrollController scrollController;
  final Color codeBackground;
  final Color codeBorder;
  final Color ruleColor;
  final Color quoteBar;
  final Color tableFill;
  final Color tableHeaderFill;
  final Color tableBorder;
  final TextStyle tableTextStyle;
  final TextStyle tableHeaderStyle;

  // RenderEditable lays text out at `width - _caretMargin` (_kCaretGap 1.0 +
  // cursorWidth 2.0). Matching it keeps line wrapping — and every decoration
  // below — aligned with the field.
  static const double _caretMargin = 3.0;

  double? _laidOutWidth;
  List<({EditorBlockRegion region, double top, double bottom})>? _measured;
  List<({TableRegion table, List<({double top, double bottom})> rows})>?
      _measuredTables;

  ({double top, double bottom})? _boxSpan(TextPainter painter, int start, int end) {
    final boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
      boxHeightStyle: ui.BoxHeightStyle.max,
    );
    if (boxes.isEmpty) return null;
    var top = double.infinity;
    var bottom = double.negativeInfinity;
    for (final box in boxes) {
      top = math.min(top, box.top);
      bottom = math.max(bottom, box.bottom);
    }
    return (top: top, bottom: bottom);
  }

  void _measure(double width) {
    final painter = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      strutStyle: strutStyle,
      textScaler: textScaler,
    )..layout(maxWidth: math.max(0, width - _caretMargin));

    final out = <({EditorBlockRegion region, double top, double bottom})>[];
    for (final region in regions) {
      final span = _boxSpan(painter, region.start, region.end);
      if (span == null) continue;
      out.add((region: region, top: span.top, bottom: span.bottom));
    }

    final outTables =
        <({TableRegion table, List<({double top, double bottom})> rows})>[];
    for (final t in tables) {
      final rows = <({double top, double bottom})>[];
      for (final r in t.rowRanges) {
        rows.add(_boxSpan(painter, r.start, r.end) ?? (top: 0, bottom: 0));
      }
      outTables.add((table: t, rows: rows));
    }

    painter.dispose();
    _measured = out;
    _measuredTables = outTables;
    _laidOutWidth = width;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if ((regions.isEmpty && tables.isEmpty) || size.width <= 0) return;
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

    for (final m in _measuredTables ?? const []) {
      _paintTable(canvas, size, m.table.table, m.rows, scrollY);
    }
  }

  // Draws a rendered table over its (hidden) markdown: equal-width columns,
  // tinted header row, grid lines, and clipped/aligned cell text. The row
  // y-positions come from the hidden markdown lines, so it stays aligned.
  void _paintTable(
    Canvas canvas,
    Size size,
    MarkdownTableData data,
    List<({double top, double bottom})> rows,
    double scrollY,
  ) {
    if (rows.isEmpty) return;
    final top = rows.first.top - scrollY;
    final bottom = rows.last.bottom - scrollY;
    if (bottom < 0 || top > size.height) return;
    final cols = data.columns;
    if (cols == 0) return;

    // Split the reserved band (header top → last body bottom) evenly across the
    // logical rows. The hidden separator line keeps a full strut-height even at
    // fontSize ~0, so we cannot rely on its zero height; dividing evenly absorbs
    // that slack so there is no blank band between the header and first row. We
    // draw the cell text ourselves, so it need not sit on the hidden line.
    final n = rows.length;
    final colW = size.width / cols;
    final rowH = (bottom - top) / n;
    double rowTop(int r) => top + r * rowH;

    final outer = Rect.fromLTRB(0, top, size.width, bottom);
    final rrect = RRect.fromRectAndRadius(outer, const Radius.circular(6));

    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(outer, Paint()..color = tableFill);
    canvas.drawRect(
      Rect.fromLTRB(0, top, size.width, rowTop(1)),
      Paint()..color = tableHeaderFill,
    );
    canvas.restore();

    final grid = Paint()
      ..color = tableBorder
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var k = 1; k < cols; k++) {
      final x = colW * k;
      canvas.drawLine(Offset(x, top), Offset(x, bottom), grid);
    }
    for (var r = 1; r < n; r++) {
      final y = rowTop(r);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    canvas.drawRRect(rrect, grid);

    for (var r = 0; r < n && r < data.rows.length; r++) {
      final rt = rowTop(r);
      final rb = rowTop(r + 1);
      for (var k = 0; k < cols; k++) {
        final cell = k < data.rows[r].length ? data.rows[r][k] : '';
        if (cell.isEmpty) continue;
        _drawCell(
          canvas,
          cell,
          Rect.fromLTRB(colW * k, rt, colW * (k + 1), rb),
          r == 0 ? tableHeaderStyle : tableTextStyle,
          data.aligns[k],
        );
      }
    }
  }

  void _drawCell(
    Canvas canvas,
    String text,
    Rect rect,
    TextStyle style,
    MarkdownTableAlign align,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: switch (align) {
        MarkdownTableAlign.left => TextAlign.left,
        MarkdownTableAlign.center => TextAlign.center,
        MarkdownTableAlign.right => TextAlign.right,
      },
      textScaler: textScaler,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(0, rect.width - 16));
    final dy = rect.top + (rect.height - tp.height) / 2;
    canvas.save();
    canvas.clipRect(rect);
    tp.paint(canvas, Offset(rect.left + 8, dy));
    canvas.restore();
    tp.dispose();
  }

  @override
  bool shouldRepaint(EditorBlockDecorationPainter old) {
    return old.span != span ||
        old.regions.length != regions.length ||
        old.tables.length != tables.length ||
        old.codeBackground != codeBackground ||
        old.codeBorder != codeBorder ||
        old.ruleColor != ruleColor ||
        old.quoteBar != quoteBar ||
        old.tableFill != tableFill ||
        old.tableHeaderFill != tableHeaderFill ||
        old.tableBorder != tableBorder ||
        old.strutStyle != strutStyle;
  }
}
