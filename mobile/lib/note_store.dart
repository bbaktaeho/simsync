import 'dart:io';
import 'package:path_provider/path_provider.dart';

class Note {
  String id;
  String noteDate;
  String title;
  String content;
  bool isDefault;
  String createdAt;
  String updatedAt;

  Note({
    required this.id,
    required this.noteDate,
    required this.title,
    required this.content,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
  });
}

class NoteMeta {
  final String id;
  final String title;
  final bool isDefault;
  final String updatedAt;

  NoteMeta({
    required this.id,
    required this.title,
    required this.isDefault,
    required this.updatedAt,
  });
}

/// NoteStore mirrors the Go notecore package logic for local file storage.
/// Will be replaced with API calls or gomobile bind in MVP-002/003.
class NoteStore {
  late String _dataDir;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    final dir = await getApplicationDocumentsDirectory();
    _dataDir = '${dir.path}/simsync/documents';
    await Directory(_dataDir).create(recursive: true);
    _initialized = true;
  }

  Future<Note> saveNote(String noteDate, String id, String title, String content) async {
    await init();

    final dateDir = '$_dataDir/$noteDate';
    await Directory(dateDir).create(recursive: true);

    final now = DateTime.now().toIso8601String();
    final isNew = id.isEmpty;

    if (isNew) {
      id = DateTime.now().microsecondsSinceEpoch.toString();
    }

    final filePath = '$dateDir/$id.md';

    bool isDefault = false;
    String createdAt = now;

    if (isNew) {
      final existing = await listNotesByDate(noteDate);
      isDefault = existing.isEmpty;
    } else {
      try {
        final existing = await loadNote(noteDate, id);
        isDefault = existing.isDefault;
        createdAt = existing.createdAt;
      } catch (_) {}
    }

    final data = '---\n'
        'title: $title\n'
        'note_date: $noteDate\n'
        'is_default: $isDefault\n'
        'created_at: $createdAt\n'
        'updated_at: $now\n'
        '---\n'
        '$content';

    await File(filePath).writeAsString(data);

    return Note(
      id: id,
      noteDate: noteDate,
      title: title,
      content: content,
      isDefault: isDefault,
      createdAt: createdAt,
      updatedAt: now,
    );
  }

  Future<Note> loadNote(String noteDate, String id) async {
    await init();
    final filePath = '$_dataDir/$noteDate/$id.md';
    final raw = await File(filePath).readAsString();
    return _parseNote(id, raw);
  }

  Future<List<NoteMeta>> listNotesByDate(String noteDate) async {
    await init();
    final dateDir = Directory('$_dataDir/$noteDate');
    if (!await dateDir.exists()) return [];

    final notes = <NoteMeta>[];
    await for (final entity in dateDir.list()) {
      if (entity is File && entity.path.endsWith('.md')) {
        final id = entity.uri.pathSegments.last.replaceAll('.md', '');
        final raw = await entity.readAsString();
        final note = _parseNote(id, raw);
        notes.add(NoteMeta(
          id: note.id,
          title: note.title,
          isDefault: note.isDefault,
          updatedAt: note.updatedAt,
        ));
      }
    }

    notes.sort((a, b) {
      if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
      return a.id.compareTo(b.id);
    });

    return notes;
  }

  Future<void> deleteNote(String noteDate, String id) async {
    await init();
    final file = File('$_dataDir/$noteDate/$id.md');
    if (await file.exists()) await file.delete();

    final dateDir = Directory('$_dataDir/$noteDate');
    if (await dateDir.exists()) {
      final remaining = await dateDir.list().length;
      if (remaining == 0) await dateDir.delete();
    }
  }

  Future<List<String>> getMonthNotes(int year, int month) async {
    await init();
    final dir = Directory(_dataDir);
    if (!await dir.exists()) return [];

    final prefix = '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-';
    final dates = <String>[];

    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final name = entity.uri.pathSegments[entity.uri.pathSegments.length - 2];
        if (name.startsWith(prefix)) {
          bool hasNotes = false;
          await for (final file in entity.list()) {
            if (file is File && file.path.endsWith('.md')) {
              hasNotes = true;
              break;
            }
          }
          if (hasNotes) dates.add(name);
        }
      }
    }

    dates.sort();
    return dates;
  }

  Note _parseNote(String id, String raw) {
    final note = Note(
      id: id,
      noteDate: '',
      title: 'Untitled',
      content: '',
      isDefault: false,
      createdAt: '',
      updatedAt: '',
    );

    if (!raw.startsWith('---\n')) {
      note.content = raw;
      return note;
    }

    final endIndex = raw.indexOf('\n---\n', 4);
    if (endIndex == -1) {
      note.content = raw;
      return note;
    }

    final frontmatter = raw.substring(4, endIndex);
    note.content = raw.substring(endIndex + 5);

    for (final line in frontmatter.split('\n')) {
      final colonIndex = line.indexOf(': ');
      if (colonIndex == -1) continue;
      final key = line.substring(0, colonIndex);
      final val = line.substring(colonIndex + 2);
      switch (key) {
        case 'title':
          note.title = val;
        case 'note_date':
          note.noteDate = val;
        case 'is_default':
          note.isDefault = val == 'true';
        case 'created_at':
          note.createdAt = val;
        case 'updated_at':
          note.updatedAt = val;
      }
    }

    if (note.title.isEmpty) note.title = 'Untitled';
    return note;
  }
}
