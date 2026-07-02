import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simsync_mobile/storage/github/github_api_client.dart';
import 'package:simsync_mobile/storage/github/github_note_storage.dart';

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
          // GitHub serves UTF-8; tree paths may contain non-Latin1 chars
          // (e.g. `N주차` review folders). Without this the mock's default
          // Latin1 body encoding throws on those paths.
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }

      // Contents endpoint (blob fetch).
      if (request.method == 'GET' &&
          path.startsWith('/repos/$owner/$repo/contents/')) {
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
        'listAllNotes excludes review files in non-day folders and never fetches them',
        () async {
      final pathToSha = {
        'notes/2026-06/01/Note A.md': 'sha-a',
        // Reviews live in non-day folders — must be ignored by the note list.
        'notes/2026-06/1주차/weekly-review.md': 'sha-w',
        'notes/2026-06/monthly-review.md': 'sha-m',
      };
      final pathToMd = {
        'notes/2026-06/01/Note A.md': md('a', 'Note A', DateTime(2026, 6, 1)),
        'notes/2026-06/1주차/weekly-review.md': '# Weekly Review\n\n- did things',
        'notes/2026-06/monthly-review.md': '# Monthly Review',
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
      expect(notes.length, 1);
      expect(notes.first.id, 'a');

      // Review files are filtered by path → never even fetched as blobs.
      final contentGets = mock.requests
          .where((r) => r.method == 'GET')
          .map((r) => Uri.decodeFull(r.url.path))
          .where((p) => p.contains('/contents/'))
          .toList();
      expect(contentGets.any((p) => p.contains('weekly-review')), isFalse);
      expect(contentGets.any((p) => p.contains('monthly-review')), isFalse);
    });

    test('listDates skips non-numeric folders such as review directories',
        () async {
      final pathToSha = {
        'notes/2026-06/01/Note A.md': 'sha-a',
        'notes/2026-06/15/Note B.md': 'sha-b',
        'notes/2026-06/1주차/weekly-review.md': 'sha-w',
        'notes/2026-06/monthly-review.md': 'sha-m',
      };
      final pathToMd = {
        'notes/2026-06/01/Note A.md': md('a', 'Note A', DateTime(2026, 6, 1)),
        'notes/2026-06/15/Note B.md': md('b', 'Note B', DateTime(2026, 6, 15)),
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

      final dates = await storage.listDates('2026-06');
      expect(dates, [DateTime(2026, 6, 1), DateTime(2026, 6, 15)]);
    });
  });
}
