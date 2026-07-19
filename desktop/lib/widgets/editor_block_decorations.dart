import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../services/markdown_editing.dart';

/// Kind of block decoration painted behind the (still-editable) TextField.
enum EditorBlockKind { code, rule, quote, detailsGuide }

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
final RegExp _quote = RegExp(r'^\s*[>|]');

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
/// 그리기 좌표는 필드의 [RenderEditable]에 직접 물어본다 — paint 단계는 항상
/// 레이아웃 이후이므로 이번 프레임의 실제 배치와 정확히 일치한다. (예전의
/// 미러 TextPainter 방식은 스트럿 floor를 없애면 RenderEditable과 ~2.3px
/// 발산하는 것이 실측으로 확인되어 폐기했다.) RenderEditable의 박스 좌표는
/// 스크롤이 반영된 viewport 좌표라 별도 보정이 필요 없다. 대신 스크롤 변경을
/// [repaint]로 받아 다시 그린다.
class EditorBlockDecorationPainter extends CustomPainter {
  EditorBlockDecorationPainter({
    required this.editable,
    required this.regions,
    required Listenable repaint,
    required this.codeBackground,
    required this.codeBorder,
    required this.ruleColor,
    required this.quoteBar,
    required this.detailsGuide,
  }) : super(repaint: repaint);

  /// 필드의 RenderEditable 조회. 아직 붙지 않았으면 null (첫 프레임 등).
  final RenderEditable? Function() editable;

  final List<EditorBlockRegion> regions;
  final Color codeBackground;
  final Color codeBorder;
  final Color ruleColor;
  final Color quoteBar;

  /// 열린 details 본문 왼쪽의 접기 범위 가이드 라인 색 (흐릿하게).
  final Color detailsGuide;

  /// 이 높이 이하의 영역은 접힌 것으로 보고 그리지 않는다 (닫힌 details 본문).
  static const double _collapsedBandThreshold = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (regions.isEmpty || size.width <= 0) return;
    final re = editable();
    if (re == null) return;
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
    final guide = Paint()..color = detailsGuide;

    for (final region in regions) {
      final band = editableBandForRange(re, region.start, region.end);
      if (band == null) continue;
      final top = band.top;
      final bottom = band.bottom;
      if (bottom - top <= _collapsedBandThreshold) continue;
      if (bottom < 0 || top > size.height) continue;
      switch (region.kind) {
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
        case EditorBlockKind.detailsGuide:
          // 접기 버튼(chevron) 열 아래로 이어지는 흐릿한 세로선 — 열린 블록이
          // 어디까지인지 보여준다.
          final rect = Rect.fromLTRB(8, top + 1, 10, bottom - 1);
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(1)),
            guide,
          );
      }
    }
  }

  @override
  bool shouldRepaint(EditorBlockDecorationPainter old) {
    // 밴드 좌표의 원천이 위젯 밖(RenderEditable)에 있어서 regions/colors가
    // 같아도 배치가 달라질 수 있다 (예: 콘텐츠 줌). 새 painter가 만들어지면
    // 항상 다시 그린다 — 사각형 몇 개라 비용은 무시할 수준이다.
    return true;
  }
}

/// [re]에서 [start]..[end] 문자 범위의 세로 밴드(viewport 좌표)를 구한다.
/// 범위가 박스를 만들지 않으면 null.
({double top, double bottom})? editableBandForRange(
    RenderEditable re, int start, int end) {
  final boxes = re.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: end),
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

/// 열린 details 블록의 본문 범위를 [EditorBlockKind.detailsGuide] 영역으로
/// 만든다 — 에디터에서 "어디까지 열려 있는지"를 흐릿한 세로선으로 보여주는
/// 용도. 닫힌 블록과 빈 본문은 제외.
List<EditorBlockRegion> detailsGuideRegions(List<DetailsRegion> details) {
  return [
    for (final d in details)
      if (d.open && d.bodyLineRanges.isNotEmpty)
        EditorBlockRegion(
          start: d.bodyLineRanges.first.start,
          end: d.bodyLineRanges.last.end,
          kind: EditorBlockKind.detailsGuide,
        ),
  ];
}

/// 데코레이션 영역 후처리: 테이블과 겹치는 quote 바(테이블 행도 `|`로 시작),
/// 테이블 구분선과 겹치는 rule 선, 닫힌 details 블록 안의 rule/quote 장식을
/// 제거한다 (접힌 자리에 1px 선 같은 잔상이 남는 것을 막는다).
List<EditorBlockRegion> filterEditorRegions(
  List<EditorBlockRegion> regions,
  List<TableRegion> tables,
  List<DetailsRegion> details,
) {
  if (regions.isEmpty) return regions;
  final sepStarts = {for (final t in tables) t.separatorRange.start};
  bool inClosedDetails(EditorBlockRegion r) =>
      details.any((d) => !d.open && r.start >= d.start && r.end <= d.end);
  return regions.where((r) {
    if (r.kind == EditorBlockKind.rule && sepStarts.contains(r.start)) {
      return false;
    }
    if (r.kind == EditorBlockKind.quote &&
        tables.any((t) => r.start <= t.end && r.end >= t.start)) {
      return false;
    }
    if ((r.kind == EditorBlockKind.rule || r.kind == EditorBlockKind.quote) &&
        inClosedDetails(r)) {
      return false;
    }
    return true;
  }).toList();
}
