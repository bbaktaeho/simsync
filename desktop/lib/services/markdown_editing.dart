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

// ── Table skeleton ──────────────────────────────────────────────────────────

/// Builds a GitHub-flavored markdown table skeleton with [columns] columns and
/// [rows] empty data rows (plus the header and separator rows).
String buildMarkdownTable({required int columns, required int rows}) {
  final cols = columns < 1 ? 1 : columns;
  final dataRows = rows < 0 ? 0 : rows;

  final header =
      '| ${List.generate(cols, (i) => 'Column ${i + 1}').join(' | ')} |';
  final separator = '| ${List.generate(cols, (_) => '---').join(' | ')} |';
  final body = List.generate(
    dataRows,
    (_) => '| ${List.generate(cols, (_) => '').join(' | ')} |',
  );

  return [header, separator, ...body].join('\n');
}
