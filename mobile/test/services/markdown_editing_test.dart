import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync_mobile/services/markdown_editing.dart';

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

    test('줄 시작 "> " 입력이 details 스켈레톤으로 바뀐다', () {
      final result = apply('>', 1, ' ');
      expect(result.text, '<details>\n<summary></summary>\n\n</details>');
      expect(result.selection.baseOffset, '<details>\n<summary>'.length);
    });

    test('앞 줄이 있어도 동작한다', () {
      final result = apply('line1\n>', 7, ' ');
      expect(result.text, 'line1\n<details>\n<summary></summary>\n\n</details>');
    });

    test('details 안에서의 Enter는 자동 들여쓰기를 하지 않는다', () {
      // v0.2.1의 자동 2칸 들여쓰기는 원문 공백이 그대로 보여 제거됨.
      const text = '<details>\n<summary>t</summary>\nabc\n</details>';
      final cursor = text.indexOf('abc') + 3;
      final result = apply(text, cursor, '\n');
      expect(result.text,
          '<details>\n<summary>t</summary>\nabc\n\n</details>');
      expect(result.selection.baseOffset, cursor + 1);
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

  group('findCheckboxRegions', () {
    test('대괄호 세 글자 범위와 체크 상태를 돌려준다', () {
      const text = '- [ ] todo\n- [x] done';
      final regions = findCheckboxRegions(text);
      expect(regions.length, 2);
      expect(text.substring(regions[0].start, regions[0].end), '[ ]');
      expect(regions[0].checked, isFalse);
      expect(text.substring(regions[1].start, regions[1].end), '[x]');
      expect(regions[1].checked, isTrue);
      expect(text[regions[1].markOffset], 'x');
    });

    test('들여쓴 항목과 다른 불릿도 찾는다', () {
      const text = '- a\n  * [X] nested';
      final r = findCheckboxRegions(text).single;
      expect(text.substring(r.start, r.end), '[X]');
      expect(r.checked, isTrue);
    });

    test('닫는 대괄호 뒤 공백이 없으면 체크박스가 아니다', () {
      expect(findCheckboxRegions('- [ ]'), isEmpty);
    });

    test('fence 안은 무시한다', () {
      expect(findCheckboxRegions('```\n- [ ] todo\n```'), isEmpty);
    });
  });

  group('CheckboxShorthandInputFormatter', () {
    // `]`를 마지막에 친 상황을 만든다 (한 글자 삽입).
    TextEditingValue typeClose(String before) {
      final oldV = _value('$before[', before.length + 1);
      final newText = '$before[]';
      final newV = _value(newText, newText.length);
      return CheckboxShorthandInputFormatter().formatEditUpdate(oldV, newV);
    }

    test('빈 줄의 []는 - [ ] 로 펼쳐지고 캐럿이 뒤에 선다', () {
      final r = typeClose('');
      expect(r.text, '- [ ] ');
      expect(r.selection.baseOffset, 6);
    });

    test('이미 있는 불릿은 그대로 쓴다', () {
      expect(typeClose('- ').text, '- [ ] ');
      expect(typeClose('* ').text, '* [ ] ');
    });

    test('들여쓰기를 유지한다', () {
      final r = typeClose('  ');
      expect(r.text, '  - [ ] ');
      expect(r.selection.baseOffset, 8);
    });

    test('앞 줄이 있어도 그 줄만 바꾼다', () {
      final oldV = _value('memo\n[', 6);
      final newV = _value('memo\n[]', 7);
      final r = CheckboxShorthandInputFormatter().formatEditUpdate(oldV, newV);
      expect(r.text, 'memo\n- [ ] ');
      expect(r.selection.baseOffset, 11);
    });

    test('문장 중간의 대괄호는 건드리지 않는다 (링크 입력)', () {
      final oldV = _value('see [', 5);
      final newV = _value('see []', 6);
      expect(
          CheckboxShorthandInputFormatter().formatEditUpdate(oldV, newV).text,
          'see []');
    });

    test('줄 끝이 아니면 반응하지 않는다', () {
      final oldV = _value('[tail', 1);
      final newV = _value('[]tail', 2);
      expect(
          CheckboxShorthandInputFormatter().formatEditUpdate(oldV, newV).text,
          '[]tail');
    });

    test('두 글자가 한 번에 들어와도 펼친다 (한글 IME 경로)', () {
      // 실제 앱에서 재현된 케이스: IME가 조합 커밋과 괄호를 한 번에 보낸다.
      final oldV = _value('', 0);
      final newV = _value('[]', 2);
      expect(
          CheckboxShorthandInputFormatter().formatEditUpdate(oldV, newV).text,
          '- [ ] ');
    });

    test('텍스트가 그대로면(커서 이동 등) 건드리지 않는다', () {
      final v = _value('[]', 2);
      expect(CheckboxShorthandInputFormatter().formatEditUpdate(v, v).text, '[]');
    });
  });

  group('indentListSelection', () {
    test('캐럿이 줄 어디에 있든 줄 머리를 2칸 들여쓴다', () {
      // "- a\n- " 의 마지막(= `- ` 우측) 캐럿.
      final r = indentListSelection(_value('- a\n- ', 6), outdent: false)!;
      expect(r.text, '- a\n  - ');
      expect(r.selection.baseOffset, 8);
    });

    test('줄 중간 캐럿도 같은 글자를 계속 가리킨다', () {
      final r = indentListSelection(_value('- abc', 3), outdent: false)!;
      expect(r.text, '  - abc');
      expect(r.selection.baseOffset, 5);
    });

    test('Shift+Tab은 한 단계 되돌린다', () {
      final r = indentListSelection(_value('  - a', 5), outdent: true)!;
      expect(r.text, '- a');
      expect(r.selection.baseOffset, 3);
    });

    test('지워진 들여쓰기 안의 캐럿은 줄 머리로 당겨진다', () {
      final r = indentListSelection(_value('  - a', 1), outdent: true)!;
      expect(r.text, '- a');
      expect(r.selection.baseOffset, 0);
    });

    test('더 뺄 들여쓰기가 없으면 그대로 돌려준다 (키는 소비)', () {
      final value = _value('- a', 3);
      expect(indentListSelection(value, outdent: true), value);
    });

    test('리스트가 아닌 줄은 null (기본 Tab 동작 유지)', () {
      expect(indentListSelection(_value('plain', 3), outdent: false), isNull);
    });

    test('체크박스 항목도 들여쓴다', () {
      final r = indentListSelection(_value('- [ ] todo', 6), outdent: false)!;
      expect(r.text, '  - [ ] todo');
    });

    test('선택이 걸친 줄을 모두 들여쓰고 선택 범위를 유지한다', () {
      const text = '- a\n- b\n- c';
      final r = indentListSelection(
        const TextEditingValue(
          text: text,
          selection: TextSelection(baseOffset: 2, extentOffset: 6),
        ),
        outdent: false,
      )!;
      expect(r.text, '  - a\n  - b\n- c');
      expect(r.selection.baseOffset, 4);
      expect(r.selection.extentOffset, 10);
    });

    test('다음 줄 머리에서 끝나는 선택은 그 줄을 건드리지 않는다', () {
      const text = '- a\n- b';
      final r = indentListSelection(
        const TextEditingValue(
          text: text,
          selection: TextSelection(baseOffset: 0, extentOffset: 4),
        ),
        outdent: false,
      )!;
      expect(r.text, '  - a\n- b');
    });
  });
}
