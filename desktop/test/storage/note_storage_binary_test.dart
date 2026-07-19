import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/services/note_service.dart';
import 'package:simsync/storage/local/local_note_storage.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('simsync_bin_test');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  final bytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 255, 128, 7]);

  test('LocalNoteStorage: 바이너리 왕복 + noteDirPath', () async {
    final storage = LocalNoteStorage(basePath: tmp.path);
    expect(storage.noteDirPath(DateTime(2026, 7, 19)), 'notes/2026-07/19');
    const rel = 'notes/2026-07/19/assets/img-x.png';
    expect(await storage.readBinaryFile(rel), isNull);
    await storage.writeBinaryFile(rel, bytes);
    expect(await storage.readBinaryFile(rel), bytes);
  });

  test('NoteService: 바이너리 왕복 + noteDirPath', () async {
    final storage = NoteService.forTesting(tmp.path);
    expect(storage.noteDirPath(DateTime(2026, 7, 19)), '2026-07-19');
    const rel = '2026-07-19/assets/img-x.png';
    await storage.writeBinaryFile(rel, bytes);
    expect(await storage.readBinaryFile(rel), bytes);
  });
}
