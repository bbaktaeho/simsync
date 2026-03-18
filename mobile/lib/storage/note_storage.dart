import '../models/note.dart';

/// 노트 저장소 추상 인터페이스.
/// 구현체에 따라 로컬 파일, GitHub, S3 등 다양한 백엔드를 지원한다.
abstract class NoteStorage {
  /// 저장소의 전체 노트 목록 조회.
  Future<List<Note>> listAllNotes();

  /// 메모 노트 목록 조회 (isMemo == true).
  Future<List<Note>> listMemoNotes();

  /// 특정 날짜의 노트 목록 조회.
  Future<List<Note>> listNotes(DateTime date);

  /// 특정 월(yearMonth)에 노트가 존재하는 날짜 목록 조회.
  /// yearMonth 형식: "2026-03"
  Future<List<DateTime>> listDates(String yearMonth);

  /// 노트 내용 읽기.
  Future<Note?> getNote(String noteId, DateTime noteDate);

  /// 노트 생성/수정.
  Future<void> saveNote(Note note);

  /// 노트 삭제.
  Future<void> deleteNote(Note note);
}
