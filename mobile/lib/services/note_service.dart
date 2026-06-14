import 'dart:io';

import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';

import '../models/note.dart';
import '../storage/note_storage.dart';

const _uuid = Uuid();

/// Date format used for directory names.
final _dirDateFmt = DateFormat('yyyy-MM-dd');

/// ISO 8601 with timezone for frontmatter timestamps.
final _isoFmt = DateFormat("yyyy-MM-dd'T'HH:mm:ssZ");

/// Manages note CRUD on the local filesystem.
///
/// Storage layout:
/// ```
/// ~/.simsync/documents/
/// ├── 2026-03-08/
/// │   ├── <uuid>.md
/// │   └── <uuid>.md
/// └── 2026-03-09/
///     └── <uuid>.md
/// ```
class NoteService implements NoteStorage {
  final String _basePath;

  NoteService._(this._basePath);

  /// Creates a NoteService rooted at `~/.simsync/documents/`.
  factory NoteService() {
    final home = Platform.environment['HOME'] ?? '.';
    final basePath = '$home/.simsync/documents';
    return NoteService._(basePath);
  }

  Directory get _baseDir => Directory(_basePath);

  // ── Read ──

  /// Loads all notes from disk.
  Future<List<Note>> loadAllNotes() async {
    final notes = <Note>[];
    if (!await _baseDir.exists()) return notes;

    await for (final dateDir in _baseDir.list()) {
      if (dateDir is! Directory) continue;
      await for (final file in dateDir.list()) {
        if (file is! File || !file.path.endsWith('.md')) continue;
        final note = await _parseNoteFile(file);
        if (note != null) notes.add(note);
      }
    }

    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return notes;
  }

  /// Loads notes for a specific date.
  Future<List<Note>> loadNotesByDate(DateTime date) async {
    final dirPath = _dateDirPath(date);
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];

    final notes = <Note>[];
    await for (final file in dir.list()) {
      if (file is! File || !file.path.endsWith('.md')) continue;
      final note = await _parseNoteFile(file);
      if (note != null) notes.add(note);
    }
    return notes;
  }

  // ── Write ──

  /// Saves a note to disk. Creates directories as needed.
  @override
  Future<void> saveNote(Note note) async {
    final dirPath = _dateDirPath(note.noteDate);
    await Directory(dirPath).create(recursive: true);

    final filePath = '$dirPath/${note.id}.md';
    final content = _serializeNote(note);
    await File(filePath).writeAsString(content);
  }

  /// Creates a new note and saves it. Returns the created note.
  Future<Note> createNote({
    required DateTime noteDate,
    required bool isDefault,
    String title = '',
    String content = '',
    List<String> tags = const [],
  }) async {
    final now = DateTime.now();
    final note = Note(
      id: _uuid.v4(),
      noteDate: noteDate,
      title: title,
      content: content,
      isDefault: isDefault,
      tags: List.from(tags),
      createdAt: now,
      updatedAt: now,
    );
    await saveNote(note);
    return note;
  }

  // ── Delete ──

  /// Deletes a note file from disk.
  @override
  Future<void> deleteNote(Note note) async {
    final filePath = '${_dateDirPath(note.noteDate)}/${note.id}.md';
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
    // Clean up empty date directory
    final dir = Directory(_dateDirPath(note.noteDate));
    if (await dir.exists()) {
      final remaining = await dir.list().length;
      if (remaining == 0) await dir.delete();
    }
  }

  // ── NoteStorage interface ──

  @override
  Future<List<Note>> listAllNotes() => loadAllNotes();

  @override
  Future<List<Note>> listNotes(DateTime date) => loadNotesByDate(date);

  @override
  Future<List<DateTime>> listDates(String yearMonth) async {
    if (!await _baseDir.exists()) return [];

    final dates = <DateTime>[];
    await for (final entity in _baseDir.list()) {
      if (entity is! Directory) continue;
      final dirName = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (!dirName.startsWith(yearMonth)) continue;
      try {
        dates.add(DateTime.parse(dirName));
      } catch (_) {
        // skip directories that don't parse as dates
      }
    }
    dates.sort();
    return dates;
  }

  @override
  Future<Note?> getNote(String noteId, DateTime noteDate) async {
    final filePath = '${_dateDirPath(noteDate)}/$noteId.md';
    final file = File(filePath);
    if (!await file.exists()) return null;
    return _parseNoteFile(file);
  }

  // ── Helpers ──

  String _dateDirPath(DateTime date) {
    return '$_basePath/${_dirDateFmt.format(date)}';
  }

  /// Parses a .md file with YAML frontmatter into a Note.
  Future<Note?> _parseNoteFile(File file) async {
    try {
      final raw = await file.readAsString();
      final fileName = file.uri.pathSegments.last;
      final id = fileName.replaceAll('.md', '');

      // Split frontmatter and content
      if (!raw.startsWith('---')) return null;
      final endIdx = raw.indexOf('---', 3);
      if (endIdx == -1) return null;

      final frontmatterStr = raw.substring(3, endIdx).trim();
      final content = raw.substring(endIdx + 3).trim();
      final fm = loadYaml(frontmatterStr);

      if (fm is! YamlMap) return null;

      final tags = <String>[];
      if (fm['tags'] is YamlList) {
        for (final t in fm['tags'] as YamlList) {
          tags.add(t.toString());
        }
      }

      return Note(
        id: id,
        noteDate: DateTime.parse(fm['note_date'].toString()),
        title: (fm['title'] ?? '').toString(),
        content: content,
        isDefault: fm['is_default'] == true,
        tags: tags,
        createdAt: _parseDateTime(fm['created_at']),
        updatedAt: _parseDateTime(fm['updated_at']),
        isMemo: fm['is_memo'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    try {
      return DateTime.parse(value.toString());
    } catch (_) {
      return DateTime.now();
    }
  }

  /// Serializes a Note to markdown with YAML frontmatter.
  String _serializeNote(Note note) {
    final tagsLine = note.tags.isEmpty
        ? '[]'
        : '[${note.tags.map((t) => '"$t"').join(', ')}]';

    return '''---
title: "${_escapeYaml(note.title)}"
note_date: ${_dirDateFmt.format(note.noteDate)}
is_default: ${note.isDefault}
is_memo: ${note.isMemo}
tags: $tagsLine
created_at: ${_isoFmt.format(note.createdAt)}
updated_at: ${_isoFmt.format(note.updatedAt)}
---
${note.content}''';
  }

  String _escapeYaml(String value) {
    return value.replaceAll('"', '\\"');
  }
}
