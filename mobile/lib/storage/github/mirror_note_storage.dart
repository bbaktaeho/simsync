import 'dart:io';

import '../../models/note.dart';
import '../note_storage.dart';
import 'git_mirror_service.dart';
import 'github_api_client.dart';
import 'github_note_storage.dart';

class MirrorNoteStorage implements NoteStorage {
  final GitHubApiClient apiClient;
  final GitMirrorService mirrorService;

  final Map<String, String> _shaCache = {};
  final Map<String, Note> _noteCache = {};
  final Map<String, String> _idToPath = {};

  MirrorNoteStorage({required this.apiClient, required this.mirrorService});

  void clearCache() {
    _shaCache.clear();
    _noteCache.clear();
    _idToPath.clear();
  }

  String get _notesDir => '${mirrorService.localPath}/notes';

  static String _sanitizeTitle(String title) {
    return title.replaceAll(RegExp(r'[/\\:*?"<>|]'), '');
  }

  String _buildRepoPath(Note note) {
    final yearMonth =
        '${note.noteDate.year}-${note.noteDate.month.toString().padLeft(2, '0')}';
    final day = note.noteDate.day.toString().padLeft(2, '0');
    final sanitized = _sanitizeTitle(note.title);
    final filename = sanitized.isEmpty ? note.id : sanitized;
    return 'notes/$yearMonth/$day/$filename.md';
  }

  String _buildLocalPath(Note note) {
    return '${mirrorService.localPath}/${_buildRepoPath(note)}';
  }

  String _dayDirPath(DateTime date) {
    final yearMonth = '${date.year}-${date.month.toString().padLeft(2, '0')}';
    final day = date.day.toString().padLeft(2, '0');
    return '$_notesDir/$yearMonth/$day';
  }

  String _monthDirPath(String yearMonth) {
    return '$_notesDir/$yearMonth';
  }

  String _repoPathFromLocal(String localPath) {
    final prefix = '${mirrorService.localPath}/';
    if (localPath.startsWith(prefix)) {
      return localPath.substring(prefix.length);
    }
    return localPath;
  }

  Future<String?> _readShaRecord(String repoPath) async {
    final shaFile = File('${mirrorService.localPath}/.shas/$repoPath');
    if (await shaFile.exists()) {
      return shaFile.readAsString();
    }
    return null;
  }

  Future<void> _writeShaRecord(String repoPath, String sha) async {
    final shaFile = File('${mirrorService.localPath}/.shas/$repoPath');
    if (!shaFile.parent.existsSync()) {
      await shaFile.parent.create(recursive: true);
    }
    await shaFile.writeAsString(sha);
  }

  Future<void> _deleteShaRecord(String repoPath) async {
    final shaFile = File('${mirrorService.localPath}/.shas/$repoPath');
    if (await shaFile.exists()) {
      await shaFile.delete();
    }
  }

  Future<void> _loadShaCacheForPath(String repoPath) async {
    if (_shaCache.containsKey(repoPath)) return;
    final sha = await _readShaRecord(repoPath);
    if (sha != null) {
      _shaCache[repoPath] = sha;
    }
  }

  @override
  Future<List<Note>> listMemoNotes() async {
    final all = await listAllNotes();
    return all.where((n) => n.isMemo).toList();
  }

  @override
  Future<List<Note>> listAllNotes() async {
    final rootDir = Directory(_notesDir);
    if (!await rootDir.exists()) return [];

    final notes = <Note>[];
    await for (final entity in rootDir.list()) {
      if (entity is! Directory) continue;

      final yearMonth = entity.path.split(Platform.pathSeparator).last;
      if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(yearMonth)) continue;

      final dates = await listDates(yearMonth);
      for (final date in dates) {
        notes.addAll(await listNotes(date));
      }
    }

    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return notes;
  }

  @override
  Future<List<Note>> listNotes(DateTime date) async {
    final dirPath = _dayDirPath(date);
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];

    final notes = <Note>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.md')) continue;

      if (_noteCache.containsKey(entity.path)) {
        notes.add(_noteCache[entity.path]!);
        continue;
      }

      final content = await entity.readAsString();
      final note = GitHubNoteStorage.parseNote(content);
      if (note != null) {
        notes.add(note);
        _noteCache[entity.path] = note;
        _idToPath[note.id] = entity.path;

        final repoPath = _repoPathFromLocal(entity.path);
        await _loadShaCacheForPath(repoPath);
      }
    }
    return notes;
  }

  @override
  Future<List<DateTime>> listDates(String yearMonth) async {
    final dirPath = _monthDirPath(yearMonth);
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];

    final parts = yearMonth.split('-');
    if (parts.length != 2) return [];
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null) return [];

    final dates = <DateTime>[];
    await for (final entity in dir.list()) {
      if (entity is! Directory) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      final day = int.tryParse(name);
      if (day == null) continue;
      dates.add(DateTime(year, month, day));
    }
    dates.sort((a, b) => a.compareTo(b));
    return dates;
  }

  @override
  Future<Note?> getNote(String noteId, DateTime noteDate) async {
    final cachedPath = _idToPath[noteId];
    if (cachedPath != null && _noteCache.containsKey(cachedPath)) {
      return _noteCache[cachedPath];
    }
    final notes = await listNotes(noteDate);
    final match = notes.where((n) => n.id == noteId);
    return match.isEmpty ? null : match.first;
  }

  @override
  Future<void> saveNote(Note note) async {
    final repoPath = _buildRepoPath(note);
    final localPath = _buildLocalPath(note);
    final markdown = GitHubNoteStorage.serializeNote(note);

    final oldLocalPath = _idToPath[note.id];
    if (oldLocalPath != null && oldLocalPath != localPath) {
      final oldRepoPath = _repoPathFromLocal(oldLocalPath);
      final oldSha = _shaCache[oldRepoPath] ?? await _readShaRecord(oldRepoPath);

      final oldFile = File(oldLocalPath);
      if (await oldFile.exists()) await oldFile.delete();
      _noteCache.remove(oldLocalPath);
      _idToPath.remove(note.id);

      if (oldSha != null) {
        try {
          await apiClient.deleteFile(
            path: oldRepoPath,
            sha: oldSha,
            message: 'Delete renamed note: ${note.title}',
          );
        } on GitHubApiException {
          // Ignore - file may already be gone or SHA stale.
        }
      }
      _shaCache.remove(oldRepoPath);
      await _deleteShaRecord(oldRepoPath);
    }

    final file = File(localPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(markdown);

    final cachedSha = _shaCache[repoPath] ?? await _readShaRecord(repoPath);

    try {
      final newSha = await apiClient.putFile(
        path: repoPath,
        content: markdown,
        message: 'Save note: ${note.title}',
        sha: cachedSha,
      );
      _shaCache[repoPath] = newSha;
      await _writeShaRecord(repoPath, newSha);
    } on GitHubConflictException {
      try {
        final latest = await apiClient.getFile(repoPath);
        final newSha = await apiClient.putFile(
          path: repoPath,
          content: markdown,
          message: 'Save note: ${note.title}',
          sha: latest.sha,
        );
        _shaCache[repoPath] = newSha;
        await _writeShaRecord(repoPath, newSha);
      } catch (_) {
        // Local file is saved; sync will reconcile later.
      }
    } catch (_) {
      // API write failed but local file is saved. Sync will reconcile.
    }

    _noteCache[localPath] = note;
    _idToPath[note.id] = localPath;
  }

  @override
  Future<void> deleteNote(Note note) async {
    final repoPath = _buildRepoPath(note);
    final localPath = _buildLocalPath(note);

    final file = File(localPath);
    if (await file.exists()) await file.delete();
    _noteCache.remove(localPath);
    _idToPath.remove(note.id);

    final sha = _shaCache[repoPath] ?? await _readShaRecord(repoPath);

    if (sha != null) {
      try {
        await apiClient.deleteFile(
          path: repoPath,
          sha: sha,
          message: 'Delete note: ${note.title}',
        );
      } on GitHubApiException {
        // Ignore - file may already be gone.
      }
    } else {
      try {
        final remoteFile = await apiClient.getFile(repoPath);
        await apiClient.deleteFile(
          path: repoPath,
          sha: remoteFile.sha,
          message: 'Delete note: ${note.title}',
        );
      } on GitHubNotFoundException {
        // File doesn't exist on remote, nothing to delete.
      } catch (_) {
        // API failed; sync will reconcile.
      }
    }

    _shaCache.remove(repoPath);
    await _deleteShaRecord(repoPath);
  }
}
