import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/theme/app_colors.dart';
import 'package:simsync/widgets/markdown_editing_controller.dart';

/// Flattens a span tree into (text, style) pairs for inspection.
List<(String, TextStyle?)> _flatten(InlineSpan root) {
  final out = <(String, TextStyle?)>[];
  void walk(InlineSpan span) {
    if (span is TextSpan) {
      if (span.text != null) out.add((span.text!, span.style));
      for (final child in span.children ?? const <InlineSpan>[]) {
        walk(child);
      }
    }
  }

  walk(root);
  return out;
}

Future<TextSpan> _build(WidgetTester tester, String text) async {
  late TextSpan span;
  final controller = MarkdownEditingController(text: text);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: const [AppColorsExtension.light]),
      home: Builder(
        builder: (context) {
          span = controller.buildTextSpan(
            context: context,
            withComposing: false,
          );
          return const SizedBox();
        },
      ),
    ),
  );
  return span;
}

void main() {
  testWidgets('preserves the exact text for arbitrary markdown', (tester) async {
    const inputs = [
      '',
      'plain text',
      '# Heading',
      '## Sub heading with **bold**',
      'Some **bold** and *italic* and `code` and ~~strike~~ together',
      '- bullet one\n- bullet two',
      '1. first\n2. second',
      '- [ ] todo\n- [x] done',
      '> a quote with *emphasis*',
      '```dart\nvoid main() {}\n```',
      'unterminated **bold and *italic',
      'mixed __underscore bold__ and _underscore italic_',
      'trailing spaces and \nblank lines\n\n\nend',
      '###### deep heading',
      'inline `**not bold inside code**` stays code',
      '한국어 **굵게** 그리고 *기울임*',
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColorsExtension.light]),
        home: Builder(
          builder: (context) {
            for (final input in inputs) {
              final controller = MarkdownEditingController(text: input);
              final span = controller.buildTextSpan(
                context: context,
                withComposing: false,
              );
              expect(span.toPlainText(), input,
                  reason: 'character mismatch for: ${input.replaceAll('\n', '\\n')}');
            }
            return const SizedBox();
          },
        ),
      ),
    );
  });

  testWidgets('headings render larger than body text', (tester) async {
    final span = await _build(tester, '# Title');
    final pairs = _flatten(span);
    final title = pairs.firstWhere((p) => p.$1 == 'Title');
    final marker = pairs.firstWhere((p) => p.$1 == '# ');
    expect(title.$2!.fontSize, greaterThan(20));
    expect(marker.$2!.fontSize, title.$2!.fontSize); // marker shares heading size
  });

  testWidgets('bold and italic apply weight and style with kept markers', (
    tester,
  ) async {
    final span = await _build(tester, '**bold** and *italic*');
    final pairs = _flatten(span);

    final bold = pairs.firstWhere((p) => p.$1 == 'bold');
    expect(bold.$2!.fontWeight, FontWeight.w700);
    expect(pairs.where((p) => p.$1 == '**').length, 2); // markers kept

    final italic = pairs.firstWhere((p) => p.$1 == 'italic');
    expect(italic.$2!.fontStyle, FontStyle.italic);
  });

  testWidgets('inline code gets a code background', (tester) async {
    final span = await _build(tester, 'run `flutter test` now');
    final pairs = _flatten(span);
    final code = pairs.firstWhere((p) => p.$1 == 'flutter test');
    expect(code.$2!.backgroundColor, isNotNull);
  });

  testWidgets('checked checkbox strikes through its content', (tester) async {
    final span = await _build(tester, '- [x] done\n- [ ] todo');
    final pairs = _flatten(span);
    final done = pairs.firstWhere((p) => p.$1 == 'done');
    final todo = pairs.firstWhere((p) => p.$1 == 'todo');
    expect(done.$2!.decoration, TextDecoration.lineThrough);
    expect(todo.$2!.decoration, anyOf(isNull, TextDecoration.none));
  });

  testWidgets('bullet marker is accented', (tester) async {
    final span = await _build(tester, '- item');
    final pairs = _flatten(span);
    // The marker '-' and the content 'item' are separate spans.
    expect(pairs.any((p) => p.$1 == '-'), isTrue);
    expect(pairs.any((p) => p.$1 == 'item'), isTrue);
  });

  testWidgets('fenced code lines use a monospace style', (tester) async {
    final span = await _build(tester, '```\ncode line\n```');
    final pairs = _flatten(span);
    final code = pairs.firstWhere((p) => p.$1 == 'code line');
    // JetBrains Mono is registered via google_fonts with a generated family.
    expect(code.$2!.fontFamily, isNot('Inter'));
  });
}
