import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/services/menu_bar_controller.dart';
import 'package:simsync/storage/note_storage.dart';

/// Minimal in-memory storage for exercising the controller's logic.
class _MemStorage implements NoteStorage {
  _MemStorage([List<Note>? notes]) : _notes = List<Note>.of(notes ?? const []);

  final List<Note> _notes;
  int saveCalls = 0;
  int deleteCalls = 0;

  @override
  Future<List<Note>> listAllNotes() async => List<Note>.of(_notes);

  @override
  Future<void> saveNote(Note note) async {
    saveCalls += 1;
    _notes.removeWhere((n) => n.id == note.id);
    _notes.add(note);
  }

  @override
  Future<void> deleteNote(Note note) async {
    deleteCalls += 1;
    _notes.removeWhere((n) => n.id == note.id);
  }

  @override
  Future<Note?> getNote(String noteId, DateTime noteDate) async {
    for (final n in _notes) {
      if (n.id == noteId) return n;
    }
    return null;
  }

  @override
  Future<List<Note>> listNotes(DateTime date) async => _notes
      .where((n) =>
          n.noteDate.year == date.year &&
          n.noteDate.month == date.month &&
          n.noteDate.day == date.day)
      .toList();

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
  String content = '',
  bool isDefault = false,
  bool isMemo = false,
  DateTime? at,
}) {
  final now = at ?? DateTime(2026, 7, 1, 9);
  return Note(
    id: id,
    noteDate: date,
    title: title,
    content: content,
    isDefault: isDefault,
    tags: const [],
    createdAt: now,
    updatedAt: now,
    isMemo: isMemo,
  );
}

MenuBarController _controller(
  _MemStorage storage, {
  bool sync = true,
  void Function()? onChanged,
}) {
  return MenuBarController(
    storage: () => storage,
    localStorage: () => null,
    syncEnabled: () => sync,
    onChanged: onChanged ?? () {},
  );
}

void main() {
  test('load populates notes and clears the loading flag', () async {
    final s = _MemStorage([_note(id: 'a', date: DateTime(2026, 7, 1))]);
    final c = _controller(s);
    expect(c.isLoading, isTrue);

    await c.load();

    expect(c.isLoading, isFalse);
    expect(c.datesWithNotes, contains(DateTime(2026, 7, 1)));
  });

  test('notesForSelectedDate excludes memos/other dates and sorts default first',
      () async {
    final s = _MemStorage([
      _note(id: 'memo', date: DateTime(2026, 7, 1), isMemo: true),
      _note(id: 'n2', date: DateTime(2026, 7, 1), at: DateTime(2026, 7, 1, 10)),
      _note(
          id: 'n1',
          date: DateTime(2026, 7, 1),
          isDefault: true,
          at: DateTime(2026, 7, 1, 11)),
      _note(id: 'other', date: DateTime(2026, 7, 2)),
    ]);
    final c = _controller(s);
    await c.load();
    c.selectDate(DateTime(2026, 7, 1));

    expect(c.notesForSelectedDate.map((n) => n.id), ['n1', 'n2']);
  });

  test('memo tab switches visibleNotes to memos', () async {
    final s = _MemStorage([
      _note(id: 'memo', date: DateTime(2026, 7, 1), isMemo: true),
      _note(id: 'day', date: DateTime(2026, 7, 1)),
    ]);
    final c = _controller(s);
    await c.load();
    c.selectDate(DateTime(2026, 7, 1));

    expect(c.visibleNotes.map((n) => n.id), ['day']);
    c.setMemoTab(true);
    expect(c.visibleNotes.map((n) => n.id), ['memo']);
  });

  test('selectDate updates the selected date and displayed month', () async {
    final c = _controller(_MemStorage());
    c.selectDate(DateTime(2026, 8, 15));

    expect(c.selectedDate, DateTime(2026, 8, 15));
    expect(c.displayedMonth, DateTime(2026, 8));
  });

  test('previousMonth / nextMonth move the displayed month', () async {
    final c = _controller(_MemStorage());
    c.selectDate(DateTime(2026, 7, 10));

    c.previousMonth();
    expect(c.displayedMonth, DateTime(2026, 6));
    c.nextMonth();
    c.nextMonth();
    expect(c.displayedMonth, DateTime(2026, 8));
  });

  test('createNote saves a synced note and opens the editor', () async {
    final s = _MemStorage();
    final c = _controller(s);
    await c.load();
    c.selectDate(DateTime(2026, 7, 1));

    await c.createNote(memo: false);

    expect(s.saveCalls, 1);
    expect(c.editingNote, isNotNull);
    expect(c.editingNote!.isMemo, isFalse);
    // First note of the day becomes the default note.
    expect(c.editingNote!.isDefault, isTrue);
    expect(c.notesForSelectedDate.length, 1);
  });

  test('createNote(memo) activates the memo tab', () async {
    final s = _MemStorage();
    final c = _controller(s);
    await c.load();
    c.selectDate(DateTime(2026, 7, 1));

    await c.createNote(memo: true);

    expect(c.editingNote!.isMemo, isTrue);
    expect(c.memoTabActive, isTrue);
    expect(c.memoNotes.length, 1);
  });

  test('createNote is blocked with a notice when sync is disabled', () async {
    final s = _MemStorage();
    final c = _controller(s, sync: false);
    await c.load();

    await c.createNote(memo: false);

    expect(s.saveCalls, 0);
    expect(c.editingNote, isNull);
    expect(c.notice, isNotNull);
  });

  test('updateNote persists after the debounce and notifies the host', () async {
    final s = _MemStorage([_note(id: 'a', date: DateTime(2026, 7, 1))]);
    var changes = 0;
    final c = _controller(s, onChanged: () => changes++);
    await c.load();
    c.selectDate(DateTime(2026, 7, 1));

    final note = c.notesForSelectedDate.first;
    c.updateNote(note.copyWith(
      content: 'edited',
      updatedAt: DateTime(2026, 7, 1, 12),
    ));

    // Nothing persisted synchronously (debounced).
    expect(s.saveCalls, 0);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(s.saveCalls, greaterThanOrEqualTo(1));
    expect(changes, greaterThanOrEqualTo(1));
  });

  test('closeEditor clears the editing note', () async {
    final s = _MemStorage();
    final c = _controller(s);
    await c.load();
    c.selectDate(DateTime(2026, 7, 1));
    await c.createNote(memo: false);
    expect(c.editingNote, isNotNull);

    c.closeEditor();
    expect(c.editingNote, isNull);
  });
}
