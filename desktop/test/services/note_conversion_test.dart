import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/services/note_conversion.dart';
import 'package:simsync/storage/note_storage.dart';

/// 인메모리 스토리지. 노트와 바이너리 자산을 맵에 담고, noteDirPath 규칙을
/// 주입받아 로컬(`YYYY-MM-DD`) vs synced(`notes/YYYY-MM/DD`) 차이를 재현한다.
class _FakeStorage implements NoteStorage {
  _FakeStorage(this._dirPattern);

  final String Function(DateTime) _dirPattern;
  final Map<String, Note> notes = {};
  final Map<String, Uint8List> files = {};
  final List<String> deleted = [];

  @override
  String noteDirPath(DateTime noteDate) => _dirPattern(noteDate);

  @override
  Future<void> saveNote(Note note) async {
    notes[note.id] = note;
  }

  @override
  Future<void> deleteNote(Note note) async {
    notes.remove(note.id);
    deleted.add(note.id);
  }

  @override
  Future<Uint8List?> readBinaryFile(String relativePath) async =>
      files[relativePath];

  @override
  Future<void> writeBinaryFile(String relativePath, Uint8List bytes) async {
    files[relativePath] = bytes;
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

Note _localNote(String content) {
  final now = DateTime(2026, 7, 21, 9);
  return Note(
    id: 'local-1',
    noteDate: DateTime(2026, 7, 21),
    title: 'my note',
    content: content,
    isDefault: false,
    tags: const ['a', 'b'],
    createdAt: now,
    updatedAt: now,
    storageType: StorageType.local,
  );
}

String _localDir(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _syncedDir(DateTime d) =>
    'notes/${d.year}-${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

void main() {
  final png = Uint8List.fromList([1, 2, 3, 4]);

  test('노트를 synced에 저장하고 로컬에서 삭제하며 storageType을 바꾼다', () async {
    final local = _FakeStorage(_localDir)..notes['local-1'] = _localNote('hi');
    final synced = _FakeStorage(_syncedDir);

    final result = await convertLocalNoteToSynced(
        note: _localNote('hi'), local: local, synced: synced);

    expect(result.note.storageType, StorageType.synced);
    expect(result.note.id, 'local-1');
    expect(result.note.content, 'hi');
    expect(result.note.tags, ['a', 'b']);
    expect(synced.notes['local-1']!.storageType, StorageType.synced);
    expect(local.deleted, ['local-1']);
    expect(result.failedAssets, isEmpty);
  });

  test('이미지 자산을 각 스토리지의 noteDirPath로 복사한다', () async {
    const img = '<img src="assets/a.png" width="100" height="80">';
    final note = _localNote('before\n$img\nafter');
    final local = _FakeStorage(_localDir);
    local.files['2026-07-21/assets/a.png'] = png;
    final synced = _FakeStorage(_syncedDir);

    final result =
        await convertLocalNoteToSynced(note: note, local: local, synced: synced);

    expect(synced.files['notes/2026-07/21/assets/a.png'], png);
    expect(result.failedAssets, isEmpty);
  });

  test('없는 이미지는 failedAssets에 담고 전환은 계속한다', () async {
    const img = '<img src="assets/missing.png" width="10" height="10">';
    final note = _localNote(img);
    final local = _FakeStorage(_localDir); // 파일 없음
    final synced = _FakeStorage(_syncedDir);

    final result =
        await convertLocalNoteToSynced(note: note, local: local, synced: synced);

    expect(result.failedAssets, ['assets/missing.png']);
    expect(synced.notes['local-1'], isNotNull); // 전환 자체는 성공
    expect(local.deleted, ['local-1']);
  });

  test('외부 URL 이미지는 복사하지 않고 실패로도 치지 않는다', () async {
    const img = '<img src="https://x.com/a.png" width="10" height="10">';
    final note = _localNote(img);
    final local = _FakeStorage(_localDir);
    final synced = _FakeStorage(_syncedDir);

    final result =
        await convertLocalNoteToSynced(note: note, local: local, synced: synced);

    expect(result.failedAssets, isEmpty);
    expect(synced.files, isEmpty);
  });

  test('synced 저장이 실패하면 예외를 던지고 로컬을 지우지 않는다', () async {
    final note = _localNote('hi');
    final local = _FakeStorage(_localDir)..notes['local-1'] = note;
    final synced = _ThrowingSyncedStorage(_syncedDir);

    await expectLater(
      convertLocalNoteToSynced(note: note, local: local, synced: synced),
      throwsA(isA<StateError>()),
    );
    // 로컬 원본이 보존되어야 한다 (유실 없음).
    expect(local.deleted, isEmpty);
  });

  group('convertSyncedNoteToLocal (반대 방향)', () {
    Note syncedNote(String content) {
      final now = DateTime(2026, 7, 21, 9);
      return Note(
        id: 'synced-1',
        noteDate: DateTime(2026, 7, 21),
        title: 'my note',
        content: content,
        isDefault: true,
        tags: const ['x'],
        createdAt: now,
        updatedAt: now,
        storageType: StorageType.synced,
      );
    }

    test('노트를 로컬에 저장하고 synced에서 삭제하며 storageType을 바꾼다', () async {
      final note = syncedNote('hello');
      final synced = _FakeStorage(_syncedDir)..notes['synced-1'] = note;
      final local = _FakeStorage(_localDir);

      final result = await convertSyncedNoteToLocal(
          note: note, synced: synced, local: local);

      expect(result.note.storageType, StorageType.local);
      expect(result.note.id, 'synced-1');
      expect(local.notes['synced-1']!.storageType, StorageType.local);
      expect(synced.deleted, ['synced-1']);
    });

    test('이미지 자산을 synced→로컬 경로로 복사한다', () async {
      const img = '<img src="assets/a.png" width="10" height="10">';
      final note = syncedNote(img);
      final synced = _FakeStorage(_syncedDir);
      synced.files['notes/2026-07/21/assets/a.png'] = png;
      final local = _FakeStorage(_localDir);

      final result = await convertSyncedNoteToLocal(
          note: note, synced: synced, local: local);

      expect(local.files['2026-07-21/assets/a.png'], png);
      expect(result.failedAssets, isEmpty);
    });

    test('원본(synced) 삭제 실패 시 대상(로컬) 저장을 롤백하고 예외를 던진다', () async {
      final note = syncedNote('hi');
      final synced = _DeleteFailingStorage(_syncedDir)..notes['synced-1'] = note;
      final local = _FakeStorage(_localDir);

      await expectLater(
        convertSyncedNoteToLocal(note: note, synced: synced, local: local),
        throwsA(isA<StateError>()),
      );
      // 롤백으로 로컬에 중복본이 남지 않아야 한다.
      expect(local.notes.containsKey('synced-1'), isFalse);
      // synced 원본은 그대로 (유실 없음).
      expect(synced.notes.containsKey('synced-1'), isTrue);
    });
  });
}

/// deleteNote가 항상 실패하는 스토리지 (롤백 검증용).
class _DeleteFailingStorage extends _FakeStorage {
  _DeleteFailingStorage(super.dirPattern);

  @override
  Future<void> deleteNote(Note note) async => throw StateError('delete failed');
}

/// saveNote가 항상 실패하는 synced 스토리지 (유실 방지 순서 검증용).
class _ThrowingSyncedStorage extends _FakeStorage {
  _ThrowingSyncedStorage(super.dirPattern);

  @override
  Future<void> saveNote(Note note) async => throw StateError('network down');
}
