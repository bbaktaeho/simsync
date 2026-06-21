import 'dart:ui' as ui;

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

  group('EditorBlockDecorationPainter table rendering', () {
    EditorBlockDecorationPainter buildPainter(InlineSpan span, String text) =>
        EditorBlockDecorationPainter(
          span: span,
          regions: const [],
          tables: findTableRegions(text),
          strutStyle: StrutStyle.fromTextStyle(const TextStyle(fontSize: 14)),
          textScaler: TextScaler.noScaling,
          scrollController: ScrollController(),
          codeBackground: const Color(0xFFEEEEEE),
          codeBorder: const Color(0xFFCCCCCC),
          ruleColor: const Color(0xFFCCCCCC),
          quoteBar: const Color(0xFF999999),
          tableFill: const Color(0xFFFFFFFF),
          tableHeaderFill: const Color(0xFFEFEFEF),
          tableBorder: const Color(0xFFCCCCCC),
          tableTextStyle: const TextStyle(fontSize: 14, color: Color(0xFF111111)),
          tableHeaderStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111111)),
        );

    testWidgets('measures table rows and paints a grid without error', (
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

      final painter = buildPainter(span, text);
      final recorder = ui.PictureRecorder();
      // Lays out the span, measures each row's box, draws fills/grid/cell text.
      // A throw here (bad index, null deref, layout error) fails the test.
      painter.paint(Canvas(recorder), const Size(420, 240));
      recorder.endRecording().dispose();

      // A different table count must trigger a repaint.
      expect(painter.shouldRepaint(buildPainter(span, 'no table here')), isTrue);
    });
  });
}
