import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simsync/storage/github/github_api_client.dart';
import 'package:simsync/storage/github/github_note_cache.dart';
import 'package:simsync/storage/github/github_note_storage.dart';

void main() {
  const owner = 'testuser';
  const repo = 'testrepo';
  const token = 'test-token';
  const branch = 'main';

  String githubBase64(String content) => base64.encode(utf8.encode(content));

  String md(String id, String title, DateTime date, {String body = ''}) => '''---
id: "$id"
title: "$title"
note_date: ${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}
is_default: false
tags: []
created_at: 2026-05-02T09:00:00+0000
updated_at: 2026-05-02T10:00:00+0000
---
$body''';

  /// Tracking mock: serves branches/trees/contents for any path → sha map.
  ({MockClient client, List<http.BaseRequest> requests}) makeMock({
    required Map<String, String> notePathToSha,
    required Map<String, String> notePathToMarkdown,
    String treeSha = 'tree-sha-1',
  }) {
    final requests = <http.BaseRequest>[];
    final mock = MockClient((request) async {
      requests.add(request);
      final path = Uri.decodeFull(request.url.path);
      if (request.method == 'GET' &&
          path == '/repos/$owner/$repo/branches/$branch') {
        return http.Response(
          jsonEncode({
            'commit': {
              'commit': {
                'tree': {'sha': treeSha},
              },
            },
          }),
          200,
        );
      }
      if (request.method == 'GET' &&
          path == '/repos/$owner/$repo/git/trees/$treeSha') {
        return http.Response(
          jsonEncode({
            'sha': treeSha,
            'tree': notePathToSha.entries
                .map((e) => {
                      'path': e.key,
                      'sha': e.value,
                      'type': 'blob',
                      'size': 100,
                    })
                .toList(),
            'truncated': false,
          }),
          200,
        );
      }
      if (request.method == 'GET' &&
          path.startsWith('/repos/$owner/$repo/contents/')) {
        final filePath =
            path.substring('/repos/$owner/$repo/contents/'.length);
        final sha = notePathToSha[filePath];
        final mdContent = notePathToMarkdown[filePath];
        if (sha != null && mdContent != null) {
          return http.Response(
            jsonEncode({
              'name': filePath.split('/').last,
              'path': filePath,
              'sha': sha,
              'content': githubBase64(mdContent),
              'type': 'file',
            }),
            200,
          );
        }
      }
      return http.Response('Not Found', 404);
    });
    return (client: mock, requests: requests);
  }

  late Directory tempDir;
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('simsync_cache_test_');
  });
  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('GitHubNoteStorage persistent cache', () {
    test(
        'second instance loads cache from disk and serves listAllNotes with zero API calls',
        () async {
      final pathToSha = {
        'notes/2026-05/02/A.md': 'sha-a',
        'notes/2026-05/03/B.md': 'sha-b',
      };
      final pathToMd = {
        'notes/2026-05/02/A.md': md('a', 'A', DateTime(2026, 5, 2)),
        'notes/2026-05/03/B.md': md('b', 'B', DateTime(2026, 5, 3)),
      };
      final cachePath = '${tempDir.path}/cache.json';

      // First instance: warm the cache by calling listAllNotes.
      {
        final mock = makeMock(
          notePathToSha: pathToSha,
          notePathToMarkdown: pathToMd,
        );
        final apiClient = GitHubApiClient(
          token: token,
          owner: owner,
          repo: repo,
          httpClient: mock.client,
        );
        final cache = GitHubNoteCache(path: cachePath);
        final storage = GitHubNoteStorage(
          apiClient,
          branch: branch,
          cache: cache,
        );
        await storage.loadCache(); // empty cache
        final notes = await storage.listAllNotes();
        expect(notes.length, 2);
        await storage.flushCache();
      }

      // Cache file must exist on disk now.
      expect(File(cachePath).existsSync(), isTrue);

      // Second instance with a mock that REJECTS every request: cache must
      // serve listAllNotes without any network round-trip.
      final blockingRequests = <http.BaseRequest>[];
      final blocking = MockClient((request) async {
        blockingRequests.add(request);
        return http.Response('Should not be called', 500);
      });
      final apiClient2 = GitHubApiClient(
        token: token,
        owner: owner,
        repo: repo,
        httpClient: blocking,
      );
      final cache2 = GitHubNoteCache(path: cachePath);
      final storage2 = GitHubNoteStorage(
        apiClient2,
        branch: branch,
        cache: cache2,
      );
      await storage2.loadCache();

      final cachedNotes = await storage2.listAllNotes();

      expect(blockingRequests, isEmpty,
          reason: 'Cache hit must not hit GitHub at all on cold start.');
      expect(cachedNotes.map((n) => n.id).toSet(), {'a', 'b'});
    });

    test(
        'after invalidateTreeCache, only files with changed SHA are re-fetched',
        () async {
      final pathToSha = {
        'notes/2026-05/02/A.md': 'sha-a-v1',
        'notes/2026-05/03/B.md': 'sha-b-v1',
      };
      final pathToMd = {
        'notes/2026-05/02/A.md': md('a', 'A', DateTime(2026, 5, 2), body: 'v1'),
        'notes/2026-05/03/B.md': md('b', 'B', DateTime(2026, 5, 3), body: 'v1'),
      };
      final cachePath = '${tempDir.path}/cache.json';

      // Warm the cache.
      {
        final mock = makeMock(
          notePathToSha: pathToSha,
          notePathToMarkdown: pathToMd,
        );
        final apiClient = GitHubApiClient(
          token: token,
          owner: owner,
          repo: repo,
          httpClient: mock.client,
        );
        final cache = GitHubNoteCache(path: cachePath);
        final storage = GitHubNoteStorage(
          apiClient,
          branch: branch,
          cache: cache,
        );
        await storage.loadCache();
        await storage.listAllNotes();
        await storage.flushCache();
      }

      // Second instance: A unchanged, B got a new SHA on the remote side.
      final newPathToSha = {
        'notes/2026-05/02/A.md': 'sha-a-v1', // unchanged
        'notes/2026-05/03/B.md': 'sha-b-v2', // changed
      };
      final newPathToMd = {
        'notes/2026-05/02/A.md': md('a', 'A', DateTime(2026, 5, 2), body: 'v1'),
        'notes/2026-05/03/B.md': md('b', 'B', DateTime(2026, 5, 3), body: 'v2'),
      };
      final mock2 = makeMock(
        notePathToSha: newPathToSha,
        notePathToMarkdown: newPathToMd,
        treeSha: 'tree-sha-2',
      );
      final apiClient2 = GitHubApiClient(
        token: token,
        owner: owner,
        repo: repo,
        httpClient: mock2.client,
      );
      final cache2 = GitHubNoteCache(path: cachePath);
      final storage2 = GitHubNoteStorage(
        apiClient2,
        branch: branch,
        cache: cache2,
      );
      await storage2.loadCache();
      // Simulate sync engine detecting a new commit.
      storage2.invalidateTreeCache();

      final notes = await storage2.listAllNotes();
      expect(notes.length, 2);
      expect(notes.firstWhere((n) => n.id == 'b').content, 'v2');

      // Exactly: 1 branch + 1 tree + 1 contents (B only).
      final blobGets = mock2.requests
          .where((r) =>
              r.method == 'GET' &&
              Uri.decodeFull(r.url.path).startsWith(
                '/repos/$owner/$repo/contents/notes/',
              ))
          .toList();
      expect(blobGets.length, 1,
          reason: 'A still cached, only B re-fetched.');
      expect(
        Uri.decodeFull(blobGets.first.url.path),
        endsWith('B.md'),
      );
    });

    test('lastCommitSha persists across instances', () async {
      final cachePath = '${tempDir.path}/cache.json';
      final cache = GitHubNoteCache(path: cachePath);
      final apiClient = GitHubApiClient(
        token: token,
        owner: owner,
        repo: repo,
        httpClient: MockClient((_) async => http.Response('NA', 404)),
      );
      final storage = GitHubNoteStorage(
        apiClient,
        branch: branch,
        cache: cache,
      );
      await storage.loadCache();
      storage.setLastCommitSha('commit-abc');
      await storage.flushCache();

      // New instance: lastCommitSha reloaded from disk.
      final cache2 = GitHubNoteCache(path: cachePath);
      final storage2 = GitHubNoteStorage(
        apiClient,
        branch: branch,
        cache: cache2,
      );
      await storage2.loadCache();
      expect(storage2.lastCommitSha, 'commit-abc');
    });

    test('cache: null preserves legacy in-memory behavior', () async {
      // Regression check: storage built without a cache must work exactly like
      // before this PR — listAllNotes hits GitHub and returns notes.
      final pathToSha = {
        'notes/2026-05/02/A.md': 'sha-a',
      };
      final pathToMd = {
        'notes/2026-05/02/A.md': md('a', 'A', DateTime(2026, 5, 2)),
      };
      final mock = makeMock(
        notePathToSha: pathToSha,
        notePathToMarkdown: pathToMd,
      );
      final apiClient = GitHubApiClient(
        token: token,
        owner: owner,
        repo: repo,
        httpClient: mock.client,
      );
      final storage =
          GitHubNoteStorage(apiClient, branch: branch); // no cache
      await storage.loadCache(); // no-op when cache is null
      final notes = await storage.listAllNotes();
      expect(notes.single.id, 'a');
      expect(storage.lastCommitSha, isNull);
    });
  });
}
