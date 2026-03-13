import '../models/note.dart';
import 'note_search_query.dart';

class NoteSearchIndex {
  final Map<String, _IndexedNote> _entries = {};

  void replaceAll(Iterable<Note> notes) {
    _entries
      ..clear()
      ..addEntries(
        notes.map((note) => MapEntry(note.id, _IndexedNote.fromNote(note))),
      );
  }

  void upsert(Note note) {
    _entries[note.id] = _IndexedNote.fromNote(note);
  }

  void remove(String noteId) {
    _entries.remove(noteId);
  }

  List<Note> search(NoteSearchQuery query) {
    final normalizedText = _normalize(query.text);
    final normalizedTag = _normalize(query.tag);

    final results = _entries.values
        .where((entry) {
          if (normalizedText.isNotEmpty &&
              !entry.searchableText.contains(normalizedText)) {
            return false;
          }

          if (normalizedTag.isNotEmpty && !entry.tags.contains(normalizedTag)) {
            return false;
          }

          if (query.startDate != null &&
              _dateOnly(
                entry.note.noteDate,
              ).isBefore(_dateOnly(query.startDate!))) {
            return false;
          }

          if (query.endDate != null &&
              _dateOnly(
                entry.note.noteDate,
              ).isAfter(_dateOnly(query.endDate!))) {
            return false;
          }

          return true;
        })
        .map((entry) => entry.note)
        .toList();

    results.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return results;
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase();
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}

class _IndexedNote {
  final Note note;
  final String searchableText;
  final Set<String> tags;

  _IndexedNote({
    required this.note,
    required this.searchableText,
    required this.tags,
  });

  factory _IndexedNote.fromNote(Note note) {
    final normalizedTags = note.tags.map(NoteSearchIndex._normalize).toSet();
    final buffer = StringBuffer()
      ..write(note.title)
      ..write(' ')
      ..write(note.content)
      ..write(' ')
      ..write(note.tags.join(' '));

    return _IndexedNote(
      note: note,
      searchableText: NoteSearchIndex._normalize(buffer.toString()),
      tags: normalizedTags,
    );
  }
}
