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

Future<TextSpan> _build(
  WidgetTester tester,
  String text, {
  bool focused = false,
  TextSelection? selection,
}) async {
  late TextSpan span;
  final controller = MarkdownEditingController(text: text);
  controller.focused = focused;
  if (selection != null) controller.selection = selection;
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
  testWidgets('preserves the exact text in both active and inactive states', (
    tester,
  ) async {
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
      '```go\nfunc main() {\n\tfmt.Println("hi")\n}\n```',
      '```json\n{"a": [1, 2], "b": true}\n```',
      '```sh\necho "hello" | grep h\n```',
      'above\n---\nbelow',
      '***',
      '```\ncode without language\n```',
      '> a quote\n>> nested deeper',
      '[a link](https://example.com)',
      '***bold italic*** and ___also___',
      'text with ==highlight== inside',
      'auto <https://example.com> and plain http://plain.url/x',
      'mixed [a](b) **c** ==d== ~~e~~ `f` ***g*** http://x.y here',
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
              for (final focused in [false, true]) {
                final controller = MarkdownEditingController(text: input)
                  ..focused = focused
                  ..selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: input.length,
                  );
                final span = controller.buildTextSpan(
                  context: context,
                  withComposing: false,
                );
                expect(span.toPlainText(), input,
                    reason:
                        'char mismatch (focused=$focused): ${input.replaceAll('\n', '\\n')}');
              }
            }
            return const SizedBox();
          },
        ),
      ),
    );
  });

  testWidgets('heading marker collapses when inactive, reveals when active', (
    tester,
  ) async {
    // Inactive (unfocused): the "# " marker is collapsed to near-zero size so
    // the line reads as a rendered heading.
    final inactive = _flatten(await _build(tester, '# Title'));
    final inactiveTitle = inactive.firstWhere((p) => p.$1 == 'Title');
    final inactiveMarker = inactive.firstWhere((p) => p.$1 == '# ');
    expect(inactiveTitle.$2!.fontSize, greaterThan(20)); // rendered big
    expect(inactiveMarker.$2!.fontSize, lessThan(1)); // collapsed

    // Active (focused, caret on the line): the marker is revealed for editing.
    final active = _flatten(await _build(
      tester,
      '# Title',
      focused: true,
      selection: const TextSelection.collapsed(offset: 3),
    ));
    final activeMarker = active.firstWhere((p) => p.$1 == '# ');
    expect(activeMarker.$2!.fontSize, greaterThan(20)); // visible, heading-size
  });

  testWidgets('inline markers collapse when inactive and show when active', (
    tester,
  ) async {
    final inactive = _flatten(await _build(tester, '**bold**'));
    // Two '**' markers, both collapsed (transparent / near-zero).
    final inactiveMarkers = inactive.where((p) => p.$1 == '**').toList();
    expect(inactiveMarkers.length, 2);
    expect(inactiveMarkers.first.$2!.color, Colors.transparent);
    // Content still bold.
    expect(inactive.firstWhere((p) => p.$1 == 'bold').$2!.fontWeight,
        FontWeight.w700);

    final active = _flatten(await _build(
      tester,
      '**bold**',
      focused: true,
      selection: const TextSelection.collapsed(offset: 4),
    ));
    final activeMarkers = active.where((p) => p.$1 == '**').toList();
    expect(activeMarkers.first.$2!.color, isNot(Colors.transparent));
  });

  testWidgets('renders links, bold-italic and highlight inline', (tester) async {
    // Link: visible text is an accented underlined link; url stays (collapsed).
    final link = _flatten(await _build(tester, '[text](https://x.com)'));
    expect(link.firstWhere((p) => p.$1 == 'text').$2!.decoration,
        TextDecoration.underline);
    expect(link.firstWhere((p) => p.$1 == 'https://x.com').$2!.color,
        Colors.transparent); // url hidden when inactive

    // Bold + italic (***)
    final bi = _flatten(await _build(tester, '***x***'));
    final biContent = bi.firstWhere((p) => p.$1 == 'x');
    expect(biContent.$2!.fontWeight, FontWeight.w700);
    expect(biContent.$2!.fontStyle, FontStyle.italic);

    // Highlight (==)
    final hl = _flatten(await _build(tester, '==hi=='));
    expect(hl.firstWhere((p) => p.$1 == 'hi').$2!.backgroundColor, isNotNull);
  });

  testWidgets('blockquote marker hides when inactive, reveals when active', (
    tester,
  ) async {
    final inactive = _flatten(await _build(tester, '> quoted'));
    expect(inactive.firstWhere((p) => p.$1 == '> ').$2!.color, Colors.transparent);

    final active = _flatten(await _build(
      tester,
      '> quoted',
      focused: true,
      selection: const TextSelection.collapsed(offset: 3),
    ));
    expect(active.firstWhere((p) => p.$1 == '> ').$2!.color,
        isNot(Colors.transparent));
  });

  testWidgets('bullet structural marker stays visible when inactive', (
    tester,
  ) async {
    final bullet = _flatten(await _build(tester, '- item'));
    final marker = bullet.firstWhere((p) => p.$1 == '-');
    // Not collapsed — structural markers keep their size.
    expect(marker.$2!.fontSize ?? 14, greaterThan(1));
    expect(marker.$2!.color, isNot(Colors.transparent));
  });

  testWidgets('inline code content keeps a code background', (tester) async {
    final pairs = _flatten(await _build(tester, 'run `flutter test` now'));
    final code = pairs.firstWhere((p) => p.$1 == 'flutter test');
    expect(code.$2!.backgroundColor, isNotNull);
  });

  testWidgets('checked checkbox strikes through its content', (tester) async {
    final pairs = _flatten(await _build(tester, '- [x] done\n- [ ] todo'));
    expect(pairs.firstWhere((p) => p.$1 == 'done').$2!.decoration,
        TextDecoration.lineThrough);
    expect(pairs.firstWhere((p) => p.$1 == 'todo').$2!.decoration,
        anyOf(isNull, TextDecoration.none));
  });

  testWidgets('fenced code is syntax-highlighted into multiple colored tokens', (
    tester,
  ) async {
    final span = await _build(tester, '```go\nfunc main() {}\n```');
    final pairs = _flatten(span);
    // The code line tokenizes into more than one span (keyword vs rest).
    final codeText = pairs
        .map((p) => p.$1)
        .join()
        .replaceAll('```go', '')
        .replaceAll('```', '');
    expect(codeText.contains('func main() {}'), isTrue);

    // At least two distinct foreground colors appear across the document
    // (a highlighted keyword vs. plain code), proving tokenization ran.
    final colors = pairs
        .where((p) => p.$2?.color != null && p.$2?.color != Colors.transparent)
        .map((p) => p.$2!.color)
        .toSet();
    expect(colors.length, greaterThan(1));
  });

  testWidgets('fence lines are hidden (transparent) when inactive', (
    tester,
  ) async {
    final fences = _flatten(await _build(tester, '```\ncode\n```'))
        .where((p) => p.$1 == '```')
        .toList();
    expect(fences.length, 2);
    // Transparent (so only the code content shows) but full height so the caret
    // can still land on them; the box wraps only the content.
    expect(fences.first.$2!.color, Colors.transparent);
    expect(fences.last.$2!.color, Colors.transparent);
  });

  testWidgets('--- rule text is hidden when inactive, revealed when active', (
    tester,
  ) async {
    // Inactive: text transparent (the decoration layer paints the line).
    final inactive = _flatten(await _build(tester, 'a\n---\nb'));
    expect(inactive.firstWhere((p) => p.$1 == '---').$2!.color,
        Colors.transparent);

    // Active (caret on the rule line): revealed for editing.
    final active = _flatten(await _build(
      tester,
      'a\n---\nb',
      focused: true,
      selection: const TextSelection.collapsed(offset: 3),
    ));
    expect(active.firstWhere((p) => p.$1 == '---').$2!.color,
        isNot(Colors.transparent));
  });

  testWidgets('unknown code language falls back without breaking text', (
    tester,
  ) async {
    final span = await _build(tester, '```nonsenselang\nsome code\n```');
    expect(span.toPlainText(), '```nonsenselang\nsome code\n```');
  });
}
