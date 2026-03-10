import 'package:yaml/yaml.dart';

import '../../models/note.dart';
import '../note_storage.dart';
import 'github_api_client.dart';

/// NoteStorage implementation backed by GitHub Contents API.
///
/// Notes are stored as markdown files with YAML frontmatter at:
///   `notes/{YYYY-MM}/{DD}/{title}.md`
class GitHubNoteStorage implements NoteStorage {
  final GitHubApiClient _client;

  /// SHA cache: file path → SHA (required for PUT/DELETE operations).
  final Map<String, String> _shaCache = {};

  /// Parsed note cache: file path → Note.
  final Map<String, Note> _noteCache = {};

  /// ID-to-path index: noteId → file path (for fast getNote lookups).
  final Map<String, String> _idToPath = {};

  GitHubNoteStorage(this._client);

  // --- Path helpers ---

  /// Sanitizes a title for use as a filename by removing invalid characters.
  static String _sanitizeTitle(String title) {
    return title.replaceAll(RegExp(r'[/\\:*?"<>|]'), '');
  }

  /// Builds the file path for a note.
  static String _buildPath(Note note) {
    final yearMonth =
        '${note.noteDate.year}-${note.noteDate.month.toString().padLeft(2, '0')}';
    final day = note.noteDate.day.toString().padLeft(2, '0');
    final sanitized = _sanitizeTitle(note.title);
    final filename = sanitized.isEmpty ? note.id : sanitized;
    return 'notes/$yearMonth/$day/$filename.md';
  }

  /// Builds the directory path for a specific date.
  static String _dayDirPath(DateTime date) {
    final yearMonth =
        '${date.year}-${date.month.toString().padLeft(2, '0')}';
    final day = date.day.toString().padLeft(2, '0');
    return 'notes/$yearMonth/$day';
  }

  /// Builds the directory path for a year-month string.
  static String _monthDirPath(String yearMonth) {
    return 'notes/$yearMonth';
  }

  // --- Serialization ---

  /// Serializes a Note to markdown with YAML frontmatter.
  static String serializeNote(Note note) {
    final buf = StringBuffer();
    buf.writeln('---');
    buf.writeln('id: "${note.id}"');
    buf.writeln('title: "${note.title}"');
    buf.writeln(
        'note_date: ${note.noteDate.year}-${note.noteDate.month.toString().padLeft(2, '0')}-${note.noteDate.day.toString().padLeft(2, '0')}');
    buf.writeln('is_default: ${note.isDefault}');
    buf.writeln(
        'tags: [${note.tags.map((t) => '"$t"').join(', ')}]');
    buf.writeln('created_at: ${_formatDateTime(note.createdAt)}');
    buf.writeln('updated_at: ${_formatDateTime(note.updatedAt)}');
    buf.writeln('---');
    buf.write(note.content);
    return buf.toString();
  }

  static String _formatDateTime(DateTime dt) {
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');

    final offset = dt.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final offHours = offset.inHours.abs().toString().padLeft(2, '0');
    final offMinutes =
        (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');

    return '$y-$m-${d}T$h:$min:$s$sign$offHours$offMinutes';
  }

  /// Parses a markdown string with YAML frontmatter into a Note.
  static Note? parseNote(String markdown) {
    if (!markdown.startsWith('---')) return null;

    final endIndex = markdown.indexOf('---', 3);
    if (endIndex == -1) return null;

    final yamlStr = markdown.substring(3, endIndex).trim();
    final content = markdown.substring(endIndex + 3);
    // Remove leading single newline after closing ---
    final noteContent =
        content.startsWith('\n') ? content.substring(1) : content;

    final yaml = loadYaml(yamlStr);
    if (yaml is! YamlMap) return null;

    final id = yaml['id']?.toString() ?? '';
    if (id.isEmpty) return null;

    final title = yaml['title']?.toString() ?? '';
    final isDefault = yaml['is_default'] == true;

    final tagsList = <String>[];
    final tagsRaw = yaml['tags'];
    if (tagsRaw is YamlList) {
      for (final t in tagsRaw) {
        tagsList.add(t.toString());
      }
    }

    final noteDate = _parseDate(yaml['note_date']?.toString() ?? '');
    final createdAt =
        _parseDateTime(yaml['created_at']?.toString() ?? '');
    final updatedAt =
        _parseDateTime(yaml['updated_at']?.toString() ?? '');

    if (noteDate == null || createdAt == null || updatedAt == null) {
      return null;
    }

    return Note(
      id: id,
      noteDate: noteDate,
      title: title,
      content: noteContent,
      isDefault: isDefault,
      tags: tagsList,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static DateTime? _parseDate(String s) {
    if (s.isEmpty) return null;
    try {
      final parts = s.split('-');
      if (parts.length != 3) return null;
      return DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
    } catch (_) {
      return null;
    }
  }

  static DateTime? _parseDateTime(String s) {
    if (s.isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  // --- NoteStorage implementation ---

  @override
  Future<List<Note>> listNotes(DateTime date) async {
    final dirPath = _dayDirPath(date);
    final files = await _client.listDirectory(dirPath);

    // Track current file paths to prune stale cache entries.
    final currentPaths = <String>{};
    final notes = <Note>[];

    for (final file in files) {
      if (file.type != 'file' || !file.name.endsWith('.md')) continue;

      final path = file.path;
      currentPaths.add(path);

      // Use cached note if SHA is unchanged.
      if (_shaCache[path] == file.sha && _noteCache.containsKey(path)) {
        notes.add(_noteCache[path]!);
        continue;
      }

      final fullFile = await _client.getFile(path);
      _shaCache[fullFile.path] = fullFile.sha;

      final decoded = fullFile.decodedContent;
      if (decoded == null) continue;

      final note = parseNote(decoded);
      if (note != null) {
        notes.add(note);
        _noteCache[path] = note;
        _idToPath[note.id] = path;
      }
    }

    // Prune cache entries for files no longer in the directory.
    final dirPrefix = '$dirPath/';
    final stalePaths = _noteCache.keys
        .where((p) => p.startsWith(dirPrefix) && !currentPaths.contains(p))
        .toList();
    for (final stalePath in stalePaths) {
      final staleNote = _noteCache.remove(stalePath);
      _shaCache.remove(stalePath);
      if (staleNote != null) {
        _idToPath.remove(staleNote.id);
      }
    }

    return notes;
  }

  @override
  Future<List<DateTime>> listDates(String yearMonth) async {
    final dirPath = _monthDirPath(yearMonth);
    final entries = await _client.listDirectory(dirPath);

    final dates = <DateTime>[];
    final parts = yearMonth.split('-');
    if (parts.length != 2) return dates;

    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null) return dates;

    for (final entry in entries) {
      if (entry.type != 'dir') continue;
      final day = int.tryParse(entry.name);
      if (day == null) continue;
      dates.add(DateTime(year, month, day));
    }

    dates.sort((a, b) => a.compareTo(b));
    return dates;
  }

  @override
  Future<Note?> getNote(String noteId, DateTime noteDate) async {
    // Fast path: use ID-to-path index.
    final cachedPath = _idToPath[noteId];
    if (cachedPath != null && _noteCache.containsKey(cachedPath)) {
      return _noteCache[cachedPath];
    }

    // If we have a path but no cached note, fetch directly.
    if (cachedPath != null) {
      try {
        final fullFile = await _client.getFile(cachedPath);
        _shaCache[fullFile.path] = fullFile.sha;
        final decoded = fullFile.decodedContent;
        if (decoded != null) {
          final note = parseNote(decoded);
          if (note != null && note.id == noteId) {
            _noteCache[cachedPath] = note;
            return note;
          }
        }
      } on GitHubNotFoundException {
        // Path is stale; remove from index and fall through.
        _idToPath.remove(noteId);
        _noteCache.remove(cachedPath);
        _shaCache.remove(cachedPath);
      }
    }

    // Fallback: list all notes for the date (populates caches for next time).
    final notes = await listNotes(noteDate);
    return notes.where((n) => n.id == noteId).isEmpty
        ? null
        : notes.firstWhere((n) => n.id == noteId);
  }

  @override
  Future<void> saveNote(Note note) async {
    final path = _buildPath(note);
    final markdown = serializeNote(note);
    final cachedSha = _shaCache[path];

    try {
      final newSha = await _client.putFile(
        path: path,
        content: markdown,
        message: 'Save note: ${note.title}',
        sha: cachedSha,
      );
      _shaCache[path] = newSha;
    } on GitHubConflictException {
      // Last-Write-Wins: fetch latest SHA and retry.
      final latest = await _client.getFile(path);
      final newSha = await _client.putFile(
        path: path,
        content: markdown,
        message: 'Save note: ${note.title}',
        sha: latest.sha,
      );
      _shaCache[path] = newSha;
    }

    _noteCache[path] = note;
    _idToPath[note.id] = path;
  }

  @override
  Future<void> deleteNote(Note note) async {
    final path = _buildPath(note);
    final sha = _shaCache[path];

    if (sha == null) {
      // Try to fetch the SHA if not cached.
      try {
        final file = await _client.getFile(path);
        _shaCache[path] = file.sha;
        await _client.deleteFile(
          path: path,
          sha: file.sha,
          message: 'Delete note: ${note.title}',
        );
      } on GitHubNotFoundException {
        // File doesn't exist, nothing to delete.
        return;
      }
    } else {
      await _client.deleteFile(
        path: path,
        sha: sha,
        message: 'Delete note: ${note.title}',
      );
    }

    _shaCache.remove(path);
    _noteCache.remove(path);
    _idToPath.remove(note.id);
  }
}
