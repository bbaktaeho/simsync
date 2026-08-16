import '../models/note.dart';
import '../storage/note_storage.dart';
import 'markdown_editing.dart';

/// 노트 스토리지 전환 결과 (로컬↔동기화).
class NoteConversionResult {
  const NoteConversionResult({required this.note, required this.failedAssets});

  /// 새로 만들어진 노트 (id/content 동일, storageType이 대상에 맞게 바뀜).
  final Note note;

  /// 대상 스토리지로 복사하지 못한 이미지 src(`assets/…`) 목록. 노트 자체는
  /// 전환되며, 이 이미지들은 다시 첨부가 필요할 수 있다.
  final List<String> failedAssets;
}

/// 로컬 노트 [note]를 [synced] 스토리지로 옮긴다.
Future<NoteConversionResult> convertLocalNoteToSynced({
  required Note note,
  required NoteStorage local,
  required NoteStorage synced,
}) =>
    _convertNote(
        note: note, from: local, to: synced, toType: StorageType.synced);

/// 동기화 노트 [note]를 [local] 스토리지로 옮긴다.
Future<NoteConversionResult> convertSyncedNoteToLocal({
  required Note note,
  required NoteStorage synced,
  required NoteStorage local,
}) =>
    _convertNote(
        note: note, from: synced, to: local, toType: StorageType.local);

/// 노트를 [from] 스토리지에서 [to] 스토리지로 옮긴다.
///
/// 순서는 데이터 안전 우선이다: 참조 이미지 자산을 먼저 복사하고, 대상에
/// 저장한 뒤, 마지막에 원본을 지운다. 대상 저장이 성공한 다음에만 원본을
/// 삭제하므로 어떤 실패에서도 내용이 유실되지 않는다.
///
/// 원본 삭제가 실패하면(예: 네트워크 오류) 방금 쓴 대상 노트를 되돌리고 예외를
/// 다시 던진다 — 그렇지 않으면 노트가 양쪽에 남아 다음 동기화에서 중복되기
/// 때문이다(mergeDirtyNotes는 중복을 제거하지 않는다). 롤백 결과 원본만
/// 온전히 남아 유실도, 중복도 없다.
///
/// 이미지 복사는 파일 단위 best-effort다 — 한 장이 실패해도 전환은 계속되고,
/// 실패한 src는 [NoteConversionResult.failedAssets]로 돌려준다 (깨진 이미지는
/// 다시 첨부하면 복구되므로, 한 장 때문에 전환 전체를 막지 않는다).
Future<NoteConversionResult> _convertNote({
  required Note note,
  required NoteStorage from,
  required NoteStorage to,
  required StorageType toType,
}) async {
  final movedNote = Note(
    id: note.id,
    noteDate: note.noteDate,
    title: note.title,
    content: note.content,
    isDefault: false,
    tags: List<String>.from(note.tags),
    createdAt: note.createdAt,
    updatedAt: note.updatedAt,
    isMemo: note.isMemo,
    storageType: toType,
  );

  // 1. 참조된 이미지 자산 복사. 상대 경로(assets/…)만 옮기고, 외부 URL은
  //    그대로 둔다. 두 스토리지의 noteDirPath 규칙이 달라도(로컬 vs GitHub),
  //    상대 src가 같으므로 각자의 noteDirPath로 해석하면 된다.
  final failed = <String>[];
  final fromDir = from.noteDirPath(note.noteDate);
  final toDir = to.noteDirPath(note.noteDate);
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
      final bytes = await from.readBinaryFile('$fromDir/$src');
      if (bytes == null) {
        failed.add(src);
        continue;
      }
      await to.writeBinaryFile('$toDir/$src', bytes);
    } catch (_) {
      failed.add(src);
    }
  }

  // 2. 원본 삭제 전에 대상에 먼저 저장한다 (유실 방지).
  await to.saveNote(movedNote);

  // 3. 원본 삭제. 실패하면 대상 저장을 되돌려 중복을 막고 예외를 다시 던진다.
  try {
    await from.deleteNote(note);
  } catch (_) {
    try {
      await to.deleteNote(movedNote);
    } catch (_) {
      // 롤백까지 실패한 극단적 경우: 중복이 남을 수 있으나 유실은 없다.
    }
    rethrow;
  }

  return NoteConversionResult(note: movedNote, failedAssets: failed);
}
