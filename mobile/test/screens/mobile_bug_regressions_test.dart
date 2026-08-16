import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:simsync_mobile/models/note.dart';
import 'package:simsync_mobile/screens/calendar_screen.dart';
import 'package:simsync_mobile/screens/editor_screen.dart';
import 'package:simsync_mobile/screens/home_screen.dart';
import 'package:simsync_mobile/screens/search_screen.dart';
import 'package:simsync_mobile/services/note_service.dart';
import 'package:simsync_mobile/settings/app_settings_controller.dart';
import 'package:simsync_mobile/storage/note_storage.dart';
import 'package:simsync_mobile/theme/app_dimensions.dart';
import 'package:simsync_mobile/theme/app_theme.dart';
import 'package:simsync_mobile/widgets/markdown_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('ko');
  });

  group('mobile MVP3 bug regressions', () {
    testWidgets('home screen shows note tab label and calendar avatar image', (
      tester,
    ) async {
      final storage = InMemoryNoteStorage();
      final settingsController = AppSettingsController(
        defaultLocalNotePath: '/tmp/simsync-mobile-test',
      );

      await tester.pumpWidget(
        _buildTestApp(
          HomeScreen(
            onLogout: () async {},
            storage: storage,
            localStorage: null,
            noteService: NoteService(),
            refreshSignal: ValueNotifier<int>(0),
            avatarUrl: '',
            settingsController: settingsController,
            onSyncEnabledChanged: (_) {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('노트'), findsOneWidget);
      expect(find.text('캘린더'), findsNothing);

      final calendarScreen = tester.widget<CalendarScreen>(
        find.byType(CalendarScreen),
      );
      expect(calendarScreen.avatarUrl, '');
    });

    testWidgets(
      'calendar today cell uses border highlight instead of circle fill',
      (tester) async {
        final settingsController = AppSettingsController(
          defaultLocalNotePath: '/tmp/simsync-mobile-test',
        );
        final storage = InMemoryNoteStorage();

        await tester.pumpWidget(
          _buildTestApp(
            CalendarScreen(
              storage: storage,
              noteService: NoteService(),
              refreshSignal: ValueNotifier<int>(0),
              settingsController: settingsController,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final today = DateTime.now();
        final todayText = find.text('${today.day}').first;
        final candidateContainers = find.ancestor(
          of: todayText,
          matching: find.byType(Container),
        );

        final todayBadge = candidateContainers
            .evaluate()
            .map((element) => element.widget)
            .whereType<Container>()
            .where((widget) {
              final decoration = widget.decoration;
              return decoration is BoxDecoration &&
                  widget.constraints?.maxWidth ==
                      AppDimensions.calendarCellSize &&
                  widget.constraints?.maxHeight ==
                      AppDimensions.calendarCellSize;
            })
            .first;

        final decoration = todayBadge.decoration! as BoxDecoration;
        expect(decoration.shape, isNot(BoxShape.circle));
        expect(decoration.border, isNotNull);
      },
    );

    testWidgets(
      'editor preview shows title and scrolls long markdown content',
      (tester) async {
        final note = _note(
          title: 'Preview Title',
          content: List.generate(
            40,
            (index) => 'Line ${index + 1}',
          ).join('\n\n'),
        );
        final storage = InMemoryNoteStorage([note]);
        final settingsController = AppSettingsController(
          defaultLocalNotePath: '/tmp/simsync-mobile-test',
        );

        await tester.pumpWidget(
          _buildTestApp(
            EditorScreen(
              note: note,
              storage: storage,
              settingsController: settingsController,
              onNoteChanged: (_) {},
              onNoteDeleted: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Preview'));
        await tester.pumpAndSettle();

        expect(find.text('Preview Title').hitTestable(), findsOneWidget);
        expect(find.text('Line 40').hitTestable(), findsNothing);

        final previewScrollView = find
            .descendant(
              of: find.byType(MarkdownPreview),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.fling(previewScrollView, const Offset(0, -2000), 4000);
        await tester.pumpAndSettle();

        expect(find.text('Line 40').hitTestable(), findsOneWidget);
      },
    );

    testWidgets('editor refreshes clean note when remote sync signal changes', (
      tester,
    ) async {
      final initialNote = _note(title: 'Before Sync', content: 'Old content');
      final refreshedNote = _note(title: 'After Sync', content: 'New content');
      final storage = InMemoryNoteStorage([initialNote]);
      final refreshSignal = ValueNotifier<int>(0);
      final settingsController = AppSettingsController(
        defaultLocalNotePath: '/tmp/simsync-mobile-test',
      );

      await tester.pumpWidget(
        _buildTestApp(
          EditorScreen(
            note: initialNote,
            storage: storage,
            settingsController: settingsController,
            refreshSignal: refreshSignal,
            onNoteChanged: (_) {},
            onNoteDeleted: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      storage.upsert(refreshedNote);
      refreshSignal.value++;
      await tester.pumpAndSettle();

      final titleField = tester.widget<TextField>(find.byType(TextField).at(0));
      final contentField = tester.widget<TextField>(
        find.byType(TextField).at(1),
      );

      expect(titleField.controller!.text, 'After Sync');
      expect(contentField.controller!.text, 'New content');
    });

    testWidgets(
      'search filter sheet keeps apply button above bottom safe area',
      (tester) async {
        const screenSize = Size(390, 844);
        final settingsController = AppSettingsController(
          defaultLocalNotePath: '/tmp/simsync-mobile-test',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: buildLightTheme(),
            home: MediaQuery(
              data: const MediaQueryData(
                size: screenSize,
                viewPadding: EdgeInsets.only(bottom: 48),
              ),
              child: SearchScreen(
                storage: InMemoryNoteStorage(),
                settingsController: settingsController,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.tune_rounded));
        await tester.pumpAndSettle();

        final applyButtonRect = tester.getRect(
          find.widgetWithText(ElevatedButton, '적용'),
        );
        expect(
          screenSize.height - applyButtonRect.bottom,
          greaterThanOrEqualTo(48),
        );
      },
    );
  });
}

Widget _buildTestApp(Widget child) {
  return MaterialApp(theme: buildLightTheme(), home: child);
}

Note _note({String id = 'note-1', String title = '', String content = ''}) {
  final now = DateTime.now();
  return Note(
    id: id,
    noteDate: DateTime(now.year, now.month, now.day),
    title: title,
    content: content,
    isDefault: true,
    tags: const [],
    createdAt: now,
    updatedAt: now,
  );
}

class InMemoryNoteStorage implements NoteStorage {
  InMemoryNoteStorage([List<Note> initialNotes = const []])
    : _notes = List<Note>.from(initialNotes);

  final List<Note> _notes;

  void upsert(Note note) {
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
        .map(
          (note) => DateTime(
            note.noteDate.year,
            note.noteDate.month,
            note.noteDate.day,
          ),
        )
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
    upsert(note);
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
