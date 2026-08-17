import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:simsync_mobile/models/note.dart';
import 'package:simsync_mobile/screens/calendar_screen.dart';
import 'package:simsync_mobile/services/note_service.dart';
import 'package:simsync_mobile/settings/app_settings_controller.dart';
import 'package:simsync_mobile/storage/note_storage.dart';
import 'package:simsync_mobile/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('ko');
  });

  group('mobile memo tab', () {
    testWidgets('renders daily and memo tabs with daily active by default', (
      tester,
    ) async {
      final storage = _FakeStorage();
      await _pumpCalendar(tester, storage);

      expect(find.text('daily'), findsOneWidget);
      expect(find.text('memo'), findsOneWidget);
      // Daily mode shows the calendar (Korean weekday headers).
      expect(find.text('일'), findsWidgets);
    });

    testWidgets('memo tab shows memos from any date and excludes daily notes', (
      tester,
    ) async {
      final storage = _FakeStorage([
        _note(
          id: 'm1',
          title: 'Memo A',
          isMemo: true,
          noteDate: DateTime(2026, 1, 1),
        ),
        _note(
          id: 'm2',
          title: 'Memo B',
          isMemo: true,
          noteDate: DateTime(2026, 12, 31),
        ),
        _note(id: 'd1', title: 'Daily X', isMemo: false),
      ]);
      await _pumpCalendar(tester, storage);

      await tester.tap(find.text('memo'));
      await tester.pumpAndSettle();

      expect(find.text('Memo A'), findsOneWidget);
      expect(find.text('Memo B'), findsOneWidget);
      expect(find.text('Daily X'), findsNothing);
    });

    testWidgets('daily tab shows only selected-date non-memo notes', (
      tester,
    ) async {
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      final storage = _FakeStorage([
        _note(id: 'd1', title: 'Daily X', isMemo: false, noteDate: todayDate),
        _note(id: 'm1', title: 'Memo A', isMemo: true, noteDate: todayDate),
      ]);
      await _pumpCalendar(tester, storage);

      expect(find.text('Daily X'), findsOneWidget);
      expect(find.text('Memo A'), findsNothing);
    });

    testWidgets('long-press daily note then "메모로 이동" flips isMemo to true', (
      tester,
    ) async {
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      final storage = _FakeStorage([
        _note(id: 'd1', title: 'Daily X', isMemo: false, noteDate: todayDate),
      ]);
      await _pumpCalendar(tester, storage);

      await tester.longPress(find.text('Daily X'));
      await tester.pumpAndSettle();
      expect(find.text('메모로 이동'), findsOneWidget);

      await tester.tap(find.text('메모로 이동'));
      await tester.pumpAndSettle();

      final notes = await storage.listAllNotes();
      expect(notes.single.isMemo, isTrue);
      // No longer in the daily list.
      expect(find.text('Daily X'), findsNothing);

      // Appears in the memo tab.
      await tester.tap(find.text('memo'));
      await tester.pumpAndSettle();
      expect(find.text('Daily X'), findsOneWidget);
    });

    testWidgets('long-press memo then "daily로 이동" flips isMemo to false', (
      tester,
    ) async {
      final storage = _FakeStorage([
        _note(
          id: 'm1',
          title: 'Memo A',
          isMemo: true,
          noteDate: DateTime(2026, 1, 1),
        ),
      ]);
      await _pumpCalendar(tester, storage);

      await tester.tap(find.text('memo'));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Memo A'));
      await tester.pumpAndSettle();
      expect(find.text('daily로 이동'), findsOneWidget);

      await tester.tap(find.text('daily로 이동'));
      await tester.pumpAndSettle();

      final notes = await storage.listAllNotes();
      expect(notes.single.isMemo, isFalse);
    });

    testWidgets('memo tab shows empty state when there are no memos', (
      tester,
    ) async {
      final storage = _FakeStorage();
      await _pumpCalendar(tester, storage);

      await tester.tap(find.text('memo'));
      await tester.pumpAndSettle();

      expect(find.text('메모가 없습니다'), findsOneWidget);
    });
  });
}

Future<void> _pumpCalendar(WidgetTester tester, NoteStorage storage) async {
  final settingsController = AppSettingsController(
    defaultLocalNotePath: '/tmp/simsync-mobile-test',
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: buildLightTheme(),
      home: CalendarScreen(
        storage: storage,
        noteService: NoteService(),
        refreshSignal: ValueNotifier<int>(0),
        settingsController: settingsController,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Note _note({
  required String id,
  String title = '',
  String content = '',
  DateTime? noteDate,
  bool isMemo = false,
  DateTime? updatedAt,
}) {
  final now = DateTime.now();
  final date = noteDate ?? DateTime(now.year, now.month, now.day);
  return Note(
    id: id,
    noteDate: date,
    title: title,
    content: content,
    isDefault: false,
    tags: const [],
    createdAt: now,
    updatedAt: updatedAt ?? now,
    isMemo: isMemo,
  );
}

class _FakeStorage implements NoteStorage {
  _FakeStorage([List<Note> initialNotes = const []])
    : _notes = List<Note>.from(initialNotes);

  final List<Note> _notes;

  void _upsert(Note note) {
    final index = _notes.indexWhere((item) => item.id == note.id);
    if (index == -1) {
      _notes.add(note);
      return;
    }
    _notes[index] = note;
  }

  @override
  Future<void> deleteNote(Note note) async {
    _notes.removeWhere((item) => item.id == note.id);
  }

  @override
  Future<Note?> getNote(String noteId, DateTime noteDate) async {
    final match = _notes.where((note) => note.id == noteId);
    return match.isEmpty ? null : match.first;
  }

  @override
  Future<List<Note>> listAllNotes() async {
    return List<Note>.from(_notes);
  }

  @override
  Future<List<DateTime>> listDates(String yearMonth) async {
    final parts = yearMonth.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    return _notes
        .where(
          (note) => note.noteDate.year == year && note.noteDate.month == month,
        )
        .map((note) => DateTime(note.noteDate.year, note.noteDate.month, note.noteDate.day))
        .toSet()
        .toList()
      ..sort();
  }

  @override
  Future<List<Note>> listNotes(DateTime date) async {
    return _notes
        .where(
          (note) =>
              note.noteDate.year == date.year &&
              note.noteDate.month == date.month &&
              note.noteDate.day == date.day,
        )
        .toList();
  }

  @override
  Future<void> saveNote(Note note) async {
    _upsert(note);
  }

  // 파일 입출력은 이 테스트 페이크의 관심사가 아니다 (노트 CRUD만 검증한다).
  @override
  Future<String?> readTextFile(String relativePath) async => null;

  @override
  Future<void> writeTextFile(String relativePath, String content) async {}

  @override
  Future<Uint8List?> readBinaryFile(String relativePath) async => null;

  @override
  Future<void> writeBinaryFile(String relativePath, Uint8List bytes) async {}

  @override
  String noteDirPath(DateTime noteDate) =>
      'notes/${noteDate.year}-${noteDate.month.toString().padLeft(2, '0')}/'
      '${noteDate.day.toString().padLeft(2, '0')}';

}
