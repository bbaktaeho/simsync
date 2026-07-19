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

  group('markdown tables', () {
    test('a blank table serializes to a GFM skeleton', () {
      final md =
          serializeMarkdownTable(MarkdownTableData.blank(columns: 2, bodyRows: 2));
      expect(md, '| Column 1 | Column 2 |\n| --- | --- |\n|  |  |\n|  |  |');
    });

    test('serializes per-column alignment', () {
      final data = MarkdownTableData(
        [
          ['Name', 'Score'],
          ['Alice', '90'],
        ],
        [MarkdownTableAlign.left, MarkdownTableAlign.right],
      );
      expect(serializeMarkdownTable(data),
          '| Name | Score |\n| --- | ---: |\n| Alice | 90 |');
    });

    test('tableAtOffset parses the table containing the caret', () {
      const text =
          'intro\n\n| A | B |\n| :-- | --: |\n| 1 | 2 |\n| 3 | 4 |\n\nafter';
      final found = tableAtOffset(text, text.indexOf('| 1'));
      expect(found, isNotNull);
      expect(found!.table.columns, 2);
      expect(found.table.rows.length, 3); // header + 2 body rows
      expect(found.table.rows[0], ['A', 'B']);
      expect(found.table.rows[2], ['3', '4']);
      expect(found.table.aligns,
          [MarkdownTableAlign.left, MarkdownTableAlign.right]);
      expect(text.substring(found.start, found.end),
          '| A | B |\n| :-- | --: |\n| 1 | 2 |\n| 3 | 4 |');
    });

    test('tableAtOffset returns null in prose that merely contains a pipe', () {
      expect(tableAtOffset('just prose with a | pipe', 5), isNull);
    });

    test('tableAtOffset pads ragged rows to the header width', () {
      const text = '| A | B | C |\n| --- | --- | --- |\n| 1 | 2 |';
      final found = tableAtOffset(text, 0);
      expect(found, isNotNull);
      expect(found!.table.rows[1], ['1', '2', '']);
    });

    test('parse → serialize round-trips a simple table', () {
      const text = '| H1 | H2 |\n| --- | --- |\n| a | b |';
      final found = tableAtOffset(text, 0)!;
      expect(serializeMarkdownTable(found.table), text);
    });

    test('round-trips a cell that contains a literal pipe', () {
      final once = serializeMarkdownTable(
        MarkdownTableData(
          [
            ['a|b', 'h2'],
            ['c', 'd'],
          ],
          [MarkdownTableAlign.left, MarkdownTableAlign.left],
        ),
      );
      final found = tableAtOffset(once, 0)!;
      expect(found.table.columns, 2); // not split into 3 by the escaped pipe
      expect(found.table.rows[0], ['a|b', 'h2']);
      expect(serializeMarkdownTable(found.table), once); // stable across edits
    });

    test('findTableRegions locates a table with header + body row ranges', () {
      const text = '| H1 | H2 |\n| --- | --- |\n| a | b |';
      final regions = findTableRegions(text);
      expect(regions, hasLength(1));
      final t = regions.first;
      expect(t.start, 0);
      expect(t.end, text.length);
      expect(t.table.rows, [
        ['H1', 'H2'],
        ['a', 'b'],
      ]);
      // rowRanges cover the header + body lines, NOT the separator.
      expect(t.rowRanges, hasLength(2));
      expect(text.substring(t.rowRanges[0].start, t.rowRanges[0].end),
          '| H1 | H2 |');
      expect(text.substring(t.rowRanges[1].start, t.rowRanges[1].end),
          '| a | b |');
      expect(text.substring(t.separatorRange.start, t.separatorRange.end),
          '| --- | --- |');
    });

    test('findTableRegions skips a pipe table inside a fenced code block', () {
      const text = '```\n| not | a |\n| --- | --- |\n| real | table |\n```';
      expect(findTableRegions(text), isEmpty);
    });

    test('findTableRegions ignores a pipe line with no separator', () {
      expect(findTableRegions('| a | b |\n| c | d |'), isEmpty);
    });

    test('findTableRegions finds a table offset into the document', () {
      const text = 'intro\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\nafter';
      final regions = findTableRegions(text);
      expect(regions, hasLength(1));
      expect(text.substring(regions.first.start, regions.first.end),
          '| A | B |\n| --- | --- |\n| 1 | 2 |');
      expect(regions.first.table.rows[1], ['1', '2']);
    });

    test('findTableRegions finds two separate tables', () {
      const text =
          '| A |\n| --- |\n| 1 |\n\ntext\n\n| B |\n| --- |\n| 2 |';
      final regions = findTableRegions(text);
      expect(regions, hasLength(2));
      expect(regions[0].table.rows[0], ['A']);
      expect(regions[1].table.rows[0], ['B']);
    });
  });

  group('code fence exit on Enter', () {
    test('empty line in an unterminated block closes it and drops below', () {
      // '```\ncode\n' with the caret on the trailing empty line (offset 9).
      final result = _applyEnter('```\ncode\n', 9);
      expect(result.text, '```\ncode\n```\n');
      expect(result.selection.baseOffset, 13); // on the new line below the close
    });

    test('uses the same fence marker the block was opened with', () {
      final result = _applyEnter('~~~\ncode\n', 9);
      expect(result.text, '~~~\ncode\n~~~\n');
    });

    test('a non-empty code line just gets a normal newline', () {
      final result = _applyEnter('```\ncode', 8);
      expect(result.text, '```\ncode\n');
      expect(result.selection.baseOffset, 9);
    });

    test('an already-closed block is left alone', () {
      // Caret on the empty line between the code and the closing fence.
      final result = _applyEnter('```\ncode\n\n```', 9);
      expect(result.text, '```\ncode\n\n\n```'); // plain newline, not re-closed
    });

    test('a plain empty line outside any block is unaffected', () {
      final result = _applyEnter('hello\n', 6);
      expect(result.text, 'hello\n\n');
    });
  });

  group('findDetailsRegions', () {
    test('닫힌 블록을 파싱한다', () {
      const text = '<details>\n<summary>제목</summary>\n\n내용\n</details>';
      final regions = findDetailsRegions(text);
      expect(regions, hasLength(1));
      final d = regions.first;
      expect(d.open, isFalse);
      expect(d.start, 0);
      expect(d.end, text.length);
      expect(text.substring(d.summaryLineRange.start, d.summaryLineRange.end),
          '<summary>제목</summary>');
      expect(d.bodyLineRanges, hasLength(2)); // 빈 줄 + '내용'
    });

    test('open 속성을 읽는다', () {
      const text = '<details open>\n<summary>t</summary>\nbody\n</details>';
      expect(findDetailsRegions(text).single.open, isTrue);
    });

    test('summary 줄이 없으면 무시한다', () {
      const text = '<details>\nno summary\n</details>';
      expect(findDetailsRegions(text), isEmpty);
    });

    test('닫는 태그가 없으면 무시한다', () {
      const text = '<details>\n<summary>t</summary>\nbody';
      expect(findDetailsRegions(text), isEmpty);
    });

    test('코드 fence 안의 details는 무시한다', () {
      const text = '```\n<details>\n<summary>t</summary>\n</details>\n```';
      expect(findDetailsRegions(text), isEmpty);
    });

    test('본문에 fence가 있으면 그 블록은 무시한다', () {
      const text =
          '<details>\n<summary>t</summary>\n```\ncode\n```\n</details>';
      expect(findDetailsRegions(text), isEmpty);
    });
  });

  group('DetailsBlockInputFormatter', () {
    TextEditingValue apply(String oldText, int cursor, String typed) {
      final oldValue = TextEditingValue(
        text: oldText,
        selection: TextSelection.collapsed(offset: cursor),
      );
      final newText = oldText.replaceRange(cursor, cursor, typed);
      final newValue = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: cursor + typed.length),
      );
      return DetailsBlockInputFormatter().formatEditUpdate(oldValue, newValue);
    }

    test('줄 시작 "> " 입력이 details 스켈레톤으로 바뀐다 (본문 들여쓰기 포함)', () {
      final result = apply('>', 1, ' ');
      expect(result.text, '<details>\n<summary></summary>\n  \n</details>');
      expect(result.selection.baseOffset, '<details>\n<summary>'.length);
    });

    test('앞 줄이 있어도 동작한다', () {
      final result = apply('line1\n>', 7, ' ');
      expect(
          result.text, 'line1\n<details>\n<summary></summary>\n  \n</details>');
    });

    test('summary 줄에서 Enter를 치면 본문 들여쓰기가 이어진다', () {
      const text = '<details>\n<summary>t</summary>\n  \n</details>';
      final cursor = text.indexOf('</summary>') + '</summary>'.length;
      final result = apply(text, cursor, '\n');
      expect(result.text,
          '<details>\n<summary>t</summary>\n  \n  \n</details>');
      expect(result.selection.baseOffset, cursor + 1 + 2);
    });

    test('본문 줄에서 Enter를 치면 들여쓰기가 이어진다', () {
      const text = '<details>\n<summary>t</summary>\n  abc\n</details>';
      final cursor = text.indexOf('abc') + 3;
      final result = apply(text, cursor, '\n');
      expect(result.text,
          '<details>\n<summary>t</summary>\n  abc\n  \n</details>');
      expect(result.selection.baseOffset, cursor + 1 + 2);
    });

    test('들여쓰기만 있는 빈 본문 줄에서의 Enter는 이어가지 않는다 (탈출구)', () {
      const text = '<details>\n<summary>t</summary>\n  \n</details>';
      final cursor = text.indexOf('  \n</details>') + 2;
      final result = apply(text, cursor, '\n');
      expect(result.text,
          '<details>\n<summary>t</summary>\n  \n\n</details>');
    });

    test('details 밖에서의 Enter는 건드리지 않는다', () {
      final result = apply('plain', 5, '\n');
      expect(result.text, 'plain\n');
    });

    test('줄 중간의 "> "는 건드리지 않는다', () {
      final result = apply('a >', 3, ' ');
      expect(result.text, 'a > ');
    });

    test('붙여넣기(여러 글자 삽입)는 건드리지 않는다', () {
      final oldValue = const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
      const newValue = TextEditingValue(
        text: '> ',
        selection: TextSelection.collapsed(offset: 2),
      );
      final result = DetailsBlockInputFormatter().formatEditUpdate(oldValue, newValue);
      expect(result.text, '> ');
    });
  });

  group('findImageRegions', () {
    test('한 줄 img 태그를 파싱한다', () {
      const text = 'before\n<img src="assets/a.png" width="300" height="200">\nafter';
      final regions = findImageRegions(text);
      expect(regions, hasLength(1));
      final r = regions.first;
      expect(r.src, 'assets/a.png');
      expect(r.width, 300);
      expect(r.height, 200);
      expect(text.substring(r.start, r.end),
          '<img src="assets/a.png" width="300" height="200">');
    });

    test('serializeImageTag는 파서와 왕복 대칭이다', () {
      final tag = serializeImageTag('assets/a.png', 300, 200);
      final regions = findImageRegions(tag);
      expect(regions.single.src, 'assets/a.png');
      expect(regions.single.width, 300);
      expect(regions.single.height, 200);
    });

    test('fence 안의 img 태그는 무시한다', () {
      const text = '```\n<img src="a.png" width="1" height="1">\n```';
      expect(findImageRegions(text), isEmpty);
    });

    test('속성이 빠진 태그는 무시한다 (원문 노출 = 자가 복구)', () {
      const text = '<img src="a.png" width="300">';
      expect(findImageRegions(text), isEmpty);
    });
  });
}
