import '../models/note.dart';
import '../storage/note_storage.dart';
import 'markdown_editing.dart';

/// 로컬 노트를 동기화 노트로 전환한 결과.
class NoteConversionResult {
  const NoteConversionResult({required this.note, required this.failedAssets});

  /// 새로 만들어진 동기화 노트 (id/content 동일, storageType == synced).
  final Note note;

  /// synced 스토리지로 복사하지 못한 이미지 src(`assets/…`) 목록. 노트 자체는
  /// 전환되며, 이 이미지들은 다시 첨부가 필요할 수 있다.
  final List<String> failedAssets;
}

/// 로컬 노트 [note]를 [synced] 스토리지로 옮긴다.
///
/// 순서는 데이터 안전 우선이다: 참조 이미지 자산을 먼저 복사하고, synced에
/// 저장한 뒤, 마지막에 [local]에서 원본을 지운다. synced 저장이 성공한 다음에만
/// 로컬을 삭제하므로 어떤 실패에서도 내용이 유실되지 않는다.
///
/// 이미지 복사는 파일 단위 best-effort다 — 한 장이 실패해도 전환은 계속되고,
/// 실패한 src는 [NoteConversionResult.failedAssets]로 돌려준다 (깨진 이미지는
/// 다시 첨부하면 복구되므로, 한 장 때문에 전환 전체를 막지 않는다).
Future<NoteConversionResult> convertLocalNoteToSynced({
  required Note note,
  required NoteStorage local,
  required NoteStorage synced,
}) async {
  final syncedNote = Note(
    id: note.id,
    noteDate: note.noteDate,
    title: note.title,
    content: note.content,
    isDefault: false,
    tags: List<String>.from(note.tags),
    createdAt: note.createdAt,
    updatedAt: note.updatedAt,
    isMemo: note.isMemo,
    storageType: StorageType.synced,
  );

  // 1. 참조된 이미지 자산 복사. 상대 경로(assets/…)만 옮기고, 외부 URL은
  //    그대로 둔다. 두 스토리지의 noteDirPath 규칙이 달라도(로컬 vs GitHub),
  //    상대 src가 같으므로 각자의 noteDirPath로 해석하면 된다.
  final failed = <String>[];
  final localDir = local.noteDirPath(note.noteDate);
  final syncedDir = synced.noteDirPath(note.noteDate);
  final seen = <String>{};
  for (final region in findImageRegions(note.content)) {
    final src = region.src;
    if (!seen.add(src)) continue; // 같은 이미지 중복 복사 방지
    if (src.startsWith('http://') || src.startsWith('https://')) continue;
    if (src.contains('..')) {
      failed.add(src); // 경로 탈출 방지
      continue;
    }
    try {
      final bytes = await local.readBinaryFile('$localDir/$src');
      if (bytes == null) {
        failed.add(src);
        continue;
      }
      await synced.writeBinaryFile('$syncedDir/$src', bytes);
    } catch (_) {
      failed.add(src);
    }
  }

  // 2. 로컬 삭제 전에 synced에 먼저 저장한다 (유실 방지).
  await synced.saveNote(syncedNote);

  // 3. 원본 로컬 노트 삭제. 여기서 실패하면 잠시 중복본이 남지만(다음 로드에서
  //    정리됨) 내용 유실은 없다 — 전환 자체는 성공으로 처리한다.
  try {
    await local.deleteNote(note);
  } catch (_) {
    // non-fatal
  }

  return NoteConversionResult(note: syncedNote, failedAssets: failed);
}
