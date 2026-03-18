import 'dart:async';
import 'dart:io';

import '../../models/note.dart';
import '../note_storage.dart';
import 'git_service.dart';
import 'github_api_client.dart';
import 'github_note_storage.dart';

class GitRepoNoteStorage implements NoteStorage {
  final GitService gitService;
  final GitHubApiClient apiClient;

  final Map<String, Note> _noteCache = {};
  final Map<String, String> _idToPath = {};

  GitRepoNoteStorage({required this.gitService, required this.apiClient});

  void clearCache() {
    _noteCache.clear();
    _idToPath.clear();
  }

  String get _notesDir => '${gitService.localPath}/notes';

  String _sanitizeTitle(String title) {
    return title.replaceAll(RegExp(r'[/\\:*?"<>|]'), '');
  }

  String _buildPath(Note note) {
    final yearMonth =
        '${note.noteDate.year}-${note.noteDate.month.toString().padLeft(2, '0')}';
    final day = note.noteDate.day.toString().padLeft(2, '0');
    final sanitized = _sanitizeTitle(note.title);
    final filename = sanitized.isEmpty ? note.id : sanitized;
    return '${gitService.localPath}/notes/$yearMonth/$day/$filename.md';
  }

  String _buildRelativePath(Note note) {
    final yearMonth =
        '${note.noteDate.year}-${note.noteDate.month.toString().padLeft(2, '0')}';
    final day = note.noteDate.day.toString().padLeft(2, '0');
    final sanitized = _sanitizeTitle(note.title);
    final filename = sanitized.isEmpty ? note.id : sanitized;
    return 'notes/$yearMonth/$day/$filename.md';
  }

  String _dayDirPath(DateTime date) {
    final yearMonth = '${date.year}-${date.month.toString().padLeft(2, '0')}';
    final day = date.day.toString().padLeft(2, '0');
    return '$_notesDir/$yearMonth/$day';
  }

  String _monthDirPath(String yearMonth) {
    return '$_notesDir/$yearMonth';
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
    final yearMonthPattern = RegExp(r'^\d{4}-\d{2}$');
    await for (final entity in rootDir.list()) {
      if (entity is! Directory) continue;

      final yearMonth = entity.path.split(Platform.pathSeparator).last;
      if (!yearMonthPattern.hasMatch(yearMonth)) continue;
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
    if (!gitService.isCloned()) {
      await _saveNoteViaApi(note);
      return;
    }

    final path = _buildPath(note);
    final oldPath = _idToPath[note.id];
    if (oldPath != null && oldPath != path) {
      final oldFile = File(oldPath);
      if (await oldFile.exists()) await oldFile.delete();
      _noteCache.remove(oldPath);
      _idToPath.remove(note.id);
    }

    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(GitHubNoteStorage.serializeNote(note));
    _noteCache[path] = note;
    _idToPath[note.id] = path;

    await gitService.addAll();
    await gitService.commit('Save note: ${note.title}');
    unawaited(gitService.push());
  }

  @override
  Future<void> deleteNote(Note note) async {
    if (!gitService.isCloned()) {
      await _deleteNoteViaApi(note);
      return;
    }

    final path = _buildPath(note);
    final file = File(path);
    if (await file.exists()) await file.delete();
    _noteCache.remove(path);
    _idToPath.remove(note.id);

    await gitService.addAll();
    await gitService.commit('Delete note: ${note.title}');
    unawaited(gitService.push());
  }

  Future<void> _saveNoteViaApi(Note note) async {
    final relativePath = _buildRelativePath(note);
    final markdown = GitHubNoteStorage.serializeNote(note);

    String? existingSha;
    try {
      final existing = await apiClient.getFile(relativePath);
      existingSha = existing.sha;
    } on GitHubNotFoundException {
      // New file
    }

    try {
      await apiClient.putFile(
        path: relativePath,
        content: markdown,
        message: 'Save note: ${note.title}',
        sha: existingSha,
      );
    } on GitHubConflictException {
      final latest = await apiClient.getFile(relativePath);
      await apiClient.putFile(
        path: relativePath,
        content: markdown,
        message: 'Save note: ${note.title}',
        sha: latest.sha,
      );
    }
  }

  Future<void> _deleteNoteViaApi(Note note) async {
    final relativePath = _buildRelativePath(note);
    try {
      final file = await apiClient.getFile(relativePath);
      await apiClient.deleteFile(
        path: relativePath,
        sha: file.sha,
        message: 'Delete note: ${note.title}',
      );
    } on GitHubNotFoundException {
      // Already gone
    }
  }
}
