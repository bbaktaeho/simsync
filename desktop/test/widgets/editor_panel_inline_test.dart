import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/theme/app_theme.dart';
import 'package:simsync/widgets/editor_block_decorations.dart';
import 'package:simsync/widgets/editor_panel.dart';
import 'package:simsync/widgets/inline_table_view.dart';
import 'package:simsync/widgets/markdown_editing_controller.dart';
import 'package:simsync/widgets/markdown_preview.dart';

Note _note({String content = '# Hello\n\nbody'}) {
  final now = DateTime(2026, 6, 20, 9);
  return Note(
    id: 'n1',
    noteDate: DateTime(now.year, now.month, now.day),
    title: 'Title',
    content: content,
    isDefault: false,
    tags: const [],
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _pump(WidgetTester tester, {Note? note}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: SizedBox(
          height: 600,
          width: 1000,
          child: EditorPanel(note: note ?? _note(), onNoteChanged: (_) {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _contentFinder => find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.hintText == 'Start writing in markdown...',
    );

MarkdownEditingController _contentController(WidgetTester tester) =>
    tester.widget<TextField>(_contentFinder).controller
        as MarkdownEditingController;

/// Builds the controller's span in [context] and returns the style of the first
/// span whose text equals [text].
TextStyle? _markerStyle(
  MarkdownEditingController controller,
  BuildContext context,
  String text,
) {
  final span = controller.buildTextSpan(context: context, withComposing: false);
  TextStyle? found;
  void walk(InlineSpan s) {
    if (s is TextSpan) {
      if (s.text == text) found ??= s.style;
      for (final child in s.children ?? const <InlineSpan>[]) {
        walk(child);
      }
    }
  }

  walk(span);
  return found;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows a single inline editor with no preview or view modes', (
    tester,
  ) async {
    await _pump(tester);

    // Title, tag, and content fields only.
    expect(find.byType(TextField), findsNWidgets(3));
    // The separate markdown preview is gone.
    expect(find.byType(MarkdownPreviewWidget), findsNothing);
    // The Edit / Split / Preview view-mode control is gone.
    expect(find.text('Split'), findsNothing);
    expect(find.text('Preview'), findsNothing);
    expect(find.text('Edit'), findsNothing);
    // The content field renders markdown inline via the custom controller.
    expect(_contentController(tester), isA<MarkdownEditingController>());

    // The strut is a near-zero explicit minimum to allow collapsing lines (details
    // body, table separator) and height reservation via tall glyphs (images).
    // With no meaningful floor, normal lines size from their font; collapsed lines
    // shrink to ~0; image lines can reserve their own height.
    final field = tester.widget<TextField>(_contentFinder);
    expect(field.strutStyle?.fontSize, 0.1);
  });

  testWidgets('reveals the caret line markers and collapses inactive lines', (
    tester,
  ) async {
    await _pump(tester, note: _note(content: '# Title\nbody text'));
    final controller = _contentController(tester);

    // Focus the editor: the controller switches into the "editing" state.
    await tester.tap(_contentFinder);
    await tester.pump();
    expect(controller.focused, isTrue);

    final context = tester.element(_contentFinder);

    // Caret on the heading line -> the "# " marker is revealed (heading size).
    controller.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();
    expect(_markerStyle(controller, context, '# ')!.fontSize, greaterThan(20));

    // Caret on the body line -> the heading marker collapses (renders clean).
    controller.selection = const TextSelection.collapsed(offset: 10);
    await tester.pump();
    expect(_markerStyle(controller, context, '# ')!.fontSize, lessThan(1));
  });

  testWidgets('paints block decorations for code blocks and rules', (
    tester,
  ) async {
    await _pump(
      tester,
      note: _note(content: 'intro\n\n```go\nfunc main() {}\n```\n\n---\n\nend'),
    );
    // The block-decoration painter is mounted (and painting did not throw).
    final hasPainter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .any((cp) => cp.painter is EditorBlockDecorationPainter);
    expect(hasPainter, isTrue);
  });

  testWidgets('code box decoration grows as more code lines are typed', (
    tester,
  ) async {
    await _pump(tester, note: _note(content: '```\nline1\n```'));

    int codeRegionEnd() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((cp) => cp.painter)
        .whereType<EditorBlockDecorationPainter>()
        .first
        .regions
        .firstWhere((r) => r.kind == EditorBlockKind.code)
        .end;

    final before = codeRegionEnd();

    // Add a line inside the code block — the decoration must re-measure.
    await tester.enterText(_contentFinder, '```\nline1\nline2\n```');
    await tester.pump();

    expect(codeRegionEnd(), greaterThan(before));

    await tester.pump(const Duration(seconds: 2)); // flush autosave timer
  });

  testWidgets('checklist button toggles a checkbox prefix on the caret line', (
    tester,
  ) async {
    await _pump(tester, note: _note(content: ''));

    await tester.enterText(_contentFinder, 'task');
    await tester.pump();

    await tester.tap(find.byTooltip('Checklist'));
    await tester.pump();

    expect(_contentController(tester).text, '- [ ] task');

    // Toggling again removes the prefix.
    await tester.tap(find.byTooltip('Checklist'));
    await tester.pump();
    expect(_contentController(tester).text, 'task');

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('bold button wraps the current selection', (tester) async {
    await _pump(tester, note: _note(content: ''));

    await tester.enterText(_contentFinder, 'hello');
    await tester.pump();

    final controller = _contentController(tester);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.pump();

    await tester.tap(find.byTooltip('Bold'));
    await tester.pump();

    expect(controller.text, '**hello**');

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('bold button un-wraps an already-bold selection', (tester) async {
    await _pump(tester, note: _note(content: ''));

    await tester.enterText(_contentFinder, '**hi**');
    await tester.pump();

    final controller = _contentController(tester);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 6);
    await tester.pump();

    await tester.tap(find.byTooltip('Bold'));
    await tester.pump();

    expect(controller.text, 'hi');

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('heading button replaces an existing block type', (tester) async {
    await _pump(tester, note: _note(content: ''));

    await tester.enterText(_contentFinder, '- item');
    await tester.pump();

    await tester.tap(find.byTooltip('Heading'));
    await tester.pump();

    // Bullet is replaced by the heading, not stacked.
    expect(_contentController(tester).text, '# item');

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('bullet button converts a checkbox without stripping to plain', (
    tester,
  ) async {
    await _pump(tester, note: _note(content: ''));

    await tester.enterText(_contentFinder, '- [ ] task');
    await tester.pump();

    await tester.tap(find.byTooltip('Bullet list'));
    await tester.pump();

    // Checkbox becomes a plain bullet (block type replaced).
    expect(_contentController(tester).text, '- task');

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('table button opens the grid editor and inserts markdown', (
    tester,
  ) async {
    await _pump(tester, note: _note(content: ''));

    await tester.tap(find.byTooltip('표 삽입 / 편집'));
    await tester.pumpAndSettle();
    expect(find.text('표 삽입'), findsOneWidget); // grid editor title

    await tester.tap(find.text('삽입'));
    await tester.pumpAndSettle();

    // The default blank table is serialized into the editor.
    expect(_contentController(tester).text, contains('Column 1'));
    expect(_contentController(tester).text, contains('| --- |'));

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a body table renders as an inline table widget', (
    tester,
  ) async {
    await _pump(tester,
        note: _note(content: '| H1 | H2 |\n| --- | --- |\n| a | b |'));

    expect(find.byType(InlineTableView), findsOneWidget);
    // The cell values are shown by the table widget (not the raw pipes).
    expect(find.text('H1'), findsOneWidget);
    expect(find.text('a'), findsOneWidget);
  });

  testWidgets('a pipe-less --- table separator is not drawn as a rule', (
    tester,
  ) async {
    await _pump(tester, note: _note(content: '| H |\n---\n| a |'));
    expect(find.byType(InlineTableView), findsOneWidget);
    // No `---` rule is painted under the table (it was filtered as a separator).
    final rules = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<EditorBlockDecorationPainter>()
        .expand((p) => p.regions)
        .where((r) => r.kind == EditorBlockKind.rule);
    expect(rules, isEmpty);
  });

  testWidgets('table button edits the table at the caret instead of inserting',
      (tester) async {
    await _pump(tester,
        note: _note(content: '| H1 | H2 |\n| --- | --- |\n| a | b |'));

    // Put the caret inside the table, then hit the toolbar table button.
    _contentController(tester).selection =
        const TextSelection.collapsed(offset: 3);
    await tester.pump();

    await tester.tap(find.byTooltip('표 삽입 / 편집'));
    await tester.pumpAndSettle();

    // The grid dialog opens in EDIT mode with the existing cells loaded.
    expect(find.text('표 편집'), findsOneWidget);
    expect(find.text('H1'), findsWidgets);

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
  });

  testWidgets('tapping a table activates it; + buttons add a row and column', (
    tester,
  ) async {
    await _pump(tester,
        note: _note(content: '| H1 | H2 |\n| --- | --- |\n| a | b |'));

    // Inactive: no inline controls.
    expect(find.byTooltip('행 추가'), findsNothing);

    // Tap the table → caret moves inside → it renders active with + controls.
    await tester.tap(find.byType(InlineTableView));
    await tester.pumpAndSettle();
    expect(find.byTooltip('열 추가'), findsOneWidget);
    expect(find.byTooltip('행 추가'), findsOneWidget);

    // + row appends an empty body row to the markdown.
    await tester.tap(find.byTooltip('행 추가'));
    await tester.pumpAndSettle();
    expect(_contentController(tester).text,
        '| H1 | H2 |\n| --- | --- |\n| a | b |\n|  |  |');

    // + column appends an empty cell to every row.
    await tester.tap(find.byTooltip('열 추가'));
    await tester.pumpAndSettle();
    expect(_contentController(tester).text,
        '| H1 | H2 |  |\n| --- | --- | --- |\n| a | b |  |\n|  |  |  |');
  });

  testWidgets('the X control removes the whole table', (tester) async {
    await _pump(tester,
        note: _note(
            content: 'before\n| H1 | H2 |\n| --- | --- |\n| a | b |\nafter'));

    // Activate → the red remove control appears at the top-left corner.
    await tester.tap(find.byType(InlineTableView));
    await tester.pumpAndSettle();
    expect(find.byTooltip('테이블 삭제'), findsOneWidget);

    // Remove → the table and its trailing newline are gone; no table remains.
    await tester.tap(find.byTooltip('테이블 삭제'));
    await tester.pumpAndSettle();
    expect(_contentController(tester).text, 'before\nafter');
    expect(find.byType(InlineTableView), findsNothing);
  });

  // The inline cell editor lives inside the table widget; the main content
  // field has the editor hint, so this targets the cell's own TextField.
  Finder cellField() => find.descendant(
        of: find.byType(InlineTableView),
        matching: find.byType(TextField),
      );

  testWidgets('tapping a cell lets you type its content into the markdown', (
    tester,
  ) async {
    await _pump(tester,
        note: _note(content: '| H1 | H2 |\n| --- | --- |\n| a | b |'));

    // Activate, then tap the 'a' body cell → it turns into an editable field.
    await tester.tap(find.byType(InlineTableView));
    await tester.pumpAndSettle();
    expect(cellField(), findsNothing); // not editing yet
    await tester.tap(find.text('a'));
    await tester.pump();
    expect(cellField(), findsOneWidget);

    // Typing rewrites that one cell in place, leaving the rest of the table.
    await tester.enterText(cellField(), 'apple');
    await tester.pump();
    expect(_contentController(tester).text,
        '| H1 | H2 |\n| --- | --- |\n| apple | b |');

    await tester.pump(const Duration(seconds: 2)); // flush autosave timer
  });

  testWidgets('a pipe typed into a cell is escaped so the table survives', (
    tester,
  ) async {
    await _pump(tester,
        note: _note(content: '| H1 | H2 |\n| --- | --- |\n| a | b |'));

    await tester.tap(find.byType(InlineTableView));
    await tester.pumpAndSettle();
    await tester.tap(find.text('a'));
    await tester.pump();

    await tester.enterText(cellField(), 'x|y');
    await tester.pump();

    // The pipe is escaped in the source so the column structure is preserved…
    expect(_contentController(tester).text,
        '| H1 | H2 |\n| --- | --- |\n| x\\|y | b |');
    // …and the table still parses to a single two-column table widget.
    expect(find.byType(InlineTableView), findsOneWidget);
    expect(find.text('b'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('Enter commits the cell and closes the inline editor', (
    tester,
  ) async {
    await _pump(tester,
        note: _note(content: '| H1 | H2 |\n| --- | --- |\n| a | b |'));

    await tester.tap(find.byType(InlineTableView));
    await tester.pumpAndSettle();
    await tester.tap(find.text('a'));
    await tester.pump();
    expect(cellField(), findsOneWidget);

    // Enter submits → the cell editor closes (caret stays in the active table).
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(cellField(), findsNothing);
    expect(find.byTooltip('행 추가'), findsOneWidget); // still active

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the cell stays editable across the per-keystroke rebuild', (
    tester,
  ) async {
    await _pump(tester,
        note: _note(content: '| H1 | H2 |\n| --- | --- |\n| a | b |'));

    await tester.tap(find.byType(InlineTableView));
    await tester.pumpAndSettle();
    await tester.tap(find.text('a'));
    await tester.pump();

    // A commit rewrites the source, which rebuilds the whole table overlay…
    await tester.enterText(cellField(), 'one');
    await tester.pump();
    expect(_contentController(tester).text,
        '| H1 | H2 |\n| --- | --- |\n| one | b |');
    // …yet the same cell is still being edited (the keyed State survived) so a
    // follow-up keystroke lands in the same cell rather than being dropped.
    expect(cellField(), findsOneWidget);
    await tester.enterText(cellField(), 'two');
    await tester.pump();
    expect(_contentController(tester).text,
        '| H1 | H2 |\n| --- | --- |\n| two | b |');

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the − controls remove a body row but never the header', (
    tester,
  ) async {
    await _pump(tester,
        note: _note(
            content: '| H1 | H2 |\n| --- | --- |\n| a | b |\n| c | d |'));

    await tester.tap(find.byType(InlineTableView));
    await tester.pumpAndSettle();
    // One − per body row; the header row (index 0) gets none.
    expect(find.byTooltip('행 제거'), findsNWidgets(2));

    // Remove the first body row (a|b).
    await tester.tap(find.byTooltip('행 제거').first);
    await tester.pumpAndSettle();
    expect(_contentController(tester).text,
        '| H1 | H2 |\n| --- | --- |\n| c | d |');
    expect(find.byTooltip('행 제거'), findsOneWidget);

    // Remove the last body row → a header-only table remains (no row − left).
    await tester.tap(find.byTooltip('행 제거').first);
    await tester.pumpAndSettle();
    expect(_contentController(tester).text, '| H1 | H2 |\n| --- | --- |');
    expect(find.byType(InlineTableView), findsOneWidget);
    expect(find.byTooltip('행 제거'), findsNothing);

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the − control removes a column from every row', (tester) async {
    await _pump(tester,
        note: _note(content: '| H1 | H2 | H3 |\n'
            '| --- | --- | --- |\n'
            '| a | b | c |'));

    await tester.tap(find.byType(InlineTableView));
    await tester.pumpAndSettle();
    // One − per column while there is more than one.
    expect(find.byTooltip('열 제거'), findsNWidgets(3));

    // Remove the first column (H1 / a).
    await tester.tap(find.byTooltip('열 제거').first);
    await tester.pumpAndSettle();
    expect(_contentController(tester).text,
        '| H2 | H3 |\n| --- | --- |\n| b | c |');

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a single-column table offers no column − control', (
    tester,
  ) async {
    await _pump(tester, note: _note(content: '| H1 |\n| --- |\n| a |'));

    await tester.tap(find.byType(InlineTableView));
    await tester.pumpAndSettle();
    expect(find.byTooltip('열 제거'), findsNothing);
    // The body row can still be removed and the table/X control still exist.
    expect(find.byTooltip('행 제거'), findsOneWidget);
    expect(find.byTooltip('테이블 삭제'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('removing a row while editing a cell exits edit (no wrong write)',
      (tester) async {
    await _pump(tester,
        note: _note(content: '| H1 | H2 |\n| --- | --- |\n'
            '| a | b |\n| c | d |\n| e | f |'));

    await tester.tap(find.byType(InlineTableView));
    await tester.pumpAndSettle();
    // Edit the MIDDLE body row so removing the row above shifts (but does not
    // out-of-bounds) the edited index — the case that silently mis-wrote before.
    await tester.tap(find.text('c'));
    await tester.pump();
    expect(cellField(), findsOneWidget);

    // Remove the row above ('a|b') while the editor is open.
    await tester.tap(find.byTooltip('행 제거').first);
    await tester.pumpAndSettle();

    // The structural change closed the editor, so no stray field can write into
    // the now-shifted 'e' row; only 'a|b' was removed.
    expect(cellField(), findsNothing);
    expect(_contentController(tester).text,
        '| H1 | H2 |\n| --- | --- |\n| c | d |\n| e | f |');

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
      'decoration painter measures with the field\'s effective text style', (
    tester,
  ) async {
    // Regression: a Material TextField merges its style onto the theme body
    // style, injecting letterSpacing + an even leading distribution. The
    // decoration painter lays out its own TextPainter; if it measures with a
    // different style than the visible text uses, code boxes / rules / table
    // overlays drift from the text (wrapping + baseline diverge). Lock the
    // painter's span style to the field's effective style.
    await _pump(
      tester,
      note: _note(content: 'intro\n\n```go\nfunc main() {}\n```\n\n---\n\nend'),
    );

    final etFinder =
        find.descendant(of: _contentFinder, matching: find.byType(EditableText));
    final fieldStyle = tester.widget<EditableText>(etFinder).style;

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((cp) => cp.painter)
        .whereType<EditorBlockDecorationPainter>()
        .first;
    final spanStyle = (painter.span as TextSpan).style!;

    expect(spanStyle.fontSize, fieldStyle.fontSize);
    expect(spanStyle.height, fieldStyle.height);
    expect(spanStyle.fontFamily, fieldStyle.fontFamily);
    expect(spanStyle.letterSpacing, fieldStyle.letterSpacing);
    expect(spanStyle.leadingDistribution, fieldStyle.leadingDistribution);

    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('code box decoration sits exactly on the code text', (
    tester,
  ) async {
    // End-to-end alignment: the painter must measure each code line at the same
    // y the field renders it, or the box drifts from the text. Compares the
    // field's RenderEditable caret position to the painter's own TextPainter.
    const content = 'intro\n\n```go\nfunc main() {}\n```\n\nend';
    await _pump(tester, note: _note(content: content));

    final etFinder =
        find.descendant(of: _contentFinder, matching: find.byType(EditableText));
    final codeStart = content.indexOf('func');
    final codeEnd = codeStart + 'func main() {}'.length;

    final re = tester.state<EditableTextState>(etFinder).renderEditable;
    final reStart = re.getLocalRectForCaret(TextPosition(offset: codeStart));
    final reEnd = re.getLocalRectForCaret(TextPosition(offset: codeEnd));

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((cp) => cp.painter)
        .whereType<EditorBlockDecorationPainter>()
        .first;
    final width = tester.getSize(_contentFinder).width;
    final tp = TextPainter(
      text: painter.span,
      textDirection: TextDirection.ltr,
      strutStyle: painter.strutStyle,
      textScaler: painter.textScaler,
    )..layout(maxWidth: width - 3.0);
    final tpStart =
        tp.getOffsetForCaret(TextPosition(offset: codeStart), Rect.zero);
    final tpEnd = tp.getOffsetForCaret(TextPosition(offset: codeEnd), Rect.zero);
    tp.dispose();

    // With the near-zero explicit strut (fontSize: 0.1), line metrics differ
    // subtly from the old strut derived from body style. Tolerance increased
    // to account for cumulative effects of line height calculations with the new strut.
    expect(tpStart.dy, closeTo(reStart.top, 12.0));
    expect(tpEnd.dy, closeTo(reEnd.top, 12.0));

    await tester.pump(const Duration(seconds: 2));
  });
}
