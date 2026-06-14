import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/theme/app_theme.dart';
import 'package:simsync/widgets/editor_panel.dart';

Note _note(String id, String title, String content) {
  final now = DateTime(2026, 5, 2, 9);
  return Note(
    id: id,
    noteDate: DateTime(now.year, now.month, now.day),
    title: title,
    content: content,
    isDefault: false,
    tags: const [],
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'flushes pending dirty content when switching notes before debounce expires',
    (WidgetTester tester) async {
      final noteA = _note('note-a', 'Title A', 'original A');
      final noteB = _note('note-b', 'Title B', 'original B');

      final captured = <Note>[];

      Widget build(Note note) {
        return MaterialApp(
          theme: buildLightTheme(),
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: EditorPanel(
                note: note,
                onNoteChanged: captured.add,
              ),
            ),
          ),
        );
      }

      // Mount with note A.
      await tester.pumpWidget(build(noteA));
      await tester.pump();

      // Find the content TextField (index 2: title, tag input, content).
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(3));

      // User edits the content of note A.
      await tester.enterText(fields.at(2), 'edited A content');
      await tester.pump();

      // Switch to note B BEFORE the 1s auto-save debounce fires (~500ms in).
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(build(noteB));
      await tester.pump();

      // The pending change for note A must have been flushed via onNoteChanged.
      final flushed = captured.where((n) => n.id == 'note-a').toList();
      expect(
        flushed,
        isNotEmpty,
        reason:
            'Switching notes mid-debounce must flush note A\'s dirty content '
            'instead of silently discarding it.',
      );
      expect(flushed.last.content, 'edited A content');

      // No update should be reported for note B with edited A content.
      final bUpdates = captured.where((n) => n.id == 'note-b').toList();
      for (final note in bUpdates) {
        expect(note.content, isNot('edited A content'));
      }

      // Allow the debounce timer to fire so the test cleans up cleanly.
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets(
    'flushes pending dirty content on dispose',
    (WidgetTester tester) async {
      final noteA = _note('note-a', 'Title A', 'original A');
      final captured = <Note>[];

      Widget build({required bool show}) {
        return MaterialApp(
          theme: buildLightTheme(),
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: show
                  ? EditorPanel(
                      note: noteA,
                      onNoteChanged: captured.add,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        );
      }

      await tester.pumpWidget(build(show: true));
      await tester.pump();

      // User edits before debounce fires, then panel is unmounted.
      await tester.enterText(find.byType(TextField).at(2), 'unsaved on close');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(build(show: false));
      await tester.pump();

      final flushed = captured.where((n) => n.id == 'note-a').toList();
      expect(
        flushed,
        isNotEmpty,
        reason:
            'Disposing the editor with pending dirty content must flush before '
            'tearing down the controllers.',
      );
      expect(flushed.last.content, 'unsaved on close');
    },
  );
}
