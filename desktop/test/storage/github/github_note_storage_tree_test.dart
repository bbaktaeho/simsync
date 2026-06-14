import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simsync/storage/github/github_api_client.dart';
import 'package:simsync/storage/github/github_note_storage.dart';

void main() {
  const owner = 'testuser';
  const repo = 'testrepo';
  const token = 'test-token';
  const branch = 'main';

  String githubBase64(String content) => base64.encode(utf8.encode(content));

  String md(String id, String title, DateTime date) => '''---
id: "$id"
title: "$title"
note_date: ${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}
is_default: false
tags: []
created_at: 2026-05-02T09:00:00+0000
updated_at: 2026-05-02T10:00:00+0000
---
content of $title''';

  /// Reusable mock that serves:
  ///   - GET /repos/{o}/{r}/branches/{b} → tree sha
  ///   - GET /repos/{o}/{r}/git/trees/{tree_sha}?recursive=1 → tree entries
  ///   - GET /repos/{o}/{r}/contents/{path} → blob content
  /// Tracks all requests so tests can assert call counts and shapes.
  ({MockClient client, List<http.BaseRequest> requests}) makeTreeMock({
    required Map<String, String> notePathToSha,
    required Map<String, String> notePathToMarkdown,
    String treeSha = 'tree-sha-1',
    bool truncated = false,
  }) {
    final requests = <http.BaseRequest>[];
    final mock = MockClient((request) async {
      requests.add(request);
      final path = Uri.decodeFull(request.url.path);

      // Branch endpoint.
      if (request.method == 'GET' &&
          path == '/repos/$owner/$repo/branches/$branch') {
        return http.Response(
          jsonEncode({
            'name': branch,
            'commit': {
              'sha': 'commit-sha-1',
              'commit': {
                'tree': {'sha': treeSha},
              },
            },
          }),
          200,
        );
      }

      // Tree endpoint.
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
                      'size': 123,
                    })
                .toList(),
            'truncated': truncated,
          }),
          200,
        );
      }

      // Contents endpoint (blob fetch).
      if (request.method == 'GET' && path.startsWith('/repos/$owner/$repo/contents/')) {
        final filePath =
            path.substring('/repos/$owner/$repo/contents/'.length);
        final markdown = notePathToMarkdown[filePath];
        final sha = notePathToSha[filePath];
        if (markdown != null && sha != null) {
          return http.Response(
            jsonEncode({
              'name': filePath.split('/').last,
              'path': filePath,
              'sha': sha,
              'content': githubBase64(markdown),
              'type': 'file',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      }

      return http.Response('Not Found', 404);
    });
    return (client: mock, requests: requests);
  }

  group('GitHubNoteStorage tree-based listing', () {
    test(
        'listAllNotes uses tree (1 branch + 1 tree) instead of per-directory listing',
        () async {
      final pathToSha = {
        'notes/2026-05/02/Note A.md': 'sha-a',
        'notes/2026-05/03/Note B.md': 'sha-b',
        'notes/2026-04/15/Note C.md': 'sha-c',
      };
      final pathToMd = {
        'notes/2026-05/02/Note A.md': md('a', 'Note A', DateTime(2026, 5, 2)),
        'notes/2026-05/03/Note B.md': md('b', 'Note B', DateTime(2026, 5, 3)),
        'notes/2026-04/15/Note C.md': md('c', 'Note C', DateTime(2026, 4, 15)),
      };
      final mock = makeTreeMock(
        notePathToSha: pathToSha,
        notePathToMarkdown: pathToMd,
      );

      final apiClient = GitHubApiClient(
        token: token,
        owner: owner,
        repo: repo,
        httpClient: mock.client,
      );
      final storage = GitHubNoteStorage(apiClient, branch: branch);

      final notes = await storage.listAllNotes();
      expect(notes.length, 3);
      expect(notes.map((n) => n.id).toSet(), {'a', 'b', 'c'});

      // Exactly one branch fetch, one tree fetch, three blob fetches.
      // No `listDirectory(notes)` or per-day listing GETs.
      final getPaths = mock.requests
          .where((r) => r.method == 'GET')
          .map((r) => Uri.decodeFull(r.url.path))
          .toList();

      expect(
        getPaths.where((p) => p == '/repos/$owner/$repo/branches/$branch').length,
        1,
        reason: 'One branch info fetch',
      );
      expect(
        getPaths
            .where((p) => p.startsWith('/repos/$owner/$repo/git/trees/'))
            .length,
        1,
        reason: 'One recursive tree fetch',
      );
      // Three content fetches (one per .md file)
      expect(
        getPaths
            .where((p) =>
                p.startsWith('/repos/$owner/$repo/contents/notes/') &&
                p.endsWith('.md'))
            .length,
        3,
      );
      // No directory listing GETs.
      expect(
        getPaths.any((p) =>
            p == '/repos/$owner/$repo/contents/notes' ||
            RegExp('/repos/$owner/$repo/contents/notes/[0-9]{4}-[0-9]{2}\$')
                .hasMatch(p)),
        isFalse,
        reason: 'No legacy month/day directory listing should occur',
      );
    });

    test('second listAllNotes call reuses tree cache and skips network',
        () async {
      final pathToSha = {
        'notes/2026-05/02/A.md': 'sha-a',
      };
      final pathToMd = {
        'notes/2026-05/02/A.md': md('a', 'A', DateTime(2026, 5, 2)),
      };
      final mock = makeTreeMock(
        notePathToSha: pathToSha,
        notePathToMarkdown: pathToMd,
      );

      final apiClient = GitHubApiClient(
        token: token,
        owner: owner,
        repo: repo,
        httpClient: mock.client,
      );
      final storage = GitHubNoteStorage(apiClient, branch: branch);

      await storage.listAllNotes();
      final firstCount = mock.requests.length;
      await storage.listAllNotes();

      // Second call: cached tree + cached blob (sha unchanged), so no new GETs.
      expect(mock.requests.length, firstCount);
    });

    test('invalidateTreeCache forces re-fetch on next listing', () async {
      final pathToSha = {
        'notes/2026-05/02/A.md': 'sha-a',
      };
      final pathToMd = {
        'notes/2026-05/02/A.md': md('a', 'A', DateTime(2026, 5, 2)),
      };
      final mock = makeTreeMock(
        notePathToSha: pathToSha,
        notePathToMarkdown: pathToMd,
      );

      final apiClient = GitHubApiClient(
        token: token,
        owner: owner,
        repo: repo,
        httpClient: mock.client,
      );
      final storage = GitHubNoteStorage(apiClient, branch: branch);

      await storage.listAllNotes();
      final firstCount = mock.requests.length;

      storage.invalidateTreeCache();
      await storage.listAllNotes();

      // After invalidate: branch + tree fetched again (2 GETs). Blob is reused
      // because its SHA in the new tree response is unchanged.
      expect(mock.requests.length, firstCount + 2);
    });

    test('truncated tree response falls back to legacy directory listing',
        () async {
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
                  'tree': {'sha': 'tree-sha-1'},
                },
              },
            }),
            200,
          );
        }

        // Tree returns truncated.
        if (request.method == 'GET' &&
            path == '/repos/$owner/$repo/git/trees/tree-sha-1') {
          return http.Response(
            jsonEncode({
              'sha': 'tree-sha-1',
              'tree': const [],
              'truncated': true,
            }),
            200,
          );
        }

        // Legacy listing fallback: notes/ → empty (sufficient to verify the
        // legacy code path is taken without hand-rolling a full listing).
        if (request.method == 'GET' &&
            path == '/repos/$owner/$repo/contents/notes') {
          return http.Response(jsonEncode([]), 200);
        }

        return http.Response('Not Found', 404);
      });

      final apiClient = GitHubApiClient(
        token: token,
        owner: owner,
        repo: repo,
        httpClient: mock,
      );
      final storage = GitHubNoteStorage(apiClient, branch: branch);

      final notes = await storage.listAllNotes();
      expect(notes, isEmpty);

      final getPaths = requests
          .where((r) => r.method == 'GET')
          .map((r) => Uri.decodeFull(r.url.path))
          .toList();
      // Tree was attempted, then legacy `notes/` listing kicked in.
      expect(
        getPaths.contains('/repos/$owner/$repo/git/trees/tree-sha-1'),
        isTrue,
      );
      expect(
        getPaths.contains('/repos/$owner/$repo/contents/notes'),
        isTrue,
      );
    });

    test('tree endpoint failure falls back to legacy directory listing',
        () async {
      final requests = <http.BaseRequest>[];
      final mock = MockClient((request) async {
        requests.add(request);
        final path = Uri.decodeFull(request.url.path);

        if (request.method == 'GET' &&
            path == '/repos/$owner/$repo/branches/$branch') {
          return http.Response('Server error', 500);
        }

        if (request.method == 'GET' &&
            path == '/repos/$owner/$repo/contents/notes') {
          return http.Response(jsonEncode([]), 200);
        }

        return http.Response('Not Found', 404);
      });

      final apiClient = GitHubApiClient(
        token: token,
        owner: owner,
        repo: repo,
        httpClient: mock,
      );
      final storage = GitHubNoteStorage(apiClient, branch: branch);

      final notes = await storage.listAllNotes();
      expect(notes, isEmpty);

      final getPaths = requests
          .where((r) => r.method == 'GET')
          .map((r) => Uri.decodeFull(r.url.path))
          .toList();
      expect(getPaths, contains('/repos/$owner/$repo/contents/notes'));
    });

    test('listNotes for a date scopes content fetches to that day only',
        () async {
      final pathToSha = {
        'notes/2026-05/02/A.md': 'sha-a',
        'notes/2026-05/03/B.md': 'sha-b',
        'notes/2026-05/04/C.md': 'sha-c',
      };
      final pathToMd = {
        for (final entry in pathToSha.entries)
          entry.key: md(
            entry.value,
            entry.key.split('/').last.replaceAll('.md', ''),
            DateTime(
              2026,
              5,
              int.parse(entry.key.split('/')[2]),
            ),
          ),
      };
      final mock = makeTreeMock(
        notePathToSha: pathToSha,
        notePathToMarkdown: pathToMd,
      );

      final apiClient = GitHubApiClient(
        token: token,
        owner: owner,
        repo: repo,
        httpClient: mock.client,
      );
      final storage = GitHubNoteStorage(apiClient, branch: branch);

      final notes = await storage.listNotes(DateTime(2026, 5, 3));
      expect(notes.length, 1);
      expect(notes.first.title, 'B');

      final blobGets = mock.requests
          .where((r) =>
              r.method == 'GET' &&
              Uri.decodeFull(r.url.path).contains('/contents/notes/2026-05/'))
          .map((r) => Uri.decodeFull(r.url.path))
          .toList();
      // Only the B.md blob should be fetched, not A.md or C.md.
      expect(blobGets.length, 1);
      expect(blobGets.first, endsWith('B.md'));
    });

    test('listDates extracts day directories from tree without API calls',
        () async {
      final pathToSha = {
        'notes/2026-05/02/A.md': 'sha-a',
        'notes/2026-05/15/B.md': 'sha-b',
        'notes/2026-05/22/C.md': 'sha-c',
        'notes/2026-04/10/D.md': 'sha-d',
      };
      final mock = makeTreeMock(
        notePathToSha: pathToSha,
        notePathToMarkdown: const {},
      );

      final apiClient = GitHubApiClient(
        token: token,
        owner: owner,
        repo: repo,
        httpClient: mock.client,
      );
      final storage = GitHubNoteStorage(apiClient, branch: branch);

      final dates = await storage.listDates('2026-05');
      expect(dates.length, 3);
      expect(dates[0], DateTime(2026, 5, 2));
      expect(dates[1], DateTime(2026, 5, 15));
      expect(dates[2], DateTime(2026, 5, 22));

      // Only branch + tree should have been hit; no directory listing GETs.
      final getPaths = mock.requests
          .where((r) => r.method == 'GET')
          .map((r) => Uri.decodeFull(r.url.path))
          .toList();
      expect(
        getPaths
            .where((p) => p.startsWith('/repos/$owner/$repo/contents/'))
            .length,
        0,
      );
    });
  });
}
