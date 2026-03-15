import '../models/note.dart';

/// 동기화 충돌 해결 전략 인터페이스.
abstract class ConflictResolver {
  /// 로컬과 리모트 노트가 충돌할 때 최종 내용을 결정한다.
  Future<Note> resolve(Note local, Note remote);
}

/// Last-Write-Wins: updatedAt이 더 최신인 노트를 선택한다.
class LastWriteWinsResolver implements ConflictResolver {
  @override
  Future<Note> resolve(Note local, Note remote) async {
    return local.updatedAt.isAfter(remote.updatedAt) ? local : remote;
  }
}
