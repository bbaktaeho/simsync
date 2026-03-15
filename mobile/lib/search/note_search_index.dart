import '../models/note.dart';
import 'note_search_query.dart';
import 'search_result.dart';

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

  List<SearchResult> searchWithContext(
    NoteSearchQuery query, {
    int contextLines = 3,
  }) {
    final normalizedText = _normalize(query.text);
    final normalizedTag = _normalize(query.tag);

    final results = <SearchResult>[];

    for (final entry in _entries.values) {
      if (normalizedText.isNotEmpty &&
          !entry.searchableText.contains(normalizedText)) {
        continue;
      }
      if (normalizedTag.isNotEmpty && !entry.tags.contains(normalizedTag)) {
        continue;
      }
      if (query.startDate != null &&
          _dateOnly(entry.note.noteDate)
              .isBefore(_dateOnly(query.startDate!))) {
        continue;
      }
      if (query.endDate != null &&
          _dateOnly(entry.note.noteDate).isAfter(_dateOnly(query.endDate!))) {
        continue;
      }

      final lines = entry.note.content.split('\n');
      SearchMatch match;
      List<String> before;
      List<String> after;

      if (normalizedText.isNotEmpty) {
        var found = false;
        var matchLineIndex = 0;
        var matchStart = 0;
        var matchEnd = 0;

        for (var i = 0; i < lines.length; i++) {
          final normalizedLine = _normalize(lines[i]);
          final idx = normalizedLine.indexOf(normalizedText);
          if (idx != -1) {
            matchLineIndex = i;
            matchStart = idx;
            matchEnd = idx + normalizedText.length;
            found = true;
            break;
          }
        }

        if (!found) {
          // searchableText includes title+tags so the note matched, but no
          // single content line contains the text.  Use the first line.
          matchLineIndex = 0;
          matchStart = 0;
          matchEnd = 0;
        }

        match = SearchMatch(
          lineNumber: matchLineIndex,
          line: lines[matchLineIndex],
          matchStart: matchStart,
          matchEnd: matchEnd,
        );
        final beforeStart =
            (matchLineIndex - contextLines).clamp(0, lines.length);
        before = lines.sublist(beforeStart, matchLineIndex);
        final afterEnd =
            (matchLineIndex + 1 + contextLines).clamp(0, lines.length);
        after = lines.sublist(matchLineIndex + 1, afterEnd);
      } else {
        // No text query (tag/date filter only) — use first line.
        match = SearchMatch(
          lineNumber: 0,
          line: lines.isNotEmpty ? lines.first : '',
          matchStart: 0,
          matchEnd: 0,
        );
        before = const [];
        final afterEnd = (1 + contextLines).clamp(0, lines.length);
        after = lines.sublist(1, afterEnd);
      }

      results.add(SearchResult(
        note: entry.note,
        match: match,
        contextBefore: before,
        contextAfter: after,
      ));
    }

    results.sort((a, b) => b.note.updatedAt.compareTo(a.note.updatedAt));
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
