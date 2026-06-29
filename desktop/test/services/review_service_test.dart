import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/services/review_service.dart';
import 'package:simsync/storage/note_storage.dart';

/// Minimal in-memory NoteStorage that only implements the text-file API used by
/// ReviewService; everything else routes to noSuchMethod (never called here).
class _MemStorage implements NoteStorage {
  final Map<String, String> files = {};
  bool throwOnRead = false;

  @override
  Future<String?> readTextFile(String relativePath) async {
    if (throwOnRead) throw Exception('network');
    return files[relativePath];
  }

  @override
  Future<void> writeTextFile(String relativePath, String content) async {
    files[relativePath] = content;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  final monday = DateTime(2026, 6, 1);
  const path = 'notes/2026-06/1주차/weekly-review.md';

  test('saveWeekly writes to both stores at the weekly path', () async {
    final remote = _MemStorage();
    final local = _MemStorage();
    final svc = ReviewService(storage: remote, localStorage: local);

    await svc.saveWeekly(monday, '# Review');

    expect(remote.files[path], '# Review');
    expect(local.files[path], '# Review');
  });

  test('loadWeekly prefers the synced store', () async {
    final remote = _MemStorage()..files[path] = 'remote';
    final local = _MemStorage()..files[path] = 'local';
    final svc = ReviewService(storage: remote, localStorage: local);

    expect(await svc.loadWeekly(monday), 'remote');
  });

  test('loadWeekly falls back to local when synced is empty', () async {
    final remote = _MemStorage();
    final local = _MemStorage()..files[path] = 'local';
    final svc = ReviewService(storage: remote, localStorage: local);

    expect(await svc.loadWeekly(monday), 'local');
  });

  test('loadWeekly falls back to local when the synced read throws', () async {
    final remote = _MemStorage()..throwOnRead = true;
    final local = _MemStorage()..files[path] = 'local';
    final svc = ReviewService(storage: remote, localStorage: local);

    expect(await svc.loadWeekly(monday), 'local');
  });

  test('loadWeekly returns null when nothing is saved', () async {
    final svc =
        ReviewService(storage: _MemStorage(), localStorage: _MemStorage());

    expect(await svc.loadWeekly(monday), isNull);
  });

  test('works without a local store', () async {
    final remote = _MemStorage();
    final svc = ReviewService(storage: remote);

    await svc.saveWeekly(monday, '# R');

    expect(remote.files[path], '# R');
    expect(await svc.loadWeekly(monday), '# R');
  });
}
