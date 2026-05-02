import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/storage/github/github_api_client.dart';
import 'package:simsync/storage/github/github_note_storage.dart';

void main() {
  const owner = 'testuser';
  const repo = 'testrepo';
  const token = 'test-token';

  Note createTestNote({
    String id = 'note-123',
    String title = 'My Note',
    String content = 'Hello world',
  }) {
    return Note(
      id: id,
      noteDate: DateTime(2026, 3, 10),
      title: title,
      content: content,
      isDefault: false,
      tags: ['tag1', 'tag2'],
      createdAt: DateTime.utc(2026, 3, 10, 9, 0, 0),
      updatedAt: DateTime.utc(2026, 3, 10, 10, 0, 0),
    );
  }

  /// Encodes content as base64 the same way GitHub returns it.
  String githubBase64(String content) => base64.encode(utf8.encode(content));

  group('GitHubNoteStorage', () {
    test('saveNote creates file via API with correct path', () async {
      final requests = <http.BaseRequest>[];

      final mockClient = MockClient((request) async {
        requests.add(request);

        if (request.method == 'PUT') {
          // Verify the path contains YYYY-MM/DD pattern.
          final decodedPath = Uri.decodeFull(request.url.path);
          expect(decodedPath, contains('2026-03'));
          expect(decodedPath, contains('10'));
          expect(decodedPath, contains('My Note.md'));

          return http.Response(
            jsonEncode({
              'content': {
                'sha': 'new-sha-abc',
                'name': 'My Note.md',
                'path': 'notes/2026-03/10/My Note.md',
              }
            }),
            201,
          );
        }

        return http.Response('Not Found', 404);
      });

      final apiClient = GitHubApiClient(
        token: token,
        owner: owner,
        repo: repo,
        httpClient: mockClient,
      );

      final storage = GitHubNoteStorage(apiClient);
      final note = createTestNote();

      await storage.saveNote(note);

      // Should have made exactly one PUT request.
      expect(requests.length, 1);
      expect(requests.first.method, 'PUT');

      // Verify path structure: notes/2026-03/10/My Note.md
      final uri = requests.first.url;
      expect(Uri.decodeFull(uri.path),
          '/repos/$owner/$repo/contents/notes/2026-03/10/My Note.md');

      // Verify body contains base64-encoded markdown with frontmatter.
      final body =
          jsonDecode((requests.first as http.Request).body) as Map<String, dynamic>;
      final decoded = utf8.decode(base64.decode(body['content'] as String));
      expect(decoded, contains('---'));
      expect(decoded, contains('id: "note-123"'));
      expect(decoded, contains('Hello world'));
    });

    test('saveNote handles 409 conflict with Last-Write-Wins', () async {
      int putCount = 0;

      final mockClient = MockClient((request) async {
        final path = request.url.path;

        if (request.method == 'PUT') {
          putCount++;
          if (putCount == 1) {
            // First PUT: 409 Conflict.
            return http.Response('Conflict', 409);
          }
          // Second PUT: success with latest SHA.
          return http.Response(
            jsonEncode({
              'content': {
                'sha': 'final-sha',
                'name': 'My Note.md',
                'path': 'notes/2026-03/10/My Note.md',
              }
            }),
            201,
          );
        }

        if (request.method == 'GET' &&
            Uri.decodeFull(path).contains('notes/2026-03/10/My Note.md')) {
          // GET to fetch latest SHA after conflict.
          return http.Response(
            jsonEncode({
              'name': 'My Note.md',
              'path': 'notes/2026-03/10/My Note.md',
              'sha': 'latest-sha-from-server',
              'content': githubBase64('---\nid: "note-123"\n---\nold content'),
              'type': 'file',
            }),
            200,
          );
        }

        return http.Response('Not Found', 404);
      });

      final apiClient = GitHubApiClient(
        token: token,
        owner: owner,
        repo: repo,
        httpClient: mockClient,
      );

      final storage = GitHubNoteStorage(apiClient);
      final note = createTestNote();

      await storage.saveNote(note);

      // Should have made 2 PUTs (first failed with 409, second succeeded)
      // and 1 GET (to fetch latest SHA).
      expect(putCount, 2);
    });

    test('listDates returns dates from directory listing', () async {
      final mockClient = MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path.contains('notes/2026-03') &&
            !request.url.path.contains('/0')) {
          return http.Response(
            jsonEncode([
              {
                'name': '05',
                'path': 'notes/2026-03/05',
                'sha': 'dir-sha-1',
                'type': 'dir',
              },
              {
                'name': '10',
                'path': 'notes/2026-03/10',
                'sha': 'dir-sha-2',
                'type': 'dir',
              },
              {
                'name': '22',
                'path': 'notes/2026-03/22',
                'sha': 'dir-sha-3',
                'type': 'dir',
              },
            ]),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = GitHubApiClient(
        token: token,
        owner: owner,
        repo: repo,
        httpClient: mockClient,
      );

      final storage = GitHubNoteStorage(apiClient);
      final dates = await storage.listDates('2026-03');

      expect(dates.length, 3);
      expect(dates[0], DateTime(2026, 3, 5));
      expect(dates[1], DateTime(2026, 3, 10));
      expect(dates[2], DateTime(2026, 3, 22));
    });

    test('listNotes returns parsed notes and caches SHAs', () async {
      final noteMarkdown = '''---
id: "note-abc"
title: "Test Note"
note_date: 2026-03-10
is_default: false
tags: ["work"]
created_at: 2026-03-10T09:00:00+0000
updated_at: 2026-03-10T10:00:00+0000
---
Some content here''';

      final mockClient = MockClient((request) async {
        final path = request.url.path;

        // Directory listing.
        if (request.method == 'GET' &&
            path.endsWith('notes/2026-03/10')) {
          return http.Response(
            jsonEncode([
              {
                'name': 'Test Note.md',
                'path': 'notes/2026-03/10/Test Note.md',
                'sha': 'list-sha',
                'type': 'file',
              },
            ]),
            200,
          );
        }

        // File content.
        if (request.method == 'GET' &&
            Uri.decodeFull(path).contains('Test Note.md')) {
          return http.Response(
            jsonEncode({
              'name': 'Test Note.md',
              'path': 'notes/2026-03/10/Test Note.md',
              'sha': 'file-sha-xyz',
              'content': githubBase64(noteMarkdown),
              'type': 'file',
            }),
            200,
          );
        }

        return http.Response('Not Found', 404);
      });

      final apiClient = GitHubApiClient(
        token: token,
        owner: owner,
        repo: repo,
        httpClient: mockClient,
      );

      final storage = GitHubNoteStorage(apiClient);
      final notes = await storage.listNotes(DateTime(2026, 3, 10));

      expect(notes.length, 1);
      expect(notes.first.id, 'note-abc');
      expect(notes.first.title, 'Test Note');
      expect(notes.first.content, 'Some content here');
      expect(notes.first.tags, ['work']);
    });

    test('getNote finds note by id in day directory', () async {
      final noteMarkdown = '''---
id: "target-id"
title: "Target"
note_date: 2026-03-10
is_default: false
tags: []
created_at: 2026-03-10T09:00:00+0000
updated_at: 2026-03-10T10:00:00+0000
---
Found it''';

      final mockClient = MockClient((request) async {
        final path = request.url.path;

        if (request.method == 'GET' &&
            path.endsWith('notes/2026-03/10')) {
          return http.Response(
            jsonEncode([
              {
                'name': 'Other.md',
                'path': 'notes/2026-03/10/Other.md',
                'sha': 'sha-other',
                'type': 'file',
              },
              {
                'name': 'Target.md',
                'path': 'notes/2026-03/10/Target.md',
                'sha': 'sha-target',
                'type': 'file',
              },
            ]),
            200,
          );
        }

        if (request.method == 'GET' && path.contains('Other.md')) {
          return http.Response(
            jsonEncode({
              'name': 'Other.md',
              'path': 'notes/2026-03/10/Other.md',
              'sha': 'sha-other',
              'content': githubBase64(
                  '---\nid: "other-id"\ntitle: "Other"\nnote_date: 2026-03-10\nis_default: false\ntags: []\ncreated_at: 2026-03-10T09:00:00+0000\nupdated_at: 2026-03-10T10:00:00+0000\n---\nNot this one'),
              'type': 'file',
            }),
            200,
          );
        }

        if (request.method == 'GET' && path.contains('Target.md')) {
          return http.Response(
            jsonEncode({
              'name': 'Target.md',
              'path': 'notes/2026-03/10/Target.md',
              'sha': 'sha-target',
              'content': githubBase64(noteMarkdown),
              'type': 'file',
            }),
            200,
          );
        }

        return http.Response('Not Found', 404);
      });

      final apiClient = GitHubApiClient(
        token: token,
        owner: owner,
        repo: repo,
        httpClient: mockClient,
      );

      final storage = GitHubNoteStorage(apiClient);
      final note = await storage.getNote('target-id', DateTime(2026, 3, 10));

      expect(note, isNotNull);
      expect(note!.id, 'target-id');
      expect(note.content, 'Found it');
    });

    test('serializeNote and parseNote round-trip correctly', () {
      final note = createTestNote();
      final markdown = GitHubNoteStorage.serializeNote(note);
      final parsed = GitHubNoteStorage.parseNote(markdown);

      expect(parsed, isNotNull);
      expect(parsed!.id, note.id);
      expect(parsed.title, note.title);
      expect(parsed.content, note.content);
      expect(parsed.isDefault, note.isDefault);
      expect(parsed.tags, note.tags);
      expect(parsed.noteDate, note.noteDate);
    });

    test('listNotes uses cache when SHA unchanged', () async {
      int getFileCallCount = 0;

      final noteMarkdown = '''---
id: "cached-note"
title: "Cached"
note_date: 2026-03-10
is_default: false
tags: []
created_at: 2026-03-10T09:00:00+0000
updated_at: 2026-03-10T10:00:00+0000
---
Cached content''';

      final mockClient = MockClient((request) async {
        final path = request.url.path;

        // Directory listing — always returns the same SHA.
        if (request.method == 'GET' && path.endsWith('notes/2026-03/10')) {
          return http.Response(
            jsonEncode([
              {
                'name': 'Cached.md',
                'path': 'notes/2026-03/10/Cached.md',
                'sha': 'stable-sha',
                'type': 'file',
              },
            ]),
            200,
          );
        }

        // Individual file fetch.
        if (request.method == 'GET' &&
            Uri.decodeFull(path).contains('Cached.md')) {
          getFileCallCount++;
          return http.Response(
            jsonEncode({
              'name': 'Cached.md',
              'path': 'notes/2026-03/10/Cached.md',
              'sha': 'stable-sha',
              'content': githubBase64(noteMarkdown),
              'type': 'file',
            }),
            200,
          );
        }

        return http.Response('Not Found', 404);
      });

      final apiClient = GitHubApiClient(
        token: token,
        owner: owner,
        repo: repo,
        httpClient: mockClient,
      );

      final storage = GitHubNoteStorage(apiClient);

      // First call: should fetch the file.
      final notes1 = await storage.listNotes(DateTime(2026, 3, 10));
      expect(notes1.length, 1);
      expect(getFileCallCount, 1);

      // Second call: same SHA, should use cache — no additional getFile call.
      final notes2 = await storage.listNotes(DateTime(2026, 3, 10));
      expect(notes2.length, 1);
      expect(notes2.first.id, 'cached-note');
      expect(getFileCallCount, 1); // Still 1 — no new getFile call.
    });

    test('getNote uses _idToPath index after listNotes', () async {
      int listDirCallCount = 0;

      final noteMarkdown = '''---
id: "indexed-note"
title: "Indexed"
note_date: 2026-03-10
is_default: false
tags: []
created_at: 2026-03-10T09:00:00+0000
updated_at: 2026-03-10T10:00:00+0000
---
Indexed content''';

      final mockClient = MockClient((request) async {
        final path = request.url.path;

        if (request.method == 'GET' && path.endsWith('notes/2026-03/10')) {
          listDirCallCount++;
          return http.Response(
            jsonEncode([
              {
                'name': 'Indexed.md',
                'path': 'notes/2026-03/10/Indexed.md',
                'sha': 'idx-sha',
                'type': 'file',
              },
            ]),
            200,
          );
        }

        if (request.method == 'GET' &&
            Uri.decodeFull(path).contains('Indexed.md')) {
          return http.Response(
            jsonEncode({
              'name': 'Indexed.md',
              'path': 'notes/2026-03/10/Indexed.md',
              'sha': 'idx-sha',
              'content': githubBase64(noteMarkdown),
              'type': 'file',
            }),
            200,
          );
        }

        return http.Response('Not Found', 404);
      });

      final apiClient = GitHubApiClient(
        token: token,
        owner: owner,
        repo: repo,
        httpClient: mockClient,
      );

      final storage = GitHubNoteStorage(apiClient);

      // Populate cache via listNotes.
      await storage.listNotes(DateTime(2026, 3, 10));
      expect(listDirCallCount, 1);

      // getNote should use the index — no additional directory listing.
      final note =
          await storage.getNote('indexed-note', DateTime(2026, 3, 10));
      expect(note, isNotNull);
      expect(note!.id, 'indexed-note');
      expect(note.content, 'Indexed content');
      expect(listDirCallCount, 1); // Still 1 — no new listDirectory call.
    });

    test('saveNote deletes old file when title changes', () async {
      final requests = <http.BaseRequest>[];

      final mockClient = MockClient((request) async {
        requests.add(request);
        final decodedPath = Uri.decodeFull(request.url.path);

        if (request.method == 'PUT' &&
            decodedPath.contains('My Note.md')) {
          return http.Response(
            jsonEncode({
              'content': {
                'sha': 'sha-original',
                'name': 'My Note.md',
                'path': 'notes/2026-03/10/My Note.md',
              }
            }),
            201,
          );
        }

        if (request.method == 'DELETE' &&
            decodedPath.contains('My Note.md')) {
          return http.Response(
            jsonEncode({'commit': {'sha': 'commit-sha'}}),
            200,
          );
        }

        if (request.method == 'PUT' &&
            decodedPath.contains('Renamed Note.md')) {
          return http.Response(
            jsonEncode({
              'content': {
                'sha': 'sha-renamed',
                'name': 'Renamed Note.md',
                'path': 'notes/2026-03/10/Renamed Note.md',
              }
            }),
            201,
          );
        }

        return http.Response('Not Found', 404);
      });

      final apiClient = GitHubApiClient(
        token: token,
        owner: owner,
        repo: repo,
        httpClient: mockClient,
      );

      final storage = GitHubNoteStorage(apiClient);

      // First save with original title.
      final note = createTestNote(title: 'My Note');
      await storage.saveNote(note);

      // Rename title and save again.
      final renamedNote = Note(
        id: note.id,
        noteDate: note.noteDate,
        title: 'Renamed Note',
        content: note.content,
        isDefault: note.isDefault,
        tags: note.tags,
        createdAt: note.createdAt,
        updatedAt: DateTime.utc(2026, 3, 10, 11, 0, 0),
      );
      await storage.saveNote(renamedNote);

      // Verify: 1 PUT (original) + 1 DELETE (old file) + 1 PUT (renamed).
      final puts = requests.where((r) => r.method == 'PUT').toList();
      final deletes = requests.where((r) => r.method == 'DELETE').toList();

      expect(puts.length, 2);
      expect(deletes.length, 1);

      expect(Uri.decodeFull(deletes.first.url.path),
          contains('My Note.md'));
      expect(Uri.decodeFull(puts.last.url.path),
          contains('Renamed Note.md'));
    });

    test('saveNote with empty title uses note id as filename', () async {
      final requests = <http.BaseRequest>[];

      final mockClient = MockClient((request) async {
        requests.add(request);

        if (request.method == 'PUT') {
          return http.Response(
            jsonEncode({
              'content': {
                'sha': 'new-sha',
                'name': 'note-123.md',
                'path': 'notes/2026-03/10/note-123.md',
              }
            }),
            201,
          );
        }

        return http.Response('Not Found', 404);
      });

      final apiClient = GitHubApiClient(
        token: token,
        owner: owner,
        repo: repo,
        httpClient: mockClient,
      );

      final storage = GitHubNoteStorage(apiClient);
      final note = createTestNote(title: '');

      await storage.saveNote(note);

      expect(requests.first.url.path,
          '/repos/$owner/$repo/contents/notes/2026-03/10/note-123.md');
    });
  });

  group('serializeNote / parseNote isMemo round-trip', () {
    test('isMemo true survives serialize -> parse', () {
      final note = Note(
        id: 'memo-1',
        noteDate: DateTime(2026, 3, 10),
        title: 'Quick memo',
        content: 'jot',
        isDefault: false,
        tags: ['idea'],
        createdAt: DateTime.utc(2026, 3, 10, 9),
        updatedAt: DateTime.utc(2026, 3, 10, 10),
        isMemo: true,
      );

      final markdown = GitHubNoteStorage.serializeNote(note);
      expect(markdown, contains('is_memo: true'));

      final parsed = GitHubNoteStorage.parseNote(markdown);
      expect(parsed, isNotNull);
      expect(parsed!.isMemo, isTrue);
      expect(parsed.id, 'memo-1');
      expect(parsed.title, 'Quick memo');
    });

    test('parseNote defaults isMemo to false when frontmatter omits the field',
        () {
      const markdown = '''---
id: "legacy-1"
title: "Old note"
note_date: 2026-03-10
is_default: false
tags: []
created_at: 2026-03-10T09:00:00+0000
updated_at: 2026-03-10T10:00:00+0000
---
body
''';

      final parsed = GitHubNoteStorage.parseNote(markdown);
      expect(parsed, isNotNull);
      expect(parsed!.isMemo, isFalse);
    });
  });
}
