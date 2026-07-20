
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  @override
  String noteDirPath(DateTime noteDate) =>
      '${noteDate.year}-${noteDate.month.toString().padLeft(2, '0')}-${noteDate.day.toString().padLeft(2, '0')}';
  @override
  Future<Uint8List?> readBinaryFile(String relativePath) async => null;
  @override
  Future<void> writeBinaryFile(String relativePath, Uint8List bytes) async {}
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
  // Defaults to the popover's browse size; the editor-overlay test widens it to
  // the edit size (the real popover window resizes itself for editing).
  double width = 332,
  double height = 500,
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
          width: width,
          height: height,
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

  testWidgets('에디터 오버레이에 이미지 콜백이 연결된다', (tester) async {
    final note = _note(id: 'n1', date: DateTime(2026, 7, 1));
    final controller = await _pumpPanel(tester, notes: [note], width: 720);
    controller.openNote(note);
    await tester.pumpAndSettle();

    final editor = tester.widget<EditorPanel>(find.byType(EditorPanel));
    expect(editor.onLoadImage, isNotNull,
        reason: '팝오버에서도 인라인 이미지가 로드되어야 한다');
    expect(editor.onAttachImage, isNotNull,
        reason: '팝오버에서도 이미지 붙여넣기/첨부가 가능해야 한다');
  });

  testWidgets('팝오버에서 cmd+= / cmd+- 단축키로 확대/축소된다', (tester) async {
    final note = _note(id: 'n1', date: DateTime(2026, 7, 1));
    final controller = await _pumpPanel(tester, notes: [note], width: 720);
    controller.openNote(note);
    await tester.pumpAndSettle();

    final settings = tester
        .widget<MenuBarPanel>(find.byType(MenuBarPanel))
        .settings;
    final before = settings.value.contentScale;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.equal);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.equal);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(settings.value.contentScale, greaterThan(before),
        reason: '팝오버는 별도 엔진이라 자체 단축키 핸들러가 있어야 한다');

    // 컨트롤러의 저장 디바운스/노티스 타이머를 흘려보낸다.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('tapping a note opens the editor overlay; back closes it', (
    tester,
  ) async {
    // The real popover widens to the edit size when the editor opens.
    await _pumpPanel(
      tester,
      notes: [_note(id: 'a', date: DateTime(2026, 7, 1), title: 'Hello')],
      width: 420,
      height: 520,
    );

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

  testWidgets('dragging the calendar/list divider resizes the calendar', (
    tester,
  ) async {
    await _pumpPanel(tester, notes: []);

    final calendar = find.byType(CalendarSection);
    final before = tester.getSize(calendar).height;

    // Drag the divider up → smaller cells → shorter calendar (more room for the
    // list).
    await tester.drag(
      find.byKey(const ValueKey('calendar-list-divider')),
      const Offset(0, -60),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(calendar).height, lessThan(before));
  });
}
