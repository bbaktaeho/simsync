import 'package:yaml/yaml.dart';

import '../../models/note.dart';
import '../note_storage.dart';
import 'github_api_client.dart';

/// NoteStorage implementation backed by GitHub Contents API.
///
/// Notes are stored as markdown files with YAML frontmatter at:
///   `notes/{YYYY-MM}/{DD}/{title}.md`
///
/// Listing operations (`listDates`, `listNotes`, `listAllNotes`) consult a
/// recursive tree snapshot (single round-trip via `git/trees`) and fetch
/// missing blob contents in parallel. The tree snapshot is invalidated by
/// [invalidateTreeCache], typically called when the sync engine detects a new
/// commit on the tracked branch.
class GitHubNoteStorage implements NoteStorage {
  final GitHubApiClient _client;
  final String _branch;

  /// SHA cache: file path → SHA (required for PUT/DELETE operations).
  final Map<String, String> _shaCache = {};

  /// Parsed note cache: file path → Note.
  final Map<String, Note> _noteCache = {};

  /// ID-to-path index: noteId → file path (for fast getNote lookups).
  final Map<String, String> _idToPath = {};

  /// Snapshot of `notes/**/*.md` paths → blob SHA from the latest tree fetch.
  /// `null` means "no snapshot loaded" (next listing call will populate).
  /// Empty map means "loaded, no notes yet". Truncated responses set this to
  /// `null` and callers fall back to legacy per-directory listing.
  Map<String, String>? _treeMap;

  /// Set when the tree snapshot for the current branch came back truncated.
  /// While true, listing operations bypass [_ensureTree] entirely.
  bool _treeTruncated = false;

  GitHubNoteStorage(this._client, {String branch = 'main'}) : _branch = branch;

  // --- Tree cache ---

  /// Invalidates the cached tree snapshot. The next listing call will perform
  /// a fresh `git/trees` fetch. Call this when the underlying repository has
  /// likely changed (sync engine commit-SHA polling, manual refresh).
  void invalidateTreeCache() {
    _treeMap = null;
    _treeTruncated = false;
  }

  /// Ensures `_treeMap` is populated. Returns the current snapshot, or `null`
  /// if the tree was truncated / unavailable — callers must fall back to the
  /// legacy directory-listing path.
  Future<Map<String, String>?> _ensureTree() async {
    if (_treeTruncated) return null;
    if (_treeMap != null) return _treeMap;
    try {
      final result = await _client.listRepoTree(branch: _branch);
      if (result.truncated) {
        _treeTruncated = true;
        _treeMap = null;
        return null;
      }
      final map = <String, String>{};
      for (final e in result.entries) {
        if (e.type == 'blob' &&
            e.path.startsWith('notes/') &&
            e.path.endsWith('.md')) {
          map[e.path] = e.sha;
        }
      }
      _treeMap = map;
      return map;
    } on GitHubApiException {
      // 4xx/5xx from tree endpoints (permissions, server errors). Fall back to
      // legacy listing on this call; do not poison the cache so the next call
      // can retry.
      return null;
    }
  }

  /// Bounded-concurrency parallel map for blob fetches. Default of 10 keeps us
  /// well under GitHub's secondary rate limit while still hiding latency.
  static Future<List<R>> _parallelMap<T, R>(
    Iterable<T> items,
    Future<R> Function(T) fn, {
    int concurrency = 10,
  }) async {
    final list = items.toList();
    final results = List<R?>.filled(list.length, null);
    var index = 0;
    Future<void> worker() async {
      while (true) {
        final i = index++;
        if (i >= list.length) return;
        results[i] = await fn(list[i]);
      }
    }

    await Future.wait(
      List.generate(
        list.length < concurrency ? list.length : concurrency,
        (_) => worker(),
      ),
    );
    return results.cast<R>();
  }

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
    final yearMonth = '${date.year}-${date.month.toString().padLeft(2, '0')}';
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
      'note_date: ${note.noteDate.year}-${note.noteDate.month.toString().padLeft(2, '0')}-${note.noteDate.day.toString().padLeft(2, '0')}',
    );
    buf.writeln('is_default: ${note.isDefault}');
    buf.writeln('tags: [${note.tags.map((t) => '"$t"').join(', ')}]');
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
    final offMinutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');

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
    final noteContent = content.startsWith('\n')
        ? content.substring(1)
        : content;

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
    final createdAt = _parseDateTime(yaml['created_at']?.toString() ?? '');
    final updatedAt = _parseDateTime(yaml['updated_at']?.toString() ?? '');

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
  Future<List<Note>> listAllNotes() async {
    final tree = await _ensureTree();
    if (tree != null) {
      return _listAllNotesFromTree(tree);
    }
    return _listAllNotesLegacy();
  }

  Future<List<Note>> _listAllNotesFromTree(Map<String, String> tree) async {
    final paths = tree.keys.toList();
    await _hydrateNotesFromTree(paths: paths, tree: tree);
    _pruneStaleEntries(currentPaths: paths.toSet());
    final notes = paths
        .map((p) => _noteCache[p])
        .whereType<Note>()
        .toList();
    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return notes;
  }

  Future<List<Note>> _listAllNotesLegacy() async {
    final monthEntries = await _client.listDirectory('notes');
    final notes = <Note>[];

    for (final entry in monthEntries) {
      if (entry.type != 'dir') continue;
      if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(entry.name)) continue;

      final dates = await listDates(entry.name);
      for (final date in dates) {
        notes.addAll(await listNotes(date));
      }
    }

    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return notes;
  }

  @override
  Future<List<Note>> listNotes(DateTime date) async {
    final tree = await _ensureTree();
    if (tree != null) {
      return _listNotesFromTree(date, tree);
    }
    return _listNotesLegacy(date);
  }

  Future<List<Note>> _listNotesFromTree(
    DateTime date,
    Map<String, String> tree,
  ) async {
    final dirPath = _dayDirPath(date);
    final dirPrefix = '$dirPath/';
    final paths = tree.keys.where((p) => p.startsWith(dirPrefix)).toList();
    await _hydrateNotesFromTree(paths: paths, tree: tree);
    _pruneStaleEntries(
      currentPaths: paths.toSet(),
      pathPrefix: dirPrefix,
    );
    return paths.map((p) => _noteCache[p]).whereType<Note>().toList();
  }

  Future<List<Note>> _listNotesLegacy(DateTime date) async {
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

    final dirPrefix = '$dirPath/';
    _pruneStaleEntries(currentPaths: currentPaths, pathPrefix: dirPrefix);

    return notes;
  }

  /// Fetches blob contents for any `paths` whose SHA has changed (or that have
  /// no cached entry yet) in parallel. Updates `_shaCache`, `_noteCache`, and
  /// `_idToPath` as files are decoded.
  Future<void> _hydrateNotesFromTree({
    required List<String> paths,
    required Map<String, String> tree,
  }) async {
    final missing = <String>[];
    for (final path in paths) {
      final treeSha = tree[path];
      if (treeSha == null) continue;
      if (_shaCache[path] == treeSha && _noteCache.containsKey(path)) continue;
      missing.add(path);
    }
    if (missing.isEmpty) return;

    await _parallelMap<String, void>(missing, (path) async {
      try {
        final file = await _client.getFile(path);
        _shaCache[file.path] = file.sha;
        final decoded = file.decodedContent;
        if (decoded == null) return;
        final note = parseNote(decoded);
        if (note != null) {
          _noteCache[file.path] = note;
          _idToPath[note.id] = file.path;
        }
      } on GitHubApiException {
        // Skip a single file failure; the remaining notes are still usable.
      } on GitHubNotFoundException {
        // File disappeared between tree fetch and blob fetch; ignore.
      }
    });
  }

  /// Removes cached entries whose path is no longer in [currentPaths]. When
  /// [pathPrefix] is provided, pruning is scoped to that prefix; otherwise the
  /// entire `_noteCache` is considered.
  void _pruneStaleEntries({
    required Set<String> currentPaths,
    String? pathPrefix,
  }) {
    final stalePaths = _noteCache.keys.where((p) {
      if (pathPrefix != null && !p.startsWith(pathPrefix)) return false;
      return !currentPaths.contains(p);
    }).toList();
    for (final stalePath in stalePaths) {
      final staleNote = _noteCache.remove(stalePath);
      _shaCache.remove(stalePath);
      if (staleNote != null) {
        _idToPath.remove(staleNote.id);
      }
    }
  }

  @override
  Future<List<DateTime>> listDates(String yearMonth) async {
    final tree = await _ensureTree();
    if (tree != null) {
      return _listDatesFromTree(yearMonth, tree);
    }
    return _listDatesLegacy(yearMonth);
  }

  List<DateTime> _listDatesFromTree(
    String yearMonth,
    Map<String, String> tree,
  ) {
    final parts = yearMonth.split('-');
    if (parts.length != 2) return const [];
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null) return const [];

    final monthPrefix = 'notes/$yearMonth/';
    final days = <int>{};
    for (final path in tree.keys) {
      if (!path.startsWith(monthPrefix)) continue;
      final rest = path.substring(monthPrefix.length);
      final dayStr = rest.split('/').first;
      final day = int.tryParse(dayStr);
      if (day != null) days.add(day);
    }
    final dates = days.map((d) => DateTime(year, month, d)).toList()
      ..sort((a, b) => a.compareTo(b));
    return dates;
  }

  Future<List<DateTime>> _listDatesLegacy(String yearMonth) async {
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

    // Detect title rename: old path differs from new path for the same note ID.
    final oldPath = _idToPath[note.id];
    if (oldPath != null && oldPath != path) {
      final oldSha = _shaCache[oldPath];
      if (oldSha != null) {
        try {
          await _client.deleteFile(
            path: oldPath,
            sha: oldSha,
            message: 'Delete renamed note: ${note.title}',
          );
        } on GitHubApiException {
          // Ignore 404/409 — file may already be gone or SHA stale.
        }
      }
      _shaCache.remove(oldPath);
      _noteCache.remove(oldPath);
      _idToPath.remove(note.id);
      _treeMap?.remove(oldPath);
    }

    final cachedSha = _shaCache[path];

    String savedSha;
    try {
      savedSha = await _client.putFile(
        path: path,
        content: markdown,
        message: 'Save note: ${note.title}',
        sha: cachedSha,
      );
    } on GitHubConflictException {
      // Last-Write-Wins: fetch latest SHA and retry.
      final latest = await _client.getFile(path);
      savedSha = await _client.putFile(
        path: path,
        content: markdown,
        message: 'Save note: ${note.title}',
        sha: latest.sha,
      );
    }

    _shaCache[path] = savedSha;
    _noteCache[path] = note;
    _idToPath[note.id] = path;
    // Keep the tree snapshot consistent with the local mutation so the next
    // listing call doesn't miss this newly written file.
    _treeMap?[path] = savedSha;
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
    _treeMap?.remove(path);
  }
}
