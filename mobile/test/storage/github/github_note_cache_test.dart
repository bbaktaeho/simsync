import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simsync_mobile/storage/github/github_note_cache.dart';

void main() {
  test('a failed disk write never poisons subsequent saves', () async {
    final dir = await Directory.systemTemp.createTemp('simsync_cache_test_');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/cache.json';

    // Block the destination with a DIRECTORY so the tmp → path rename fails
    // with a FileSystemException.
    await Directory(path).create();

    final cache = GitHubNoteCache(path: path);
    cache.lastCommitSha = 'sha-one';
    // Must swallow the failure — a throw here would leave a failed future in
    // the save chain and silently kill every later save.
    await cache.flush();

    // Unblock and save again: the chain must still be alive.
    await Directory(path).delete();
    cache.lastCommitSha = 'sha-two';
    await cache.flush();

    final reloaded = GitHubNoteCache(path: path);
    await reloaded.load();
    expect(reloaded.lastCommitSha, 'sha-two');
  });

  test('round-trips lastCommitSha and file entries through disk', () async {
    final dir = await Directory.systemTemp.createTemp('simsync_cache_test_');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/cache.json';

    final cache = GitHubNoteCache(path: path);
    cache.lastCommitSha = 'commit-1';
    cache.files['notes/2026-06/01/A.md'] =
        const GitHubNoteCacheEntry(sha: 'sha-a', markdown: '# A');
    await cache.flush();

    final reloaded = GitHubNoteCache(path: path);
    await reloaded.load();
    expect(reloaded.lastCommitSha, 'commit-1');
    expect(reloaded.files['notes/2026-06/01/A.md']?.sha, 'sha-a');
    expect(reloaded.files['notes/2026-06/01/A.md']?.markdown, '# A');
  });
}
