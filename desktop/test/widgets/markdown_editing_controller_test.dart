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

/// [fragment]를 포함하는 첫 스팬의 스타일 (Task 6/12 렌더링 검증용).
TextStyle? _styleOf(TextSpan root, String fragment) {
  for (final (text, style) in _flatten(root)) {
    if (text.contains(fragment)) return style;
  }
  return null;
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
      '| H1 | H2 |\n| --- | --- |\n| a | b |',
      'intro\n\n| A | B |\n| :-- | --: |\n| 1 | 2 |\n\nafter',
      'text | with a pipe but no table',
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

  testWidgets('table lines are hidden so the decoration layer renders them', (
    tester,
  ) async {
    const text = '| H1 | H2 |\n| --- | --- |\n| a | b |';
    final flat = _flatten(await _build(tester, text));
    // The whole line is kept (char-preservation) but painted transparent so the
    // decoration layer's rendered table shows instead of the raw pipes.
    final header = flat.firstWhere((p) => p.$1 == '| H1 | H2 |');
    expect(header.$2!.color, Colors.transparent);
    expect(header.$2!.fontSize, greaterThan(1)); // keeps its row height
    final body = flat.firstWhere((p) => p.$1 == '| a | b |');
    expect(body.$2!.color, Colors.transparent);
    // The separator's font shrinks toward 0 (the strut still floors its line
    // height; the painter divides the table band evenly to absorb that slack).
    final sep = flat.firstWhere((p) => p.$1 == '| --- | --- |');
    expect(sep.$2!.color, Colors.transparent);
    expect(sep.$2!.fontSize, lessThan(1));
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

  group('pipe blockquote', () {
    testWidgets('| 인용문 줄도 문자 보존 invariant를 지킨다', (tester) async {
      const text = '| quoted line\nplain';
      final span = await _build(tester, text);
      expect(_flatten(span).map((e) => e.$1).join(), text);
    });

    testWidgets('레거시 > 인용문도 여전히 매칭된다', (tester) async {
      const text = '> old quote';
      final span = await _build(tester, text);
      expect(_flatten(span).map((e) => e.$1).join(), text);
    });
  });

  group('details rendering', () {
    const closed = '<details>\n<summary>제목</summary>\nbody line\n</details>';
    const opened = '<details open>\n<summary>제목</summary>\nbody line\n</details>';

    String joined(TextSpan span) => _flatten(span).map((e) => e.$1).join();

    testWidgets('invariant: 닫힘/펼침/활성 모두 문자 보존', (tester) async {
      expect(joined(await _build(tester, closed)), closed);
      expect(joined(await _build(tester, opened)), opened);
      expect(
        joined(await _build(tester, closed,
            focused: true,
            selection: const TextSelection.collapsed(offset: 12))),
        closed,
      ); // summary 줄 활성
    });

    testWidgets('태그 줄은 inactive에서 투명 처리된다 (높이 유지)', (tester) async {
      final span = await _build(tester, closed);
      final style = _styleOf(span, '<details>');
      expect(style!.color, Colors.transparent);
      // 폰트 크기는 유지 — 높이 접기가 아니라 fence 줄과 같은 숨김이다.
      expect(style.fontSize ?? 100, greaterThan(1));
    });

    testWidgets('본문 줄은 열림/닫힘 무관하게 일반 렌더링된다', (tester) async {
      for (final text in [closed, opened]) {
        final span = await _build(tester, text);
        final style = _styleOf(span, 'body line');
        expect(style?.color, isNot(Colors.transparent));
      }
    });

    testWidgets('summary 제목은 semibold, 태그는 마커 처리된다', (tester) async {
      final span = await _build(tester, closed);
      expect(_styleOf(span, '제목')!.fontWeight, FontWeight.w600);
      // inactive에서 <summary> 마커는 폭 접힘(극소 폰트 + 투명)
      final marker = _styleOf(span, '<summary>');
      expect(marker!.color, Colors.transparent);
    });
  });

  group('detectFenceLanguage', () {
    test('명백한 JSON을 감지한다', () {
      const block = '{\n  "name": "simsync",\n  "count": 3,\n  "ok": true\n}';
      expect(MarkdownEditingController.detectFenceLanguage(block), isNotNull);
    });

    test('명백한 Dart/유사 코드를 감지한다', () {
      const block = '''
void main() {
  final list = <int>[1, 2, 3];
  for (final v in list) {
    print(v);
  }
}''';
      expect(MarkdownEditingController.detectFenceLanguage(block), isNotNull);
    });

    test('평범한 산문은 감지하지 않는다 (낮은 relevance)', () {
      const block = '오늘은 날씨가 좋았다 그래서 산책을 했다';
      expect(MarkdownEditingController.detectFenceLanguage(block), isNull);
    });
  });

  group('image line rendering', () {
    const img = '<img src="assets/a.png" width="300" height="200">';

    testWidgets('invariant: img 줄도 문자 보존', (tester) async {
      final text = 'before\n$img\nafter';
      final span = await _build(tester, text);
      expect(_flatten(span).map((e) => e.$1).join(), text);
    });

    testWidgets('img 줄 첫 글자가 이미지 높이만큼 폰트를 갖는다 (높이 예약)',
        (tester) async {
      final span = await _build(tester, img);
      final style = _styleOf(span, '<');
      // 예약 높이 = (height 200 + 패딩 12) * scale(1.0)
      expect(style!.fontSize, greaterThan(200));
      expect(style.color, Colors.transparent);
    });
  });
}
