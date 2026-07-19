import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/services/markdown_editing.dart';
import 'package:simsync/widgets/editor_block_decorations.dart';

void main() {
  group('parseEditorBlockRegions', () {
    test('wraps a fenced code block\'s content (not the fence lines)', () {
      const text = 'before\n```go\nx := 1\n```\nafter';
      final regions = parseEditorBlockRegions(text);
      expect(regions.length, 1);
      expect(regions.first.kind, EditorBlockKind.code);
      expect(text.substring(regions.first.start, regions.first.end), 'x := 1');
    });

    test('an empty code block falls back to the fence line', () {
      const text = '```\n```';
      final regions = parseEditorBlockRegions(text);
      expect(regions.length, 1);
      expect(regions.first.kind, EditorBlockKind.code);
    });

    test('finds a --- thematic break', () {
      const text = 'a\n---\nb';
      final regions = parseEditorBlockRegions(text);
      expect(regions.length, 1);
      expect(regions.first.kind, EditorBlockKind.rule);
      expect(text.substring(regions.first.start, regions.first.end), '---');
    });

    test('groups consecutive blockquote lines into one region', () {
      const text = 'intro\n> quote one\n> quote two\nafter';
      final regions = parseEditorBlockRegions(text);
      expect(regions.length, 1);
      expect(regions.first.kind, EditorBlockKind.quote);
      expect(text.substring(regions.first.start, regions.first.end),
          '> quote one\n> quote two');
    });

    test('a blank line ends a blockquote', () {
      const text = '> a\n\n> b';
      final regions = parseEditorBlockRegions(text);
      expect(regions.where((r) => r.kind == EditorBlockKind.quote).length, 2);
    });

    test('an unterminated fence wraps content to the end of text', () {
      const text = 'a\n```\ncode';
      final regions = parseEditorBlockRegions(text);
      expect(regions.length, 1);
      expect(regions.first.kind, EditorBlockKind.code);
      expect(text.substring(regions.first.start, regions.first.end), 'code');
    });

    test('--- and > inside a fence are part of the code block', () {
      const text = '```\n---\n> not a quote\n```';
      final regions = parseEditorBlockRegions(text);
      expect(regions.length, 1);
      expect(regions.single.kind, EditorBlockKind.code);
    });

    test('handles a mix of code, rules and quotes', () {
      const text = '# h\n---\n```js\n1\n```\n***\n> q\ntext';
      final regions = parseEditorBlockRegions(text);
      expect(regions.where((r) => r.kind == EditorBlockKind.code).length, 1);
      expect(regions.where((r) => r.kind == EditorBlockKind.rule).length, 2);
      expect(regions.where((r) => r.kind == EditorBlockKind.quote).length, 1);
    });

    test('empty text yields no regions', () {
      expect(parseEditorBlockRegions(''), isEmpty);
    });
  });

  group('pipe quote regions', () {
    test('| 줄이 quote 영역으로 잡힌다', () {
      const text = '| a\n| b\nplain';
      final regions = parseEditorBlockRegions(text);
      expect(regions, [
        const EditorBlockRegion(start: 0, end: 7, kind: EditorBlockKind.quote),
      ]);
    });

    test('filterEditorRegions는 테이블과 겹치는 quote 영역을 버린다', () {
      const text = '| h1 | h2 |\n| --- | --- |\n| a | b |';
      final regions = parseEditorBlockRegions(text);
      final tables = findTableRegions(text);
      final filtered = filterEditorRegions(regions, tables, const []);
      expect(filtered.where((r) => r.kind == EditorBlockKind.quote), isEmpty);
    });

    test('filterEditorRegions는 테이블 구분선의 rule 영역도 버린다 (기존 동작 이전)', () {
      const text = 'x | y\n---\n| a | b |'; // 파이프 없는 구분선 케이스는 기존 로직 유지 확인용
      final regions = parseEditorBlockRegions(text);
      final tables = findTableRegions(text);
      final filtered = filterEditorRegions(regions, tables, const []);
      for (final t in tables) {
        expect(
          filtered.any((r) => r.kind == EditorBlockKind.rule && r.start == t.separatorRange.start),
          isFalse,
        );
      }
    });

    test('filterEditorRegions는 닫힌 details 안의 rule/quote 장식을 버린다', () {
      const text =
          '<details>\n<summary>t</summary>\n---\n| q\n</details>\nplain\n---';
      final regions = parseEditorBlockRegions(text);
      final tables = findTableRegions(text);
      final details = findDetailsRegions(text);
      final filtered = filterEditorRegions(regions, tables, details);
      // 닫힌 블록 안의 --- rule과 | quote는 걸러진다.
      final insideRules = filtered.where((r) =>
          r.kind == EditorBlockKind.rule && r.end < text.indexOf('plain'));
      final insideQuotes =
          filtered.where((r) => r.kind == EditorBlockKind.quote);
      expect(insideRules, isEmpty);
      expect(insideQuotes, isEmpty);
      // 블록 밖 마지막 --- rule은 남는다.
      expect(
        filtered.where((r) => r.kind == EditorBlockKind.rule).length,
        1,
      );
    });

    test('열린 details 안의 장식은 유지된다', () {
      const text = '<details open>\n<summary>t</summary>\n---\n</details>';
      final regions = parseEditorBlockRegions(text);
      final filtered = filterEditorRegions(
          regions, const [], findDetailsRegions(text));
      expect(
          filtered.where((r) => r.kind == EditorBlockKind.rule), hasLength(1));
    });
  });
}
