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

  testWidgets('insert table writes a markdown table into the editor', (
    tester,
  ) async {
    await _pump(tester, note: _note(content: ''));

    await tester.tap(find.byTooltip('Insert table'));
    await tester.pumpAndSettle();
    expect(find.text('Insert table'), findsOneWidget); // dialog title

    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();

    expect(_contentController(tester).text, contains('Column 1'));

    await tester.pump(const Duration(seconds: 2));
  });
}
