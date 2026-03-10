import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/storage/github/repo_cache.dart';

void main() {
  late Directory tempDir;
  late String filePath;
  late RepoCache cache;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('repo_cache_test_');
    filePath = '${tempDir.path}/repos.json';
    cache = RepoCache.withPath(filePath);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('load returns empty list when file missing', () async {
    final entries = await cache.load();
    expect(entries, isEmpty);
  });

  test('add and load round-trip', () async {
    final entry = RepoEntry(
      owner: 'alice',
      repo: 'notes',
      branch: 'main',
      connectedAt: DateTime.utc(2026, 3, 10),
    );

    await cache.add(entry);
    final entries = await cache.load();

    expect(entries, hasLength(1));
    expect(entries.first.owner, 'alice');
    expect(entries.first.repo, 'notes');
    expect(entries.first.branch, 'main');
    expect(entries.first.fullName, 'alice/notes');
    expect(entries.first.connectedAt, DateTime.utc(2026, 3, 10));
  });

  test('add replaces duplicate owner/repo and keeps latest first', () async {
    final old = RepoEntry(
      owner: 'alice',
      repo: 'notes',
      branch: 'dev',
      connectedAt: DateTime.utc(2026, 1, 1),
    );
    final newer = RepoEntry(
      owner: 'alice',
      repo: 'notes',
      branch: 'main',
      connectedAt: DateTime.utc(2026, 3, 10),
    );
    final other = RepoEntry(
      owner: 'bob',
      repo: 'docs',
      connectedAt: DateTime.utc(2026, 2, 1),
    );

    await cache.add(old);
    await cache.add(other);
    await cache.add(newer);

    final entries = await cache.load();
    expect(entries, hasLength(2));
    // newest add is first
    expect(entries[0].owner, 'alice');
    expect(entries[0].branch, 'main');
    expect(entries[1].owner, 'bob');
  });

  test('remove deletes entry by owner/repo', () async {
    await cache.add(RepoEntry(owner: 'alice', repo: 'notes'));
    await cache.add(RepoEntry(owner: 'bob', repo: 'docs'));

    await cache.remove('alice', 'notes');

    final entries = await cache.load();
    expect(entries, hasLength(1));
    expect(entries.first.owner, 'bob');
  });

  test('load returns empty on corrupt file', () async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString('not valid json {{{');

    final entries = await cache.load();
    expect(entries, isEmpty);
  });
}
