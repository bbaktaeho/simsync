import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:simsync_mobile/models/note.dart';
import 'package:simsync_mobile/storage/note_storage.dart';
import 'package:simsync_mobile/screens/editor_screen.dart';
import 'package:simsync_mobile/settings/app_settings_controller.dart';
import 'package:simsync_mobile/theme/app_theme.dart';
import 'package:simsync_mobile/widgets/editor_panel.dart';

import 'mobile_bug_regressions_test.dart' show InMemoryNoteStorage;

/// 하단 툴바는 모바일 입력의 주 수단이다 — 눌렀을 때 원문이 정확히 어떻게
/// 바뀌는지 잠가 둔다.
void main() {
  late AppSettingsController settings;

  setUpAll(() => initializeDateFormatting('ko'));

  setUp(() {
    settings = AppSettingsController(defaultLocalNotePath: '/tmp/simsync-test');
  });

  tearDown(() => settings.dispose());

  Future<TextEditingController> pumpEditor(
    WidgetTester tester,
    String content,
  ) async {
    final now = DateTime(2026, 8, 16);
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: EditorScreen(
        storage: InMemoryNoteStorage(),
        onNoteChanged: (_) {},
        onNoteDeleted: (_) {},
        note: Note(
          id: 'n1',
          noteDate: now,
          title: 't',
          content: content,
          isDefault: true,
          tags: const [],
          createdAt: now,
          updatedAt: now,
        ),
        settingsController: settings,
      ),
    ));
    await tester.pumpAndSettle();
    return tester.widget<EditorPanel>(find.byType(EditorPanel)).controller;
  }

  Future<void> tapTool(WidgetTester tester, IconData icon) async {
    await tester.ensureVisible(find.byIcon(icon).first);
    await tester.tap(find.byIcon(icon).first);
    await tester.pump();
  }

  testWidgets('할 일 버튼은 줄 프리픽스를 토글한다 (두 번 눌러도 겹치지 않는다)',
      (tester) async {
    final controller = await pumpEditor(tester, 'todo');
    controller.selection = const TextSelection.collapsed(offset: 4);

    await tapTool(tester, Icons.check_box_outlined);
    expect(controller.text, '- [ ] todo');

    await tapTool(tester, Icons.check_box_outlined);
    expect(controller.text, 'todo', reason: '같은 프리픽스를 다시 누르면 해제');
  });

  testWidgets('목록 버튼은 기존 블록 프리픽스를 교체한다', (tester) async {
    final controller = await pumpEditor(tester, '- [ ] todo');
    controller.selection = const TextSelection.collapsed(offset: 8);

    await tapTool(tester, Icons.format_list_bulleted_rounded);
    expect(controller.text, '- todo', reason: '체크박스 → 불릿 (쌓이지 않는다)');
  });

  testWidgets('들여쓰기/내어쓰기 버튼이 Tab을 대신한다', (tester) async {
    final controller = await pumpEditor(tester, '- a\n- b');
    controller.selection = const TextSelection.collapsed(offset: 7);

    await tapTool(tester, Icons.format_indent_increase_rounded);
    expect(controller.text, '- a\n  - b');

    await tapTool(tester, Icons.format_indent_decrease_rounded);
    expect(controller.text, '- a\n- b');
  });

  testWidgets('인용 버튼은 이 앱의 문법인 | 를 넣는다 (> 는 details 트리거)',
      (tester) async {
    final controller = await pumpEditor(tester, 'quote');
    controller.selection = const TextSelection.collapsed(offset: 5);

    await tapTool(tester, Icons.format_quote_rounded);
    expect(controller.text, '| quote');
  });

  testWidgets('표 버튼은 파싱 가능한 표 블록을 넣는다', (tester) async {
    final controller = await pumpEditor(tester, 'x');
    controller.selection = const TextSelection.collapsed(offset: 1);

    await tapTool(tester, Icons.table_chart_outlined);
    expect(controller.text, contains('| 항목 | 값 |'));
    expect(controller.text, contains('| --- | --- |'));
  });

  testWidgets('앱이 백그라운드로 가면 대기 중인 편집을 즉시 저장한다', (tester) async {
    // 안드로이드는 백그라운드 프로세스를 회수한다 — 디바운스(1초) 안에 있던
    // 편집이 사라지면 안 된다.
    final storage = _CountingStorage(InMemoryNoteStorage());
    final now = DateTime(2026, 8, 16);
    final note = Note(
      id: 'n1',
      noteDate: now,
      title: 't',
      content: 'before',
      isDefault: true,
      tags: const [],
      createdAt: now,
      updatedAt: now,
    );
    storage.inner.upsert(note);

    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: EditorScreen(
        storage: storage,
        onNoteChanged: (_) {},
        onNoteDeleted: (_) {},
        note: note,
        settingsController: settings,
      ),
    ));
    await tester.pumpAndSettle();

    // 실제 입력 경로로 타이핑해야 dirty로 표시된다.
    final editable = find.descendant(
      of: find.byType(EditorPanel),
      matching: find.byType(EditableText),
    );
    await tester.tap(editable);
    await tester.pump();
    tester.state<EditableTextState>(editable).updateEditingValue(
          const TextEditingValue(
            text: 'after background',
            selection: TextSelection.collapsed(offset: 16),
          ),
        );
    await tester.pump();

    // 디바운스(1초)가 끝나기 전에 백그라운드로 보낸다. 이후 프레임만 돌리고
    // 시간을 흘려보내지 않아야 "디바운스가 대신 저장한 것"과 구분된다.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump();

    // 페이크가 같은 Note 인스턴스를 들고 있어 내용 비교로는 검증되지 않는다.
    // 디바운스가 끝나기 전에 저장이 '호출됐는지'로 본다.
    expect(storage.saveCount, 1,
        reason: '백그라운드 전환 시 디바운스 대기분이 즉시 저장돼야 한다');

    // 남은 디바운스 타이머를 정리한다.
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('굵게 버튼은 선택을 감싼다', (tester) async {
    final controller = await pumpEditor(tester, 'bold me');
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 4);

    await tester.ensureVisible(find.text('B'));
    await tester.tap(find.text('B'));
    await tester.pump();

    expect(controller.text, '**bold** me');
  });
}

/// saveNote 호출 횟수만 세는 래퍼. 나머지는 그대로 위임한다.
class _CountingStorage implements NoteStorage {
  _CountingStorage(this.inner);

  final InMemoryNoteStorage inner;
  int saveCount = 0;

  @override
  Future<void> saveNote(Note note) {
    saveCount++;
    return inner.saveNote(note);
  }

  @override
  Future<void> deleteNote(Note note) => inner.deleteNote(note);

  @override
  Future<Note?> getNote(String noteId, DateTime noteDate) =>
      inner.getNote(noteId, noteDate);

  @override
  Future<List<Note>> listAllNotes() => inner.listAllNotes();

  @override
  Future<List<DateTime>> listDates(String yearMonth) =>
      inner.listDates(yearMonth);

  @override
  Future<List<Note>> listNotes(DateTime date) => inner.listNotes(date);

  @override
  Future<String?> readTextFile(String relativePath) =>
      inner.readTextFile(relativePath);

  @override
  Future<void> writeTextFile(String relativePath, String content) =>
      inner.writeTextFile(relativePath, content);

  @override
  Future<Uint8List?> readBinaryFile(String relativePath) =>
      inner.readBinaryFile(relativePath);

  @override
  Future<void> writeBinaryFile(String relativePath, Uint8List bytes) =>
      inner.writeBinaryFile(relativePath, bytes);

  @override
  String noteDirPath(DateTime noteDate) => inner.noteDirPath(noteDate);
}
