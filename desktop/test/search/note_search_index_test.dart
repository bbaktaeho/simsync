import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/search/note_search_index.dart';
import 'package:simsync/search/note_search_query.dart';

void main() {
  Note buildNote({
    required String id,
    required DateTime noteDate,
    required String title,
    required String content,
    List<String> tags = const [],
    StorageType storageType = StorageType.synced,
  }) {
    return Note(
      id: id,
      noteDate: noteDate,
      title: title,
      content: content,
      isDefault: false,
      tags: List<String>.from(tags),
      createdAt: noteDate,
      updatedAt: noteDate.add(const Duration(hours: 1)),
      storageType: storageType,
    );
  }

  group('NoteSearchIndex', () {
    test('matches full text across title, content, and tags', () {
      final index = NoteSearchIndex();
      final releaseNote = buildNote(
        id: '1',
        noteDate: DateTime(2026, 3, 10),
        title: 'Release Plan',
        content: 'Ship mobile search foundation this week.',
        tags: ['work', 'mvp'],
      );
      final journalNote = buildNote(
        id: '2',
        noteDate: DateTime(2026, 3, 11),
        title: 'Journal',
        content: 'Went for a walk after lunch.',
        tags: ['personal'],
      );

      index.replaceAll([releaseNote, journalNote]);

      expect(index.search(const NoteSearchQuery(text: 'release')), [
        releaseNote,
      ]);
      expect(index.search(const NoteSearchQuery(text: 'mobile search')), [
        releaseNote,
      ]);
      expect(index.search(const NoteSearchQuery(text: 'MVP')), [releaseNote]);
    });

    test('applies exact tag and inclusive date range filters', () {
      final index = NoteSearchIndex();
      final marchFirst = buildNote(
        id: '1',
        noteDate: DateTime(2026, 3, 1),
        title: 'Kickoff',
        content: 'Initial planning',
        tags: ['work'],
      );
      final marchFifth = buildNote(
        id: '2',
        noteDate: DateTime(2026, 3, 5),
        title: 'Search notes',
        content: 'Need tag filter',
        tags: ['work', 'search'],
      );
      final marchTwelfth = buildNote(
        id: '3',
        noteDate: DateTime(2026, 3, 12),
        title: 'Family',
        content: 'Dinner plans',
        tags: ['personal'],
      );

      index.replaceAll([marchFirst, marchFifth, marchTwelfth]);

      final results = index.search(
        NoteSearchQuery(
          tags: const ['work'],
          startDate: DateTime(2026, 3, 1),
          endDate: DateTime(2026, 3, 5),
        ),
      );

      expect(results, [marchFifth, marchFirst]);
    });

    test('searchWithContext returns match with surrounding context lines', () {
      final index = NoteSearchIndex();
      final note = buildNote(
        id: '1',
        noteDate: DateTime(2026, 3, 10),
        title: 'Multi-line note',
        content: 'line0\nline1\nline2\ntarget keyword here\nline4\nline5\nline6',
      );

      index.replaceAll([note]);

      final results = index.searchWithContext(
        const NoteSearchQuery(text: 'keyword'),
        contextLines: 2,
      );

      expect(results, hasLength(1));
      final result = results.first;
      expect(result.note.id, '1');
      expect(result.match.lineNumber, 3);
      expect(result.match.line, 'target keyword here');
      expect(result.match.matchStart, 7);
      expect(result.match.matchEnd, 14);
      expect(result.contextBefore, ['line1', 'line2']);
      expect(result.contextAfter, ['line4', 'line5']);
    });

    test('searchWithContext highlight offset accounts for leading whitespace',
        () {
      final index = NoteSearchIndex();
      index.replaceAll([
        buildNote(
          id: '1',
          noteDate: DateTime(2026, 3, 10),
          title: 'x',
          content: '  release notes',
        ),
      ]);

      final result =
          index.searchWithContext(const NoteSearchQuery(text: 'release')).first;
      expect(result.match.line, '  release notes');
      expect(result.match.matchStart, 2); // after the two leading spaces
      expect(result.match.matchEnd, 9);
    });

    test('searchWithContext clips context at first and last lines', () {
      final index = NoteSearchIndex();
      final note = buildNote(
        id: '1',
        noteDate: DateTime(2026, 3, 10),
        title: 'Short note',
        content: 'match here\nsecond line',
      );

      index.replaceAll([note]);

      final results = index.searchWithContext(
        const NoteSearchQuery(text: 'match'),
        contextLines: 5,
      );

      expect(results, hasLength(1));
      final result = results.first;
      expect(result.match.lineNumber, 0);
      expect(result.contextBefore, isEmpty);
      expect(result.contextAfter, ['second line']);
    });

    test('searchWithContext uses first line when only tag filter is used', () {
      final index = NoteSearchIndex();
      final note = buildNote(
        id: '1',
        noteDate: DateTime(2026, 3, 10),
        title: 'Tagged note',
        content: 'first line\nsecond line\nthird line',
        tags: ['work'],
      );

      index.replaceAll([note]);

      final results = index.searchWithContext(
        const NoteSearchQuery(tags: ['work']),
        contextLines: 2,
      );

      expect(results, hasLength(1));
      final result = results.first;
      expect(result.match.lineNumber, 0);
      expect(result.match.line, 'first line');
      expect(result.contextBefore, isEmpty);
      expect(result.contextAfter, ['second line', 'third line']);
    });

    test('upsert and remove keep search results in sync', () {
      final index = NoteSearchIndex();
      final note = buildNote(
        id: '1',
        noteDate: DateTime(2026, 3, 10),
        title: 'Original',
        content: 'alpha',
      );

      index.replaceAll([note]);
      expect(index.search(const NoteSearchQuery(text: 'alpha')), [note]);

      final updated = note.copyWith(
        title: 'Updated',
        content: 'beta',
        updatedAt: DateTime(2026, 3, 10, 12),
      );

      index.upsert(updated);

      expect(index.search(const NoteSearchQuery(text: 'alpha')), isEmpty);
      expect(index.search(const NoteSearchQuery(text: 'beta')), [updated]);

      index.remove('1');

      expect(index.search(const NoteSearchQuery(text: 'beta')), isEmpty);
    });

    test('prefix-matches a term as you type', () {
      final index = NoteSearchIndex();
      final note = buildNote(
        id: '1',
        noteDate: DateTime(2026, 3, 1),
        title: 'Release Plan',
        content: 'ship it',
      );
      index.replaceAll([note]);

      expect(index.search(const NoteSearchQuery(text: 'rel')), [note]);
      expect(index.search(const NoteSearchQuery(text: 'pla')), [note]);
      expect(index.search(const NoteSearchQuery(text: 'zzz')), isEmpty);
    });

    test('matches multi-term queries regardless of word order', () {
      final index = NoteSearchIndex();
      final note = buildNote(
        id: '1',
        noteDate: DateTime(2026, 3, 1),
        title: '',
        content: 'mobile search foundation',
      );
      index.replaceAll([note]);

      expect(index.search(const NoteSearchQuery(text: 'search mobile')), [note]);
      expect(
          index.search(const NoteSearchQuery(text: 'mobile foundation')), [note]);
      expect(index.search(const NoteSearchQuery(text: 'mobile missing')), isEmpty);
    });

    test('filters by multiple tags (AND)', () {
      final index = NoteSearchIndex();
      final a = buildNote(
        id: '1',
        noteDate: DateTime(2026, 3, 1),
        title: 'A',
        content: '',
        tags: ['work', 'urgent'],
      );
      final b = buildNote(
        id: '2',
        noteDate: DateTime(2026, 3, 2),
        title: 'B',
        content: '',
        tags: ['work'],
      );
      index.replaceAll([a, b]);

      expect(
        index.search(const NoteSearchQuery(tags: ['work'])).map((n) => n.id).toSet(),
        {'1', '2'},
      );
      expect(index.search(const NoteSearchQuery(tags: ['work', 'urgent'])), [a]);
      expect(
          index.search(const NoteSearchQuery(tags: ['work', 'missing'])), isEmpty);
    });

    test('allTags returns distinct tags sorted case-insensitively', () {
      final index = NoteSearchIndex();
      index.replaceAll([
        buildNote(
            id: '1',
            noteDate: DateTime(2026, 3, 1),
            title: '',
            content: '',
            tags: ['Work', 'zeta']),
        buildNote(
            id: '2',
            noteDate: DateTime(2026, 3, 2),
            title: '',
            content: '',
            tags: ['work', 'Alpha']),
      ]);

      expect(index.allTags, ['Alpha', 'Work', 'zeta']);
    });
  });
}
