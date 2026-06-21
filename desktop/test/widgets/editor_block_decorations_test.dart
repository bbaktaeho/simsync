import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/services/markdown_editing.dart';
import 'package:simsync/theme/app_colors.dart';
import 'package:simsync/widgets/editor_block_decorations.dart';
import 'package:simsync/widgets/markdown_editing_controller.dart';

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

  group('measureTableRegions', () {
    testWidgets('returns one vertical extent per table, ordered by position', (
      tester,
    ) async {
      const text =
          'intro\n\n| Name | Score |\n| :-- | --: |\n| Alice | 90 |\n| Bob | 7 |';
      final controller = MarkdownEditingController(text: text);
      late InlineSpan span;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColorsExtension.light]),
          home: Builder(builder: (context) {
            span =
                controller.buildTextSpan(context: context, withComposing: false);
            return const SizedBox();
          }),
        ),
      );

      final measured = measureTableRegions(
        span,
        findTableRegions(text),
        StrutStyle.fromTextStyle(const TextStyle(fontSize: 14)),
        TextScaler.noScaling,
        420,
      );
      expect(measured, hasLength(1));
      // The table sits below the 'intro' prose, so its top is positive, and it
      // spans a real (positive) height covering its rows.
      expect(measured.first.top, greaterThan(0));
      expect(measured.first.bottom, greaterThan(measured.first.top));
      expect(measured.first.table.table.columns, 2);
    });

    test('returns empty for text with no tables', () {
      expect(
        measureTableRegions(const TextSpan(text: 'no table'), const [],
            const StrutStyle(), TextScaler.noScaling, 400),
        isEmpty,
      );
    });
  });
}
