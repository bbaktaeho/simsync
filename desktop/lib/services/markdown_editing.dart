import 'package:flutter/services.dart';

/// Pure text-manipulation helpers for the markdown editor.
///
/// All logic here is widget-agnostic so it can be unit-tested directly against
/// [TextEditingValue] without pumping a widget.

// ── List continuation on Enter ──────────────────────────────────────────────

final RegExp _taskRe = RegExp(r'^(\s*)([-*+]) +\[([ xX])\] +(.*)$');
final RegExp _orderedRe = RegExp(r'^(\s*)(\d+)([.)]) +(.*)$');
final RegExp _bulletRe = RegExp(r'^(\s*)([-*+]) +(.*)$');
final RegExp _fenceRe = RegExp(r'^\s*(```|~~~)');

class _ListMarker {
  _ListMarker.bullet({required this.indent, required this.bullet, required this.body})
    : isOrdered = false,
      isTask = false,
      number = null,
      delimiter = null;

  _ListMarker.task({required this.indent, required this.bullet, required this.body})
    : isOrdered = false,
      isTask = true,
      number = null,
      delimiter = null;

  _ListMarker.ordered({
    required this.indent,
    required this.number,
    required this.delimiter,
    required this.body,
  }) : isOrdered = true,
       isTask = false,
       bullet = null;

  final String indent;
  final String? bullet;
  final int? number;
  final String? delimiter;
  final bool isOrdered;
  final bool isTask;
  final String body;

  /// The marker text that should start the continued item on the next line.
  String continuation() {
    if (isOrdered) {
      return '$indent${number! + 1}$delimiter ';
    }
    if (isTask) {
      return '$indent$bullet [ ] ';
    }
    return '$indent$bullet ';
  }
}

_ListMarker? _matchMarker(String line) {
  final task = _taskRe.firstMatch(line);
  if (task != null) {
    return _ListMarker.task(
      indent: task.group(1)!,
      bullet: task.group(2)!,
      body: task.group(4)!,
    );
  }
  final ordered = _orderedRe.firstMatch(line);
  if (ordered != null) {
    return _ListMarker.ordered(
      indent: ordered.group(1)!,
      number: int.parse(ordered.group(2)!),
      delimiter: ordered.group(3)!,
      body: ordered.group(4)!,
    );
  }
  final bullet = _bulletRe.firstMatch(line);
  if (bullet != null) {
    return _ListMarker.bullet(
      indent: bullet.group(1)!,
      bullet: bullet.group(2)!,
      body: bullet.group(3)!,
    );
  }
  return null;
}

int _lineStartOf(String text, int offset) {
  var i = offset;
  while (i > 0 && text[i - 1] != '\n') {
    i--;
  }
  return i;
}

int _lineEndOf(String text, int offset) {
  var i = offset;
  while (i < text.length && text[i] != '\n') {
    i++;
  }
  return i;
}

/// Continues markdown list markers when the user presses Enter.
///
/// Acts only when the edit is exactly a single '\n' inserted at a collapsed
/// cursor; otherwise the edit passes through unchanged. On a list line it
/// inserts the next marker (incrementing ordered numbers); on an empty list
/// item it strips the marker to exit the list.
class MarkdownListInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final selection = oldValue.selection;
    if (!selection.isValid || !selection.isCollapsed) return newValue;
    final cursor = selection.baseOffset;
    if (cursor < 0 || cursor > oldValue.text.length) return newValue;

    // Only react to a single newline inserted at the cursor.
    final expected =
        '${oldValue.text.substring(0, cursor)}\n${oldValue.text.substring(cursor)}';
    if (newValue.text != expected) return newValue;
    if (!newValue.selection.isCollapsed ||
        newValue.selection.baseOffset != cursor + 1) {
      return newValue;
    }

    final lineStart = _lineStartOf(oldValue.text, cursor);
    final lineEnd = _lineEndOf(oldValue.text, cursor);
    final line = oldValue.text.substring(lineStart, lineEnd);
    final marker = _matchMarker(line);
    if (marker == null) {
      // Not a list line. If the cursor is on an empty line inside an
      // unterminated code block, pressing Enter closes the block and drops the
      // cursor onto a fresh line below it (so you can keep writing outside).
      return _exitUnterminatedCodeFence(oldValue, lineStart, lineEnd, line) ??
          newValue;
    }

    if (marker.body.trim().isEmpty) {
      // Empty item: clear the marker and exit the list (no newline added).
      final text =
          oldValue.text.substring(0, lineStart) + oldValue.text.substring(lineEnd);
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: lineStart),
      );
    }

    final continuation = marker.continuation();
    final text =
        '${oldValue.text.substring(0, cursor)}\n$continuation${oldValue.text.substring(cursor)}';
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor + 1 + continuation.length),
    );
  }
}

/// When Enter is pressed on an empty line that sits inside an *unterminated*
/// fenced code block, close the block on that line and put the cursor on a new
/// line just below it. Returns null when the situation doesn't apply (so the
/// caller falls back to the default newline). This is the standard "press Enter
/// to leave the code block" affordance — important here because the closing
/// fence renders collapsed and is otherwise hard to reach.
TextEditingValue? _exitUnterminatedCodeFence(
  TextEditingValue value,
  int lineStart,
  int lineEnd,
  String line,
) {
  if (line.trim().isNotEmpty) return null;

  final beforeLines = value.text.substring(0, lineStart).split('\n');
  final fencesBefore = beforeLines.where(_fenceRe.hasMatch).length;
  if (fencesBefore.isEven) return null; // not inside an open code block

  final after = value.text.substring(lineEnd);
  if (after.split('\n').any(_fenceRe.hasMatch)) return null; // already closed below

  // Close with the same fence marker the block was opened with.
  var marker = '```';
  for (final l in beforeLines.reversed) {
    final m = _fenceRe.firstMatch(l);
    if (m != null) {
      marker = m.group(1)!;
      break;
    }
  }

  final text =
      '${value.text.substring(0, lineStart)}$marker\n${value.text.substring(lineEnd)}';
  return TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: lineStart + marker.length + 1),
  );
}

// ── Ordered list renumbering ────────────────────────────────────────────────

final RegExp _orderedLineRe = RegExp(r'^(\s*)(\d+)([.)])(\s.*)$');

class _OrderedLine {
  _OrderedLine({
    required this.indent,
    required this.number,
    required this.delimiter,
    required this.rest,
  });

  final String indent;
  final int number;
  final String delimiter;
  final String rest; // leading whitespace + body, preserved verbatim
}

_OrderedLine? _matchOrderedLine(String line) {
  final m = _orderedLineRe.firstMatch(line);
  if (m == null) return null;
  return _OrderedLine(
    indent: m.group(1)!,
    number: int.parse(m.group(2)!),
    delimiter: m.group(3)!,
    rest: m.group(4)!,
  );
}

int _lineIndexOf(List<String> lines, int offset) {
  var acc = 0;
  for (var i = 0; i < lines.length; i++) {
    final end = acc + lines[i].length;
    if (offset <= end) return i;
    acc = end + 1; // + '\n'
  }
  return lines.isEmpty ? 0 : lines.length - 1;
}

int _lineStartOffset(List<String> lines, int lineIndex) {
  var offset = 0;
  for (var i = 0; i < lineIndex; i++) {
    offset += lines[i].length + 1;
  }
  return offset;
}

/// Renumbers the ordered-list block containing the cursor to a consecutive
/// sequence, starting from the block's first item number. The block spans
/// consecutive lines that are ordered items sharing the cursor line's
/// indentation; it stops at the first non-matching line. No-op if the cursor
/// is not on an ordered item.
TextEditingValue renumberOrderedListAtCursor(TextEditingValue value) {
  final text = value.text;
  final selection = value.selection;
  final cursor = selection.isValid
      ? selection.baseOffset.clamp(0, text.length)
      : text.length;

  final lines = text.split('\n');
  final cursorLine = _lineIndexOf(lines, cursor);
  final current = _matchOrderedLine(lines[cursorLine]);
  if (current == null) return value;

  final indent = current.indent;
  var start = cursorLine;
  while (start - 1 >= 0) {
    final m = _matchOrderedLine(lines[start - 1]);
    if (m == null || m.indent != indent) break;
    start--;
  }
  var end = cursorLine;
  while (end + 1 < lines.length) {
    final m = _matchOrderedLine(lines[end + 1]);
    if (m == null || m.indent != indent) break;
    end++;
  }

  final base = _matchOrderedLine(lines[start])!.number;
  final newLines = List<String>.from(lines);
  for (var i = start; i <= end; i++) {
    final m = _matchOrderedLine(lines[i])!;
    final newNumber = base + (i - start);
    newLines[i] = '${m.indent}$newNumber${m.delimiter}${m.rest}';
  }

  final newText = newLines.join('\n');
  final column = cursor - _lineStartOffset(lines, cursorLine);
  final newLineStart = _lineStartOffset(newLines, cursorLine);
  final newOffset = (newLineStart + column).clamp(0, newText.length);
  return TextEditingValue(
    text: newText,
    selection: TextSelection.collapsed(offset: newOffset),
  );
}

// ── Markdown tables (grid editing) ──────────────────────────────────────────

/// Column text alignment in a GFM table.
enum MarkdownTableAlign { left, center, right }

/// A parsed GFM table: [rows] (the first is the header, the rest are body rows,
/// each normalized to [columns] cells) plus a per-column [aligns].
class MarkdownTableData {
  MarkdownTableData(this.rows, this.aligns);

  /// Row 0 is the header; rows 1.. are the body. Every row has `aligns.length`
  /// cells.
  final List<List<String>> rows;
  final List<MarkdownTableAlign> aligns;

  int get columns => aligns.length;

  /// A blank table with [columns] columns and [bodyRows] empty body rows.
  factory MarkdownTableData.blank({int columns = 3, int bodyRows = 2}) {
    final cols = columns < 1 ? 1 : columns;
    final body = bodyRows < 0 ? 0 : bodyRows;
    return MarkdownTableData(
      [
        List.generate(cols, (i) => 'Column ${i + 1}'),
        for (var r = 0; r < body; r++) List.filled(cols, ''),
      ],
      List.filled(cols, MarkdownTableAlign.left),
    );
  }
}

final RegExp _tableSeparatorCell = RegExp(r'^:?-+:?$');

/// Splits a table row on UNescaped `|`, unescaping `\|` back to `|` inside
/// cells. Symmetric with [serializeMarkdownTable] (which escapes `|`), so a
/// cell containing a literal pipe survives a parse → serialize round-trip.
List<String> _splitTableRow(String line) {
  var s = line.trim();
  if (s.startsWith('|')) s = s.substring(1);
  if (s.endsWith('|') && !s.endsWith(r'\|')) s = s.substring(0, s.length - 1);
  final cells = <String>[];
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (s[i] == r'\' && i + 1 < s.length && s[i + 1] == '|') {
      buf.write('|');
      i++; // skip the escaped pipe
    } else if (s[i] == '|') {
      cells.add(buf.toString().trim());
      buf.clear();
    } else {
      buf.write(s[i]);
    }
  }
  cells.add(buf.toString().trim());
  return cells;
}

bool _isTableSeparator(String line) {
  if (!line.contains('|') && !line.contains('-')) return false;
  final cells = _splitTableRow(line);
  if (cells.isEmpty) return false;
  return cells.every((c) => _tableSeparatorCell.hasMatch(c.replaceAll(' ', '')));
}

MarkdownTableAlign _alignOf(String separatorCell) {
  final c = separatorCell.trim();
  final left = c.startsWith(':');
  final right = c.endsWith(':');
  if (left && right) return MarkdownTableAlign.center;
  if (right) return MarkdownTableAlign.right;
  return MarkdownTableAlign.left;
}

List<String> _normalizeRow(List<String> cells, int columns) {
  if (cells.length == columns) return cells;
  if (cells.length > columns) return cells.sublist(0, columns);
  return [...cells, ...List.filled(columns - cells.length, '')];
}

/// Finds the GFM table whose lines contain [offset], or null if the caret isn't
/// inside a table. Returns the parsed data and the table's `[start, end]`
/// character range in [text].
///
/// Limitations (acceptable for MVP — both need a blank line, which GFM tables
/// want anyway): it does not track fenced code, so pipe lines inside a ``` block
/// could be mistaken for a table; and a pipe-bearing prose line directly above a
/// table (no blank line between) hides the table.
({MarkdownTableData table, int start, int end})? tableAtOffset(
    String text, int offset) {
  final lines = text.split('\n');
  final starts = <int>[];
  var acc = 0;
  for (final l in lines) {
    starts.add(acc);
    acc += l.length + 1;
  }

  final caret = offset.clamp(0, text.length);
  var cur = lines.length - 1;
  for (var i = 0; i < lines.length; i++) {
    if (caret <= starts[i] + lines[i].length) {
      cur = i;
      break;
    }
  }

  bool isRow(int i) => i >= 0 && i < lines.length && lines[i].contains('|');
  if (!isRow(cur)) return null;

  var top = cur;
  var bottom = cur;
  while (isRow(top - 1)) {
    top--;
  }
  while (isRow(bottom + 1)) {
    bottom++;
  }

  // A valid table needs a header, a separator on the 2nd line, and ≥1 body row.
  if (bottom - top < 2) return null;
  if (!_isTableSeparator(lines[top + 1])) return null;

  final header = _splitTableRow(lines[top]);
  final columns = header.length;
  if (columns == 0) return null;

  final sepCells = _splitTableRow(lines[top + 1]);
  final aligns = List.generate(
    columns,
    (i) => i < sepCells.length ? _alignOf(sepCells[i]) : MarkdownTableAlign.left,
  );

  final rows = <List<String>>[_normalizeRow(header, columns)];
  for (var i = top + 2; i <= bottom; i++) {
    rows.add(_normalizeRow(_splitTableRow(lines[i]), columns));
  }

  return (
    table: MarkdownTableData(rows, aligns),
    start: starts[top],
    end: starts[bottom] + lines[bottom].length,
  );
}

String _separatorFor(MarkdownTableAlign a) => switch (a) {
      MarkdownTableAlign.left => '---',
      MarkdownTableAlign.center => ':--:',
      MarkdownTableAlign.right => '---:',
    };

/// Serializes [table] to GFM markdown (header, alignment separator, body rows).
String serializeMarkdownTable(MarkdownTableData table) {
  String row(List<String> cells) =>
      '| ${_normalizeRow(cells, table.columns).map((c) => c.replaceAll('|', r'\|').trim()).join(' | ')} |';
  return [
    row(table.rows.first),
    '| ${table.aligns.map(_separatorFor).join(' | ')} |',
    for (final r in table.rows.skip(1)) row(r),
  ].join('\n');
}

/// A GFM table found in a document, with the data needed to render it inline:
/// the parsed [table] (header + body, no separator), the character range of
/// each DISPLAY row line ([rowRanges], header first), and the separator line's
/// range (drawn as zero-height so it disappears).
class TableRegion {
  const TableRegion({
    required this.start,
    required this.end,
    required this.table,
    required this.rowRanges,
    required this.separatorRange,
  });

  final int start;
  final int end;
  final MarkdownTableData table;
  final List<({int start, int end})> rowRanges;
  final ({int start, int end}) separatorRange;
}

final RegExp _tableFence = RegExp(r'^\s*(?:```|~~~)');

/// Finds every GFM table in [text] (a `|` header line immediately followed by a
/// separator line, then `|` body lines), skipping fenced code blocks. Used to
/// render tables inline and to hide their raw markdown.
List<TableRegion> findTableRegions(String text) {
  if (text.isEmpty) return const [];
  final lines = text.split('\n');
  final starts = <int>[];
  var acc = 0;
  for (final l in lines) {
    starts.add(acc);
    acc += l.length + 1;
  }
  ({int start, int end}) rangeOf(int i) =>
      (start: starts[i], end: starts[i] + lines[i].length);

  final result = <TableRegion>[];
  var inFence = false;
  var i = 0;
  while (i < lines.length) {
    if (_tableFence.hasMatch(lines[i])) {
      inFence = !inFence;
      i++;
      continue;
    }
    if (inFence) {
      i++;
      continue;
    }
    final isTable = lines[i].contains('|') &&
        i + 1 < lines.length &&
        _isTableSeparator(lines[i + 1]);
    if (!isTable) {
      i++;
      continue;
    }

    final headerIdx = i;
    final sepIdx = i + 1;
    var bottom = sepIdx;
    while (bottom + 1 < lines.length &&
        lines[bottom + 1].contains('|') &&
        !_tableFence.hasMatch(lines[bottom + 1])) {
      bottom++;
    }

    final header = _splitTableRow(lines[headerIdx]);
    final columns = header.length;
    if (columns > 0) {
      final sepCells = _splitTableRow(lines[sepIdx]);
      final aligns = List.generate(
        columns,
        (k) => k < sepCells.length ? _alignOf(sepCells[k]) : MarkdownTableAlign.left,
      );
      final rows = <List<String>>[_normalizeRow(header, columns)];
      final rowRanges = <({int start, int end})>[rangeOf(headerIdx)];
      for (var r = sepIdx + 1; r <= bottom; r++) {
        rows.add(_normalizeRow(_splitTableRow(lines[r]), columns));
        rowRanges.add(rangeOf(r));
      }
      result.add(TableRegion(
        start: starts[headerIdx],
        end: starts[bottom] + lines[bottom].length,
        table: MarkdownTableData(rows, aligns),
        rowRanges: rowRanges,
        separatorRange: rangeOf(sepIdx),
      ));
    }
    i = bottom + 1;
  }
  return result;
}

// ── <details> 접기 블록 ─────────────────────────────────────────────────────

final RegExp _detailsOpenRe = RegExp(r'^\s*<details( open)?>\s*$');
final RegExp _summaryLineRe = RegExp(r'^\s*<summary>.*</summary>\s*$');
final RegExp _detailsCloseRe = RegExp(r'^\s*</details>\s*$');

/// 에디터 텍스트에서 찾은 `<details>` 블록 하나. 형식(각 요소는 자기 줄):
///   `<details>` | `<details open>`
///   `<summary>제목</summary>`
///   ...본문...
///   `</details>`
/// 중첩은 지원하지 않고, 본문에 코드 fence가 있으면 블록을 무시한다.
class DetailsRegion {
  const DetailsRegion({
    required this.start,
    required this.end,
    required this.open,
    required this.detailsLineRange,
    required this.summaryLineRange,
    required this.bodyLineRanges,
    required this.closeLineRange,
  });

  /// `<details>` 줄 시작 오프셋 (inclusive).
  final int start;

  /// `</details>` 줄 끝 오프셋 (exclusive).
  final int end;

  /// `<details open>` 여부. 파일에 저장되는 펼침 상태다.
  final bool open;

  final ({int start, int end}) detailsLineRange;
  final ({int start, int end}) summaryLineRange;
  final List<({int start, int end})> bodyLineRanges;
  final ({int start, int end}) closeLineRange;
}

/// 모든 `<details>` 블록을 찾는다. fence 내부와 형식이 안 맞는 블록은 무시.
List<DetailsRegion> findDetailsRegions(String text) {
  if (text.isEmpty) return const [];
  final lines = text.split('\n');
  final starts = <int>[];
  var acc = 0;
  for (final l in lines) {
    starts.add(acc);
    acc += l.length + 1;
  }
  ({int start, int end}) rangeOf(int i) =>
      (start: starts[i], end: starts[i] + lines[i].length);

  final result = <DetailsRegion>[];
  var inFence = false;
  var i = 0;
  while (i < lines.length) {
    if (_fenceRe.hasMatch(lines[i])) {
      inFence = !inFence;
      i++;
      continue;
    }
    if (inFence) {
      i++;
      continue;
    }
    final openMatch = _detailsOpenRe.firstMatch(lines[i]);
    if (openMatch == null ||
        i + 1 >= lines.length ||
        !_summaryLineRe.hasMatch(lines[i + 1])) {
      i++;
      continue;
    }
    var close = -1;
    for (var j = i + 2; j < lines.length; j++) {
      if (_fenceRe.hasMatch(lines[j])) break; // 본문 fence → 블록 무효
      if (_detailsCloseRe.hasMatch(lines[j])) {
        close = j;
        break;
      }
    }
    if (close == -1) {
      i++;
      continue;
    }
    result.add(DetailsRegion(
      start: starts[i],
      end: starts[close] + lines[close].length,
      open: openMatch.group(1) != null,
      detailsLineRange: rangeOf(i),
      summaryLineRange: rangeOf(i + 1),
      bodyLineRanges: [for (var j = i + 2; j < close; j++) rangeOf(j)],
      closeLineRange: rangeOf(close),
    ));
    i = close + 1;
  }
  return result;
}

/// 줄 시작에서 `> `를 입력하면 `<details>` 스켈레톤으로 바꾼다. 인용문의 새
/// 문법은 `| `이므로 `>`는 details 생성 트리거로만 쓰인다. 이미 저장된
/// `> ` 줄(레거시 인용문)은 건드리지 않는다 — 새로 타이핑되는 경우만 반응.
class DetailsBlockInputFormatter extends TextInputFormatter {
  static const skeleton = '<details>\n<summary></summary>\n\n</details>';
  static final int _caretOffset = '<details>\n<summary>'.length;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final sel = newValue.selection;
    if (!sel.isValid || !sel.isCollapsed) return newValue;
    // 한 글자 삽입만 반응 (붙여넣기/IME 조합 제외).
    if (newValue.text.length != oldValue.text.length + 1) return newValue;
    final cursor = sel.baseOffset;
    final lineStart = _lineStartOf(newValue.text, cursor);
    final lineEnd = _lineEndOf(newValue.text, cursor);
    if (cursor != lineEnd) return newValue;
    if (newValue.text.substring(lineStart, lineEnd) != '> ') return newValue;

    final text = newValue.text.replaceRange(lineStart, lineEnd, skeleton);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: lineStart + _caretOffset),
    );
  }
}

// ── 인라인 이미지 (`<img>` 한 줄 태그) ────────────────────────────────────────

final RegExp _imgLineRe = RegExp(
    r'^\s*<img\s+src="([^"]+)"\s+width="(\d+)"\s+height="(\d+)"\s*/?>\s*$');

/// 에디터 텍스트에서 찾은 한 줄짜리 `<img>` 태그. width/height를 둘 다
/// 저장하는 이유: 이미지 바이트를 받기 전에 줄 높이를 예약해야 한다.
class ImageRegion {
  const ImageRegion({
    required this.start,
    required this.end,
    required this.src,
    required this.width,
    required this.height,
  });

  /// 줄 시작 오프셋 (inclusive).
  final int start;

  /// 줄 끝 오프셋 (exclusive).
  final int end;

  final String src;
  final int width;
  final int height;
}

/// 한 줄 `<img src width height>` 태그를 모두 찾는다. fence 내부는 무시.
/// 형식이 깨진 태그는 매칭되지 않아 원문 텍스트로 노출된다(자가 복구).
List<ImageRegion> findImageRegions(String text) {
  if (text.isEmpty) return const [];
  final lines = text.split('\n');
  final result = <ImageRegion>[];
  var offset = 0;
  var inFence = false;
  for (final line in lines) {
    if (_fenceRe.hasMatch(line)) {
      inFence = !inFence;
    } else if (!inFence) {
      final m = _imgLineRe.firstMatch(line);
      if (m != null) {
        result.add(ImageRegion(
          start: offset,
          end: offset + line.length,
          src: m.group(1)!,
          width: int.parse(m.group(2)!),
          height: int.parse(m.group(3)!),
        ));
      }
    }
    offset += line.length + 1;
  }
  return result;
}

/// 이미지 태그 직렬화. [_imgLineRe] 파서와 왕복 대칭.
String serializeImageTag(String src, int width, int height) =>
    '<img src="$src" width="$width" height="$height">';
