import '../models/note.dart';

class SearchMatch {
  final int lineNumber;
  final String line;
  final int matchStart;
  final int matchEnd;

  const SearchMatch({
    required this.lineNumber,
    required this.line,
    required this.matchStart,
    required this.matchEnd,
  });
}

class SearchResult {
  final Note note;
  final SearchMatch match;
  final List<String> contextBefore;
  final List<String> contextAfter;

  const SearchResult({
    required this.note,
    required this.match,
    required this.contextBefore,
    required this.contextAfter,
  });
}
