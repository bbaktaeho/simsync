import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/services/image_asset_service.dart';
import 'package:simsync/storage/note_storage.dart';

/// 인메모리 NoteStorage — 바이너리 API만 실동작, 노트 API는 미사용.
class _FakeStorage implements NoteStorage {
  final Map<String, Uint8List> files = {};
  int reads = 0;

  @override
  String noteDirPath(DateTime noteDate) =>
      'notes/${noteDate.year}-${noteDate.month.toString().padLeft(2, '0')}/${noteDate.day.toString().padLeft(2, '0')}';

  @override
  Future<Uint8List?> readBinaryFile(String relativePath) async {
    reads++;
    return files[relativePath];
  }

  @override
  Future<void> writeBinaryFile(String relativePath, Uint8List bytes) async {
    files[relativePath] = bytes;
  }

  // 이하 미사용 멤버
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final bytes = Uint8List.fromList([1, 2, 3, 4]);
  final date = DateTime(2026, 7, 19);

  test('saveImage는 날짜 디렉토리 assets/에 쓰고 상대 src를 돌려준다', () async {
    final storage = _FakeStorage();
    final service = ImageAssetService(storage: storage);
    final src = await service.saveImage(
        noteDate: date, bytes: bytes, extension: 'png');
    expect(src, startsWith('assets/img-'));
    expect(src, endsWith('.png'));
    expect(storage.files.keys.single, 'notes/2026-07/19/$src');
  });

  test('loadImage는 메모리 캐시를 사용한다 (두번째 호출은 스토리지 미접근)', () async {
    final storage = _FakeStorage();
    storage.files['notes/2026-07/19/assets/a.png'] = bytes;
    final service = ImageAssetService(storage: storage);
    expect(await service.loadImage(noteDate: date, src: 'assets/a.png'), bytes);
    expect(await service.loadImage(noteDate: date, src: 'assets/a.png'), bytes);
    expect(storage.reads, 1);
  });

  test('경로 탈출 src는 거부한다', () async {
    final service = ImageAssetService(storage: _FakeStorage());
    expect(await service.loadImage(noteDate: date, src: '../../secret.png'),
        isNull);
  });

  test('없는 이미지는 null', () async {
    final service = ImageAssetService(storage: _FakeStorage());
    expect(await service.loadImage(noteDate: date, src: 'assets/nope.png'),
        isNull);
  });
}
