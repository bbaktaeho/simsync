import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/services/menu_bar_controller.dart';
import 'package:simsync/settings/app_settings_controller.dart';
import 'package:simsync/storage/note_storage.dart';
import 'package:simsync/theme/app_theme.dart';
import 'package:simsync/widgets/calendar_section.dart';
import 'package:simsync/widgets/editor_panel.dart';
import 'package:simsync/widgets/menu_bar_panel.dart';

class _MemStorage implements NoteStorage {
  _MemStorage([List<Note>? notes]) : _notes = List<Note>.of(notes ?? const []);
  final List<Note> _notes;

  @override
  Future<List<Note>> listAllNotes() async => List<Note>.of(_notes);
  @override
  Future<void> saveNote(Note note) async {
    _notes.removeWhere((n) => n.id == note.id);
    _notes.add(note);
  }

  @override
  Future<void> deleteNote(Note note) async {}
  @override
  Future<Note?> getNote(String noteId, DateTime noteDate) async => null;
  @override
  Future<List<Note>> listNotes(DateTime date) async => const [];
  @override
  Future<List<DateTime>> listDates(String yearMonth) async => const [];
  @override
  Future<String?> readTextFile(String relativePath) async => null;
  @override
  Future<void> writeTextFile(String relativePath, String content) async {}
}

Note _note({
  required String id,
  required DateTime date,
  String title = '',
  String content = 'body',
  bool isMemo = false,
}) {
  final now = DateTime(2026, 7, 1, 9);
  return Note(
    id: id,
    noteDate: date,
    title: title,
    content: content,
    isDefault: false,
    tags: const [],
    createdAt: now,
    updatedAt: now,
    isMemo: isMemo,
  );
}

Future<MenuBarController> _pumpPanel(
  WidgetTester tester, {
  required List<Note> notes,
}) async {
  final storage = _MemStorage(notes);
  final controller = MenuBarController(
    storage: () => storage,
    localStorage: () => null,
    syncEnabled: () => true,
    onChanged: () {},
  );
  final settings = AppSettingsController(defaultLocalNotePath: '/tmp/simsync');
  addTearDown(controller.dispose);
  addTearDown(settings.dispose);

  await controller.load();
  controller.selectDate(DateTime(2026, 7, 1));

  await tester.pumpWidget(
    MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: SizedBox(
          width: 460,
          height: 620,
          child: MenuBarPanel(controller: controller, settings: settings),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the calendar and the selected date\'s notes', (
    tester,
  ) async {
    await _pumpPanel(tester, notes: [
      _note(id: 'a', date: DateTime(2026, 7, 1), title: 'Hello'),
    ]);

    expect(find.byType(CalendarSection), findsOneWidget);
    expect(find.text('Hello'), findsWidgets); // list row title
  });

  testWidgets('tapping a note opens the editor overlay; back closes it', (
    tester,
  ) async {
    await _pumpPanel(tester, notes: [
      _note(id: 'a', date: DateTime(2026, 7, 1), title: 'Hello'),
    ]);

    expect(find.byType(EditorPanel), findsNothing);

    await tester.tap(find.text('Hello').first);
    await tester.pumpAndSettle();
    expect(find.byType(EditorPanel), findsOneWidget);

    await tester.tap(find.byTooltip('뒤로'));
    await tester.pumpAndSettle();
    expect(find.byType(EditorPanel), findsNothing);

    await tester.pump(const Duration(seconds: 2)); // flush any editor timer
  });

  testWidgets('the Memo tab switches the list to memos', (tester) async {
    await _pumpPanel(tester, notes: [
      _note(id: 'day', date: DateTime(2026, 7, 1), title: 'DayNote'),
      _note(id: 'memo', date: DateTime(2026, 7, 1), title: 'MyMemo', isMemo: true),
    ]);

    // Notes tab: the day note is shown, the memo is not.
    expect(find.text('DayNote'), findsWidgets);
    expect(find.text('MyMemo'), findsNothing);

    await tester.tap(find.text('Memo'));
    await tester.pumpAndSettle();

    expect(find.text('MyMemo'), findsWidgets);
    expect(find.text('DayNote'), findsNothing);
  });

  testWidgets('empty memo tab hint omits the right-click-a-date instruction', (
    tester,
  ) async {
    await _pumpPanel(tester, notes: []);
    await tester.tap(find.text('Memo'));
    await tester.pumpAndSettle();

    expect(find.text('메모가 없습니다'), findsOneWidget);
    // Right-clicking a date does not add a memo, so that hint must not appear.
    expect(find.textContaining('우클릭'), findsNothing);
    expect(find.text('+ 로 메모 추가'), findsOneWidget);
  });
}
