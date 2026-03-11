import 'dart:io';

import '../../models/note.dart';
import '../note_storage.dart';
import '../github/github_note_storage.dart'; // reuse parseNote, serializeNote

/// NoteStorage implementation backed by the local file system.
/// Notes stored as markdown with YAML frontmatter at:
///   {basePath}/notes/{YYYY-MM}/{DD}/{title}.md
class LocalNoteStorage implements NoteStorage {
  final String basePath;
  final Map<String, Note> _noteCache = {};
  final Map<String, String> _idToPath = {};

  LocalNoteStorage({required this.basePath});

  String _sanitizeTitle(String title) {
    return title.replaceAll(RegExp(r'[/\\:*?"<>|]'), '');
  }

  String _buildPath(Note note) {
    final yearMonth =
        '${note.noteDate.year}-${note.noteDate.month.toString().padLeft(2, '0')}';
    final day = note.noteDate.day.toString().padLeft(2, '0');
    final sanitized = _sanitizeTitle(note.title);
    final filename = sanitized.isEmpty ? note.id : sanitized;
    return '$basePath/notes/$yearMonth/$day/$filename.md';
  }

  String _dayDirPath(DateTime date) {
    final yearMonth =
        '${date.year}-${date.month.toString().padLeft(2, '0')}';
    final day = date.day.toString().padLeft(2, '0');
    return '$basePath/notes/$yearMonth/$day';
  }

  String _monthDirPath(String yearMonth) {
    return '$basePath/notes/$yearMonth';
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
        final localNote = Note(
          id: note.id,
          noteDate: note.noteDate,
          title: note.title,
          content: note.content,
          isDefault: note.isDefault,
          tags: note.tags,
          createdAt: note.createdAt,
          updatedAt: note.updatedAt,
          storageType: StorageType.local,
        );
        notes.add(localNote);
        _noteCache[entity.path] = localNote;
        _idToPath[localNote.id] = entity.path;
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
  }

  @override
  Future<void> deleteNote(Note note) async {
    final path = _buildPath(note);
    final file = File(path);
    if (await file.exists()) await file.delete();
    _noteCache.remove(path);
    _idToPath.remove(note.id);
  }
}
