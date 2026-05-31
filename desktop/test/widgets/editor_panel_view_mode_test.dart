import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/theme/app_theme.dart';
import 'package:simsync/widgets/editor_panel.dart';
import 'package:simsync/widgets/markdown_preview.dart';

Note _note({String content = '# Hello\n\nbody'}) {
  final now = DateTime(2026, 5, 31, 9);
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

Future<void> _pump(
  WidgetTester tester, {
  Note? note,
  bool allowSplit = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: SizedBox(
          height: 600,
          width: 1000,
          child: EditorPanel(
            note: note ?? _note(),
            onNoteChanged: (_) {},
            allowSplit: allowSplit,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('split is the default view and shows both editor and preview', (
    tester,
  ) async {
    await _pump(tester);

    // Editor (title + tag + content) and the live preview are both present.
    expect(find.byType(TextField), findsNWidgets(3));
    expect(find.byType(MarkdownPreviewWidget), findsOneWidget);
  });

  testWidgets('switching to Edit hides the preview', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownPreviewWidget), findsNothing);
    expect(find.byType(TextField), findsNWidgets(3));
  });

  testWidgets('switching to Preview hides the editor content field', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownPreviewWidget), findsOneWidget);
    // Only the title and tag fields remain; the content editor is hidden.
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('split preview updates live as the content changes', (
    tester,
  ) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField).at(2), 'live edit text');
    await tester.pump();

    final preview = tester.widget<MarkdownPreviewWidget>(
      find.byType(MarkdownPreviewWidget),
    );
    expect(preview.content, 'live edit text');

    // Let the auto-save debounce fire so no timer is pending at teardown.
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('allowSplit false falls back to edit and hides the Split segment', (
    tester,
  ) async {
    await _pump(tester, allowSplit: false);

    expect(find.text('Split'), findsNothing);
    expect(find.byType(MarkdownPreviewWidget), findsNothing);
    expect(find.byType(TextField), findsNWidgets(3));
  });

  testWidgets('Insert table action inserts a table rendered in the preview', (
    tester,
  ) async {
    await _pump(tester, note: _note(content: ''));

    await tester.tap(find.byTooltip('Insert table'));
    await tester.pumpAndSettle();
    expect(find.text('Insert table'), findsOneWidget); // dialog title

    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();

    // Default 2x2 skeleton -> header cell rendered in the live preview.
    expect(find.text('Column 1'), findsWidgets);

    await tester.pump(const Duration(seconds: 2));
  });
}
