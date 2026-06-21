import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/theme/app_theme.dart';
import 'package:simsync/widgets/editor_block_decorations.dart';
import 'package:simsync/widgets/editor_panel.dart';
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

    // The strut floor matches the body font (mdBody = 14 at scale 1.0) so the
    // caret lines up with the text — guards against a too-small strut.
    final field = tester.widget<TextField>(_contentFinder);
    expect(field.strutStyle?.fontSize, 14.0);
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

  testWidgets('a body table is rendered by the decoration painter', (
    tester,
  ) async {
    await _pump(tester,
        note: _note(content: '| H1 | H2 |\n| --- | --- |\n| a | b |'));

    // The decoration layer is active (not the empty SizedBox) and the editor
    // wired the parsed table through to the painter.
    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .where((w) => w.painter is EditorBlockDecorationPainter)
        .map((w) => w.painter as EditorBlockDecorationPainter);
    expect(painters, isNotEmpty);
    expect(painters.first.tables, hasLength(1));
  });

  testWidgets('a pipe-less --- table separator is not drawn as a rule', (
    tester,
  ) async {
    await _pump(tester, note: _note(content: '| H |\n---\n| a |'));
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<EditorBlockDecorationPainter>()
        .first;
    expect(painter.tables, hasLength(1));
    expect(
        painter.regions.where((r) => r.kind == EditorBlockKind.rule), isEmpty);
  });

  testWidgets('table button edits the table at the caret instead of inserting',
      (tester) async {
    await _pump(tester,
        note: _note(content: '| H1 | H2 |\n| --- | --- |\n| a | b |'));

    // Put the caret inside the table, then hit the table button.
    _contentController(tester).selection =
        const TextSelection.collapsed(offset: 3);
    await tester.pump();

    await tester.tap(find.byTooltip('표 삽입 / 편집'));
    await tester.pumpAndSettle();

    // The grid opens in EDIT mode with the existing cells loaded.
    expect(find.text('표 편집'), findsOneWidget);
    expect(find.text('H1'), findsWidgets);

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
  });

  testWidgets('tapping directly on a rendered table opens the editor', (
    tester,
  ) async {
    await _pump(tester,
        note: _note(content: '| H1 | H2 |\n| --- | --- |\n| a | b |'));

    // Tap on the first (header) row of the rendered table. The caret lands in
    // the hidden markdown, which _handleContentTap turns into an edit.
    final topLeft = tester.getTopLeft(_contentFinder);
    await tester.tapAt(topLeft + const Offset(24, 10));
    await tester.pumpAndSettle();

    expect(find.text('표 편집'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
  });
}
