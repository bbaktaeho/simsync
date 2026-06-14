import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/storage/note_storage.dart';

/// In-memory fake implementation of NoteStorage for testing the interface contract.
class FakeNoteStorage implements NoteStorage {
  final Map<String, Note> _notes = {};

  @override
  Future<List<Note>> listAllNotes() async {
    final notes = _notes.values.toList();
    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return notes;
  }

  @override
  Future<List<Note>> listNotes(DateTime date) async {
    return _notes.values
        .where(
          (n) =>
              n.noteDate.year == date.year &&
              n.noteDate.month == date.month &&
              n.noteDate.day == date.day,
        )
        .toList();
  }

  @override
  Future<List<DateTime>> listDates(String yearMonth) async {
    final parts = yearMonth.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);

    final dates = _notes.values
        .where((n) => n.noteDate.year == year && n.noteDate.month == month)
        .map((n) => DateTime(n.noteDate.year, n.noteDate.month, n.noteDate.day))
        .toSet()
        .toList();
    dates.sort();
    return dates;
  }

  @override
  Future<Note?> getNote(String noteId, DateTime noteDate) async {
    return _notes[noteId];
  }

  @override
  Future<void> saveNote(Note note) async {
    _notes[note.id] = note;
  }

  @override
  Future<void> deleteNote(Note note) async {
    _notes.remove(note.id);
  }
}

Note _createNote({
  required String id,
  required DateTime noteDate,
  String title = '',
  String content = '',
}) {
  final now = DateTime.now();
  return Note(
    id: id,
    noteDate: noteDate,
    title: title,
    content: content,
    isDefault: false,
    tags: [],
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late FakeNoteStorage storage;

  setUp(() {
    storage = FakeNoteStorage();
  });

  test('saveNote and listNotes returns saved notes for the date', () async {
    final date = DateTime(2026, 3, 10);
    final note1 = _createNote(id: 'n1', noteDate: date, title: 'Note 1');
    final note2 = _createNote(id: 'n2', noteDate: date, title: 'Note 2');

    await storage.saveNote(note1);
    await storage.saveNote(note2);

    final notes = await storage.listNotes(date);
    expect(notes.length, 2);
    expect(notes.map((n) => n.id).toSet(), {'n1', 'n2'});
  });

  test('listNotes does not return notes from other dates', () async {
    final date1 = DateTime(2026, 3, 10);
    final date2 = DateTime(2026, 3, 11);
    await storage.saveNote(_createNote(id: 'n1', noteDate: date1));
    await storage.saveNote(_createNote(id: 'n2', noteDate: date2));

    final notes = await storage.listNotes(date1);
    expect(notes.length, 1);
    expect(notes.first.id, 'n1');
  });

  test('getNote returns note by id', () async {
    final date = DateTime(2026, 3, 10);
    final note = _createNote(id: 'n1', noteDate: date, title: 'Hello');
    await storage.saveNote(note);

    final result = await storage.getNote('n1', date);
    expect(result, isNotNull);
    expect(result!.id, 'n1');
    expect(result.title, 'Hello');
  });

  test('getNote returns null for missing note', () async {
    final result = await storage.getNote('nonexistent', DateTime(2026, 3, 10));
    expect(result, isNull);
  });

  test('deleteNote removes note', () async {
    final date = DateTime(2026, 3, 10);
    final note = _createNote(id: 'n1', noteDate: date);
    await storage.saveNote(note);

    await storage.deleteNote(note);

    final result = await storage.getNote('n1', date);
    expect(result, isNull);

    final notes = await storage.listNotes(date);
    expect(notes, isEmpty);
  });

  test('listDates returns dates with notes for the given month', () async {
    await storage.saveNote(
      _createNote(id: 'n1', noteDate: DateTime(2026, 3, 5)),
    );
    await storage.saveNote(
      _createNote(id: 'n2', noteDate: DateTime(2026, 3, 10)),
    );
    await storage.saveNote(
      _createNote(id: 'n3', noteDate: DateTime(2026, 3, 10)),
    );
    // Different month — should not appear.
    await storage.saveNote(
      _createNote(id: 'n4', noteDate: DateTime(2026, 4, 1)),
    );

    final dates = await storage.listDates('2026-03');
    expect(dates.length, 2);
    expect(dates[0], DateTime(2026, 3, 5));
    expect(dates[1], DateTime(2026, 3, 10));
  });
}
