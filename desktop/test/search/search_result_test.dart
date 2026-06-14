import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/search/search_result.dart';

void main() {
  test('SearchMatch stores line number and match positions', () {
    const match = SearchMatch(
      lineNumber: 5,
      line: 'hello world',
      matchStart: 6,
      matchEnd: 11,
    );

    expect(match.lineNumber, 5);
    expect(match.line, 'hello world');
    expect(match.matchStart, 6);
    expect(match.matchEnd, 11);
  });

  test('SearchResult stores note, match, and context lines', () {
    final note = Note(
      id: '1',
      noteDate: DateTime(2026, 3, 10),
      title: 'Test',
      content: 'content',
      isDefault: false,
      tags: const [],
      createdAt: DateTime(2026, 3, 10),
      updatedAt: DateTime(2026, 3, 10),
    );

    const match = SearchMatch(
      lineNumber: 2,
      line: 'matched line',
      matchStart: 0,
      matchEnd: 7,
    );

    final result = SearchResult(
      note: note,
      match: match,
      contextBefore: const ['before1', 'before2'],
      contextAfter: const ['after1'],
    );

    expect(result.note.id, '1');
    expect(result.match.lineNumber, 2);
    expect(result.contextBefore, hasLength(2));
    expect(result.contextAfter, hasLength(1));
  });
}
