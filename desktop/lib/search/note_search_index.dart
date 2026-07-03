import '../models/note.dart';
import 'note_search_query.dart';
import 'search_result.dart';

/// An in-memory search index over notes.
///
/// Instead of re-scanning every note's full text per query, notes are tokenized
/// once into an inverted index (`token -> note ids`) plus a tag index
/// (`tag -> note ids`), maintained incrementally on [upsert]/[remove]. A query
/// resolves to a candidate id set by intersecting per-term (prefix) matches and
/// per-tag matches, then filtering that small set by date — so search cost
/// scales with the matching vocabulary, not the corpus size.
class NoteSearchIndex {
  final Map<String, _IndexedNote> _entries = {};
  final Map<String, Set<String>> _tokenIndex = {}; // token -> note ids
  final Map<String, Set<String>> _tagIndex = {}; // normalized tag -> note ids

  void replaceAll(Iterable<Note> notes) {
    _entries.clear();
    _tokenIndex.clear();
    _tagIndex.clear();
    for (final note in notes) {
      _add(_IndexedNote.fromNote(note));
    }
  }

  void upsert(Note note) {
    final existing = _entries[note.id];
    if (existing != null) _unindex(existing);
    _add(_IndexedNote.fromNote(note));
  }

  void remove(String noteId) {
    final existing = _entries.remove(noteId);
    if (existing != null) _unindex(existing);
  }

  /// All distinct tags across indexed notes, in their original case, sorted
  /// case-insensitively — used to populate the filter UI's tag chips.
  List<String> get allTags {
    final seen = <String, String>{}; // lower -> first original casing
    for (final entry in _entries.values) {
      for (final tag in entry.note.tags) {
        seen.putIfAbsent(tag.toLowerCase(), () => tag);
      }
    }
    final tags = seen.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return tags;
  }

  void _add(_IndexedNote entry) {
    _entries[entry.note.id] = entry;
    for (final token in entry.tokens) {
      (_tokenIndex[token] ??= <String>{}).add(entry.note.id);
    }
    for (final tag in entry.tags) {
      (_tagIndex[tag] ??= <String>{}).add(entry.note.id);
    }
  }

  void _unindex(_IndexedNote entry) {
    for (final token in entry.tokens) {
      final ids = _tokenIndex[token];
      if (ids != null) {
        ids.remove(entry.note.id);
        if (ids.isEmpty) _tokenIndex.remove(token);
      }
    }
    for (final tag in entry.tags) {
      final ids = _tagIndex[tag];
      if (ids != null) {
        ids.remove(entry.note.id);
        if (ids.isEmpty) _tagIndex.remove(tag);
      }
    }
  }

  /// Candidate note ids that match every query term (by prefix) and every tag.
  /// Returns null when there is no text/tag constraint (i.e. "all notes").
  Set<String>? _candidateIds(NoteSearchQuery query) {
    Set<String>? ids;

    for (final term in tokenize(query.text)) {
      final union = <String>{};
      for (final token in _tokenIndex.keys) {
        if (token.startsWith(term)) union.addAll(_tokenIndex[token]!);
      }
      ids = ids == null ? union : ids.intersection(union);
      if (ids.isEmpty) return ids;
    }

    for (final tag in query.tags) {
      final norm = _normalize(tag);
      if (norm.isEmpty) continue;
      final set = _tagIndex[norm] ?? const <String>{};
      ids = ids == null ? Set.of(set) : ids.intersection(set);
      if (ids.isEmpty) return ids;
    }

    return ids;
  }

  Iterable<_IndexedNote> _matches(NoteSearchQuery query) {
    final ids = _candidateIds(query);
    final entries = ids == null
        ? _entries.values
        : ids.map((id) => _entries[id]).whereType<_IndexedNote>();
    return entries.where((e) => _inDateRange(e.note, query));
  }

  List<Note> search(NoteSearchQuery query) {
    final results = _matches(query).map((e) => e.note).toList();
    results.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return results;
  }

  List<SearchResult> searchWithContext(
    NoteSearchQuery query, {
    int contextLines = 3,
  }) {
    // Highlight the first query term where it appears in a content line.
    final terms = tokenize(query.text);
    final highlight = terms.isEmpty ? '' : terms.first;

    final results = <SearchResult>[];
    for (final entry in _matches(query)) {
      final lines = entry.note.content.split('\n');
      SearchMatch match;
      List<String> before;
      List<String> after;

      var lineIndex = 0;
      var start = 0;
      var end = 0;
      var found = false;
      if (highlight.isNotEmpty) {
        for (var i = 0; i < lines.length; i++) {
          // Lowercase only (no trim) so the offset lines up with the raw line
          // even when it has leading whitespace.
          final idx = lines[i].toLowerCase().indexOf(highlight);
          if (idx != -1) {
            lineIndex = i;
            start = idx;
            end = idx + highlight.length;
            found = true;
            break;
          }
        }
      }

      if (found) {
        match = SearchMatch(
          lineNumber: lineIndex,
          line: lines[lineIndex],
          matchStart: start,
          matchEnd: end,
        );
        final beforeStart = (lineIndex - contextLines).clamp(0, lines.length);
        before = lines.sublist(beforeStart, lineIndex);
        final afterEnd = (lineIndex + 1 + contextLines).clamp(0, lines.length);
        after = lines.sublist(lineIndex + 1, afterEnd);
      } else {
        // The note matched via title/tags, or this is a tag/date-only query:
        // anchor on the first line.
        match = SearchMatch(
          lineNumber: 0,
          line: lines.isNotEmpty ? lines.first : '',
          matchStart: 0,
          matchEnd: 0,
        );
        before = const [];
        final afterEnd = (1 + contextLines).clamp(0, lines.length);
        after = lines.length > 1 ? lines.sublist(1, afterEnd) : const [];
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

  bool _inDateRange(Note note, NoteSearchQuery query) {
    final date = _dateOnly(note.noteDate);
    if (query.startDate != null && date.isBefore(_dateOnly(query.startDate!))) {
      return false;
    }
    if (query.endDate != null && date.isAfter(_dateOnly(query.endDate!))) {
      return false;
    }
    return true;
  }

  /// Splits [text] into lowercased word tokens (Unicode letters/digits),
  /// dropping punctuation and whitespace. Used for both indexing and querying.
  static List<String> tokenize(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((t) => t.isNotEmpty)
        .toList();
  }

  static String _normalize(String value) => value.trim().toLowerCase();

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

class _IndexedNote {
  final Note note;
  final Set<String> tokens;
  final Set<String> tags;

  _IndexedNote({required this.note, required this.tokens, required this.tags});

  factory _IndexedNote.fromNote(Note note) {
    final tokens = <String>{
      ...NoteSearchIndex.tokenize(note.title),
      ...NoteSearchIndex.tokenize(note.content),
      for (final tag in note.tags) ...NoteSearchIndex.tokenize(tag),
    };
    final tags = note.tags.map(NoteSearchIndex._normalize).toSet();
    return _IndexedNote(note: note, tokens: tokens, tags: tags);
  }
}
