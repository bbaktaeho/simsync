import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simsync/storage/github/github_api_client.dart';

void main() {
  const token = 'test-token';
  const owner = 'test-owner';
  const repo = 'test-repo';

  GitHubApiClient createClient(MockClient mockClient) {
    return GitHubApiClient(
      token: token,
      owner: owner,
      repo: repo,
      httpClient: mockClient,
    );
  }

  group('getFile', () {
    test('returns file with decoded content and sends auth header', () async {
      final content = base64.encode(utf8.encode('Hello, World!'));

      final mock = MockClient((request) async {
        // Verify auth header
        expect(request.headers['Authorization'], 'Bearer $token');
        expect(request.headers['Accept'], 'application/vnd.github.v3+json');
        expect(request.headers['X-GitHub-Api-Version'], '2022-11-28');
        expect(
          request.url.toString(),
          'https://api.github.com/repos/$owner/$repo/contents/notes/test.md',
        );

        return http.Response(
          jsonEncode({
            'name': 'test.md',
            'path': 'notes/test.md',
            'sha': 'abc123',
            'content': content,
            'type': 'file',
          }),
          200,
        );
      });

      final client = createClient(mock);
      final file = await client.getFile('notes/test.md');

      expect(file.name, 'test.md');
      expect(file.path, 'notes/test.md');
      expect(file.sha, 'abc123');
      expect(file.decodedContent, 'Hello, World!');
      expect(file.type, 'file');
    });

    test('throws GitHubNotFoundException on 404', () async {
      final mock = MockClient((_) async => http.Response('Not Found', 404));
      final client = createClient(mock);

      expect(
        () => client.getFile('missing.md'),
        throwsA(isA<GitHubNotFoundException>()),
      );
    });
  });

  group('listDirectory', () {
    test('returns file list', () async {
      final mock = MockClient((_) async {
        return http.Response(
          jsonEncode([
            {
              'name': 'a.md',
              'path': 'notes/a.md',
              'sha': 'sha-a',
              'type': 'file',
            },
            {
              'name': 'b.md',
              'path': 'notes/b.md',
              'sha': 'sha-b',
              'type': 'file',
            },
          ]),
          200,
        );
      });

      final client = createClient(mock);
      final files = await client.listDirectory('notes');

      expect(files, hasLength(2));
      expect(files[0].name, 'a.md');
      expect(files[1].name, 'b.md');
    });

    test('returns empty list on 404', () async {
      final mock = MockClient((_) async => http.Response('Not Found', 404));
      final client = createClient(mock);

      final files = await client.listDirectory('nonexistent');
      expect(files, isEmpty);
    });
  });

  group('putFile', () {
    test('creates file and returns sha (no sha in body for create)', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'PUT');

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.containsKey('sha'), isFalse);
        expect(body['message'], 'create file');
        expect(body.containsKey('content'), isTrue);

        return http.Response(
          jsonEncode({
            'content': {
              'name': 'new.md',
              'path': 'notes/new.md',
              'sha': 'new-sha-123',
              'type': 'file',
            },
          }),
          201,
        );
      });

      final client = createClient(mock);
      final sha = await client.putFile(
        path: 'notes/new.md',
        content: 'New content',
        message: 'create file',
      );

      expect(sha, 'new-sha-123');
    });

    test('throws GitHubConflictException on 409', () async {
      final mock = MockClient((_) async => http.Response('Conflict', 409));
      final client = createClient(mock);

      expect(
        () => client.putFile(
          path: 'notes/test.md',
          content: 'content',
          message: 'update',
          sha: 'old-sha',
        ),
        throwsA(isA<GitHubConflictException>()),
      );
    });
  });

  group('deleteFile', () {
    test('sends DELETE with sha in body', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(
          request.url.toString(),
          'https://api.github.com/repos/$owner/$repo/contents/notes/old.md',
        );

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['sha'], 'delete-sha');
        expect(body['message'], 'delete file');

        return http.Response('', 200);
      });

      final client = createClient(mock);
      await client.deleteFile(
        path: 'notes/old.md',
        sha: 'delete-sha',
        message: 'delete file',
      );
    });
  });
}
