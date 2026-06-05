import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/services/markdown_editing.dart';

/// Simulates pressing Enter at [cursor] in [text]: returns the (old, new)
/// [TextEditingValue] pair the text input pipeline would produce for a single
/// '\n' insertion at a collapsed cursor.
({TextEditingValue oldV, TextEditingValue newV}) _enterAt(String text, int cursor) {
  final oldV = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: cursor),
  );
  final newText = '${text.substring(0, cursor)}\n${text.substring(cursor)}';
  final newV = TextEditingValue(
    text: newText,
    selection: TextSelection.collapsed(offset: cursor + 1),
  );
  return (oldV: oldV, newV: newV);
}

TextEditingValue _applyEnter(String text, int cursor) {
  final p = _enterAt(text, cursor);
  return MarkdownListInputFormatter().formatEditUpdate(p.oldV, p.newV);
}

TextEditingValue _value(String text, int cursor) {
  return TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: cursor),
  );
}

void main() {
  group('MarkdownListInputFormatter', () {
    test('continues an unordered list with the same bullet', () {
      final r = _applyEnter('- a', 3);
      expect(r.text, '- a\n- ');
      expect(r.selection.baseOffset, 6);
    });

    test('continues an ordered list with the incremented number', () {
      final r = _applyEnter('1. a', 4);
      expect(r.text, '1. a\n2. ');
      expect(r.selection.baseOffset, 8);
    });

    test('preserves the ) delimiter when continuing an ordered list', () {
      final r = _applyEnter('1) a', 4);
      expect(r.text, '1) a\n2) ');
    });

    test('continues a task list with an unchecked box', () {
      final r = _applyEnter('- [ ] a', 7);
      expect(r.text, '- [ ] a\n- [ ] ');
      expect(r.selection.baseOffset, 14);
    });

    test('exits the list when Enter is pressed on an empty bullet', () {
      final r = _applyEnter('- ', 2);
      expect(r.text, '');
      expect(r.selection.baseOffset, 0);
    });

    test('exits the list when Enter is pressed on an empty ordered item', () {
      final r = _applyEnter('1. ', 3);
      expect(r.text, '');
      expect(r.selection.baseOffset, 0);
    });

    test('passes through a normal newline on a non-list line', () {
      final r = _applyEnter('hello', 5);
      expect(r.text, 'hello\n');
      expect(r.selection.baseOffset, 6);
    });

    test('passes through edits that are not a single newline insertion', () {
      final oldV = _value('- a', 3);
      final newV = _value('- a\nXY', 6);
      final r = MarkdownListInputFormatter().formatEditUpdate(oldV, newV);
      expect(r.text, '- a\nXY');
    });

    test('splits the line and continues when Enter is pressed mid-item', () {
      final r = _applyEnter('- helloworld', 7);
      expect(r.text, '- hello\n- world');
      expect(r.selection.baseOffset, 10);
    });

    test('preserves indentation when continuing', () {
      final r = _applyEnter('  - a', 5);
      expect(r.text, '  - a\n  - ');
      expect(r.selection.baseOffset, 10);
    });
  });

  group('renumberOrderedListAtCursor', () {
    test('renumbers a block to a consecutive sequence', () {
      final r = renumberOrderedListAtCursor(_value('1. a\n3. b\n4. c', 6));
      expect(r.text, '1. a\n2. b\n3. c');
    });

    test('preserves the first item number as the base', () {
      final r = renumberOrderedListAtCursor(_value('3. a\n9. b', 1));
      expect(r.text, '3. a\n4. b');
    });

    test('preserves indent, delimiter and spacing', () {
      final r = renumberOrderedListAtCursor(_value('  2)  x\n  5)  y', 2));
      expect(r.text, '  2)  x\n  3)  y');
    });

    test('is a no-op when the cursor is not on an ordered item', () {
      final v = _value('hello\nworld', 0);
      final r = renumberOrderedListAtCursor(v);
      expect(r.text, 'hello\nworld');
    });

    test('stops the block at a blank line', () {
      final r = renumberOrderedListAtCursor(_value('3. a\n7. b\n\n9. c', 0));
      expect(r.text, '3. a\n4. b\n\n9. c');
    });
  });

  group('buildMarkdownTable', () {
    test('builds a 2x2 GFM table skeleton', () {
      expect(
        buildMarkdownTable(columns: 2, rows: 2),
        '| Column 1 | Column 2 |\n| --- | --- |\n|  |  |\n|  |  |',
      );
    });

    test('omits body rows when rows is 0', () {
      expect(
        buildMarkdownTable(columns: 3, rows: 0),
        '| Column 1 | Column 2 | Column 3 |\n| --- | --- | --- |',
      );
    });

    test('clamps columns to at least 1', () {
      expect(
        buildMarkdownTable(columns: 0, rows: 1),
        '| Column 1 |\n| --- |\n|  |',
      );
    });
  });
}
