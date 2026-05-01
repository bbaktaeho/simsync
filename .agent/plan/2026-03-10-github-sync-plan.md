# GitHub 기반 노트 동기화 구현 계획

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** GitHub REST API를 저장소 백엔드로 사용하여 노트를 동기화하는 인터페이스 기반 스토리지 레이어 구현

**Architecture:** NoteStorage / SyncEngine / ConflictResolver 인터페이스를 정의하고, GitHub Contents API를 사용하는 구현체를 작성한다. 기존 NoteService(로컬 파일)는 NoteStorage 구현체로 리팩터링한다. 앱은 인터페이스에만 의존하므로 저장소를 자유롭게 교체할 수 있다.

**Tech Stack:** Flutter/Dart, GitHub REST API (Contents API), http 패키지 (이미 의존성에 있음)

**설계 문서:** `docs/plan/2026-03-10-github-sync-design.md`

---

## Task 1: NoteStorage 인터페이스 정의

**Files:**
- Create: `desktop/lib/storage/note_storage.dart`
- Test: `desktop/test/storage/note_storage_test.dart`

**Step 1: NoteStorage 인터페이스 작성**

```dart
// desktop/lib/storage/note_storage.dart
import '../models/note.dart';

/// 노트 저장소 추상 인터페이스.
/// 구현체에 따라 로컬 파일, GitHub, S3 등 다양한 백엔드를 지원한다.
abstract class NoteStorage {
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
```

**Step 2: 인터페이스 import 테스트 작성**

```dart
// desktop/test/storage/note_storage_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/storage/note_storage.dart';
import 'package:simsync/models/note.dart';

class FakeNoteStorage implements NoteStorage {
  final List<Note> notes = [];

  @override
  Future<List<Note>> listNotes(DateTime date) async {
    return notes.where((n) =>
      n.noteDate.year == date.year &&
      n.noteDate.month == date.month &&
      n.noteDate.day == date.day
    ).toList();
  }

  @override
  Future<List<DateTime>> listDates(String yearMonth) async {
    return notes
      .where((n) => '${n.noteDate.year}-${n.noteDate.month.toString().padLeft(2, '0')}' == yearMonth)
      .map((n) => n.noteDate)
      .toSet()
      .toList();
  }

  @override
  Future<Note?> getNote(String noteId, DateTime noteDate) async {
    try {
      return notes.firstWhere((n) => n.id == noteId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveNote(Note note) async {
    notes.removeWhere((n) => n.id == note.id);
    notes.add(note);
  }

  @override
  Future<void> deleteNote(Note note) async {
    notes.removeWhere((n) => n.id == note.id);
  }
}

void main() {
  group('NoteStorage interface', () {
    late FakeNoteStorage storage;
    late Note testNote;

    setUp(() {
      storage = FakeNoteStorage();
      testNote = Note(
        id: 'test-1',
        noteDate: DateTime(2026, 3, 10),
        title: '테스트 노트',
        content: '내용',
        isDefault: false,
        tags: [],
        createdAt: DateTime(2026, 3, 10),
        updatedAt: DateTime(2026, 3, 10),
      );
    });

    test('saveNote and listNotes', () async {
      await storage.saveNote(testNote);
      final notes = await storage.listNotes(DateTime(2026, 3, 10));
      expect(notes.length, 1);
      expect(notes.first.id, 'test-1');
    });

    test('getNote returns note by id', () async {
      await storage.saveNote(testNote);
      final note = await storage.getNote('test-1', DateTime(2026, 3, 10));
      expect(note, isNotNull);
      expect(note!.title, '테스트 노트');
    });

    test('getNote returns null for missing note', () async {
      final note = await storage.getNote('missing', DateTime(2026, 3, 10));
      expect(note, isNull);
    });

    test('deleteNote removes note', () async {
      await storage.saveNote(testNote);
      await storage.deleteNote(testNote);
      final notes = await storage.listNotes(DateTime(2026, 3, 10));
      expect(notes, isEmpty);
    });

    test('listDates returns dates with notes', () async {
      await storage.saveNote(testNote);
      final dates = await storage.listDates('2026-03');
      expect(dates.length, 1);
      expect(dates.first.day, 10);
    });
  });
}
```

**Step 3: 테스트 실행하여 통과 확인**

Run: `cd desktop && flutter test test/storage/note_storage_test.dart`
Expected: All tests PASS

**Step 4: 커밋**

```bash
git add desktop/lib/storage/note_storage.dart desktop/test/storage/note_storage_test.dart
git commit -m "feat: define NoteStorage abstract interface"
```

---

## Task 2: SyncEngine / ConflictResolver 인터페이스 정의

**Files:**
- Create: `desktop/lib/storage/sync_engine.dart`
- Create: `desktop/lib/storage/conflict_resolver.dart`

**Step 1: ConflictResolver 인터페이스 작성**

```dart
// desktop/lib/storage/conflict_resolver.dart
import '../models/note.dart';

/// 동기화 충돌 해결 전략 인터페이스.
abstract class ConflictResolver {
  /// 로컬과 리모트 노트가 충돌할 때 최종 내용을 결정한다.
  /// 반환값이 저장소에 기록된다.
  Future<Note> resolve(Note local, Note remote);
}

/// Last-Write-Wins: updatedAt이 더 최신인 노트를 선택한다.
class LastWriteWinsResolver implements ConflictResolver {
  @override
  Future<Note> resolve(Note local, Note remote) async {
    return local.updatedAt.isAfter(remote.updatedAt) ? local : remote;
  }
}
```

**Step 2: SyncEngine 인터페이스 작성**

```dart
// desktop/lib/storage/sync_engine.dart
import 'dart:async';

/// 동기화 상태.
enum SyncStatus { idle, syncing, error }

/// 동기화 엔진 인터페이스.
/// 저장소별로 다른 동기화 전략을 구현한다.
abstract class SyncEngine {
  /// 자동 동기화 시작 (인터벌 폴링).
  void start();

  /// 자동 동기화 중지.
  void stop();

  /// 즉시 동기화 실행.
  Future<void> syncNow();

  /// 현재 동기화 상태 스트림.
  Stream<SyncStatus> get statusStream;

  /// 리소스 정리.
  void dispose();
}
```

**Step 3: ConflictResolver 테스트 작성 및 실행**

```dart
// desktop/test/storage/conflict_resolver_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/storage/conflict_resolver.dart';
import 'package:simsync/models/note.dart';

void main() {
  group('LastWriteWinsResolver', () {
    late LastWriteWinsResolver resolver;

    setUp(() {
      resolver = LastWriteWinsResolver();
    });

    test('picks local when local is newer', () async {
      final local = Note(
        id: '1', noteDate: DateTime(2026, 3, 10),
        title: 'local', content: 'local content',
        isDefault: false, tags: [],
        createdAt: DateTime(2026, 3, 10),
        updatedAt: DateTime(2026, 3, 10, 12, 0),
      );
      final remote = Note(
        id: '1', noteDate: DateTime(2026, 3, 10),
        title: 'remote', content: 'remote content',
        isDefault: false, tags: [],
        createdAt: DateTime(2026, 3, 10),
        updatedAt: DateTime(2026, 3, 10, 11, 0),
      );
      final result = await resolver.resolve(local, remote);
      expect(result.title, 'local');
    });

    test('picks remote when remote is newer', () async {
      final local = Note(
        id: '1', noteDate: DateTime(2026, 3, 10),
        title: 'local', content: 'local content',
        isDefault: false, tags: [],
        createdAt: DateTime(2026, 3, 10),
        updatedAt: DateTime(2026, 3, 10, 11, 0),
      );
      final remote = Note(
        id: '1', noteDate: DateTime(2026, 3, 10),
        title: 'remote', content: 'remote content',
        isDefault: false, tags: [],
        createdAt: DateTime(2026, 3, 10),
        updatedAt: DateTime(2026, 3, 10, 12, 0),
      );
      final result = await resolver.resolve(local, remote);
      expect(result.title, 'remote');
    });
  });
}
```

Run: `cd desktop && flutter test test/storage/conflict_resolver_test.dart`
Expected: All tests PASS

**Step 4: 커밋**

```bash
git add desktop/lib/storage/sync_engine.dart desktop/lib/storage/conflict_resolver.dart desktop/test/storage/conflict_resolver_test.dart
git commit -m "feat: define SyncEngine and ConflictResolver interfaces"
```

---

## Task 3: GitHub API 클라이언트 구현

**Files:**
- Create: `desktop/lib/storage/github/github_api_client.dart`
- Test: `desktop/test/storage/github/github_api_client_test.dart`

GitHub Contents API 호출을 캡슐화하는 저수준 클라이언트. NoteStorage에 직접 노출되지 않는다.

**Step 1: GitHub API 응답 모델 작성**

```dart
// desktop/lib/storage/github/github_api_client.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

/// GitHub Contents API의 파일 정보.
class GitHubFile {
  final String name;
  final String path;
  final String sha;
  final String? content; // Base64 인코딩, 파일일 때만 존재
  final String type; // "file" or "dir"

  GitHubFile({
    required this.name,
    required this.path,
    required this.sha,
    this.content,
    required this.type,
  });

  factory GitHubFile.fromJson(Map<String, dynamic> json) {
    return GitHubFile(
      name: json['name'] as String,
      path: json['path'] as String,
      sha: json['sha'] as String,
      content: json['content'] as String?,
      type: json['type'] as String,
    );
  }

  /// Base64 디코딩된 파일 내용.
  String? get decodedContent {
    if (content == null) return null;
    // GitHub API returns Base64 with newlines
    final cleaned = content!.replaceAll('\n', '');
    return utf8.decode(base64.decode(cleaned));
  }
}

/// GitHub Contents API 클라이언트.
class GitHubApiClient {
  final String _token;
  final String _owner;
  final String _repo;
  final http.Client _httpClient;

  static const _baseUrl = 'https://api.github.com';

  GitHubApiClient({
    required String token,
    required String owner,
    required String repo,
    http.Client? httpClient,
  })  : _token = token,
        _owner = owner,
        _repo = repo,
        _httpClient = httpClient ?? http.Client();

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $_token',
    'Accept': 'application/vnd.github.v3+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  String _contentsUrl(String path) =>
      '$_baseUrl/repos/$_owner/$_repo/contents/$path';

  /// 파일 또는 디렉토리 내용 조회.
  /// 디렉토리면 List<GitHubFile>, 파일이면 단일 GitHubFile 반환.
  Future<GitHubFile> getFile(String path) async {
    final response = await _httpClient.get(
      Uri.parse(_contentsUrl(path)),
      headers: _headers,
    );
    if (response.statusCode == 404) {
      throw GitHubNotFoundException(path);
    }
    if (response.statusCode != 200) {
      throw GitHubApiException(response.statusCode, response.body);
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return GitHubFile.fromJson(json);
  }

  /// 디렉토리 내 파일 목록 조회.
  Future<List<GitHubFile>> listDirectory(String path) async {
    final response = await _httpClient.get(
      Uri.parse(_contentsUrl(path)),
      headers: _headers,
    );
    if (response.statusCode == 404) {
      return [];
    }
    if (response.statusCode != 200) {
      throw GitHubApiException(response.statusCode, response.body);
    }
    final json = jsonDecode(response.body);
    if (json is List) {
      return json
          .map((e) => GitHubFile.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  /// 파일 생성 또는 수정.
  /// [sha]가 null이면 새 파일 생성, 있으면 기존 파일 수정.
  Future<String> putFile({
    required String path,
    required String content,
    required String message,
    String? sha,
  }) async {
    final body = {
      'message': message,
      'content': base64.encode(utf8.encode(content)),
      if (sha != null) 'sha': sha,
    };
    final response = await _httpClient.put(
      Uri.parse(_contentsUrl(path)),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (response.statusCode == 409) {
      throw GitHubConflictException(path);
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw GitHubApiException(response.statusCode, response.body);
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final fileJson = json['content'] as Map<String, dynamic>;
    return fileJson['sha'] as String;
  }

  /// 파일 삭제.
  Future<void> deleteFile({
    required String path,
    required String sha,
    required String message,
  }) async {
    final body = {
      'message': message,
      'sha': sha,
    };
    final request = http.Request('DELETE', Uri.parse(_contentsUrl(path)));
    request.headers.addAll(_headers);
    request.body = jsonEncode(body);
    final streamed = await _httpClient.send(request);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      throw GitHubApiException(response.statusCode, response.body);
    }
  }

  void dispose() {
    _httpClient.close();
  }
}

class GitHubApiException implements Exception {
  final int statusCode;
  final String body;
  GitHubApiException(this.statusCode, this.body);
  @override
  String toString() => 'GitHubApiException($statusCode): $body';
}

class GitHubNotFoundException implements Exception {
  final String path;
  GitHubNotFoundException(this.path);
  @override
  String toString() => 'GitHubNotFoundException: $path';
}

class GitHubConflictException implements Exception {
  final String path;
  GitHubConflictException(this.path);
  @override
  String toString() => 'GitHubConflictException: $path';
}
```

**Step 2: 테스트 작성 (mock http client)**

```dart
// desktop/test/storage/github/github_api_client_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:simsync/storage/github/github_api_client.dart';

void main() {
  group('GitHubApiClient', () {
    late GitHubApiClient client;

    GitHubApiClient createClient(http_testing.MockClient mockHttp) {
      return GitHubApiClient(
        token: 'test-token',
        owner: 'testuser',
        repo: 'notes',
        httpClient: mockHttp,
      );
    }

    test('getFile returns file with decoded content', () async {
      final content = base64.encode(utf8.encode('Hello World'));
      final mockHttp = http_testing.MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer test-token');
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
      client = createClient(mockHttp);
      final file = await client.getFile('notes/test.md');
      expect(file.name, 'test.md');
      expect(file.decodedContent, 'Hello World');
      expect(file.sha, 'abc123');
    });

    test('getFile throws GitHubNotFoundException on 404', () async {
      final mockHttp = http_testing.MockClient((_) async {
        return http.Response('', 404);
      });
      client = createClient(mockHttp);
      expect(
        () => client.getFile('missing.md'),
        throwsA(isA<GitHubNotFoundException>()),
      );
    });

    test('listDirectory returns file list', () async {
      final mockHttp = http_testing.MockClient((_) async {
        return http.Response(
          jsonEncode([
            {'name': 'a.md', 'path': 'notes/a.md', 'sha': '1', 'type': 'file'},
            {'name': 'b.md', 'path': 'notes/b.md', 'sha': '2', 'type': 'file'},
          ]),
          200,
        );
      });
      client = createClient(mockHttp);
      final files = await client.listDirectory('notes');
      expect(files.length, 2);
      expect(files[0].name, 'a.md');
    });

    test('listDirectory returns empty on 404', () async {
      final mockHttp = http_testing.MockClient((_) async {
        return http.Response('', 404);
      });
      client = createClient(mockHttp);
      final files = await client.listDirectory('notes/missing');
      expect(files, isEmpty);
    });

    test('putFile creates file and returns sha', () async {
      final mockHttp = http_testing.MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['message'], 'create note');
        expect(body.containsKey('sha'), false);
        return http.Response(
          jsonEncode({
            'content': {'sha': 'new-sha-123'},
          }),
          201,
        );
      });
      client = createClient(mockHttp);
      final sha = await client.putFile(
        path: 'notes/test.md',
        content: 'content',
        message: 'create note',
      );
      expect(sha, 'new-sha-123');
    });

    test('putFile throws GitHubConflictException on 409', () async {
      final mockHttp = http_testing.MockClient((_) async {
        return http.Response('', 409);
      });
      client = createClient(mockHttp);
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

    test('deleteFile sends DELETE with sha', () async {
      final mockHttp = http_testing.MockClient((request) async {
        expect(request.method, 'DELETE');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['sha'], 'abc123');
        return http.Response('{}', 200);
      });
      client = createClient(mockHttp);
      await client.deleteFile(
        path: 'notes/test.md',
        sha: 'abc123',
        message: 'delete note',
      );
    });
  });
}
```

**Step 3: 테스트 실행**

Run: `cd desktop && flutter test test/storage/github/github_api_client_test.dart`
Expected: All tests PASS

**Step 4: 커밋**

```bash
git add desktop/lib/storage/github/github_api_client.dart desktop/test/storage/github/github_api_client_test.dart
git commit -m "feat: implement GitHub Contents API client with tests"
```

---

## Task 4: GitHubNoteStorage 구현 (NoteStorage 구현체)

**Files:**
- Create: `desktop/lib/storage/github/github_note_storage.dart`
- Test: `desktop/test/storage/github/github_note_storage_test.dart`

**Step 1: GitHubNoteStorage 작성**

```dart
// desktop/lib/storage/github/github_note_storage.dart
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';

import '../../models/note.dart';
import '../note_storage.dart';
import 'github_api_client.dart';

const _uuid = Uuid();
final _dirDateFmt = DateFormat('yyyy-MM-dd');
final _isoFmt = DateFormat("yyyy-MM-dd'T'HH:mm:ssZ");
final _monthFmt = DateFormat('yyyy-MM');

class GitHubNoteStorage implements NoteStorage {
  final GitHubApiClient _api;
  final String _basePath;

  /// 파일 경로 → SHA 매핑. PUT/DELETE 시 필요.
  final Map<String, String> _shaCache = {};

  GitHubNoteStorage({
    required GitHubApiClient api,
    String basePath = 'notes',
  })  : _api = api,
        _basePath = basePath;

  /// notes/{YYYY-MM}/{DD}/{title}.md
  String _notePath(Note note) {
    final month = _monthFmt.format(note.noteDate);
    final day = note.noteDate.day.toString().padLeft(2, '0');
    final fileName = _sanitizeFileName(note.title.isEmpty ? note.id : note.title);
    return '$_basePath/$month/$day/$fileName.md';
  }

  String _sanitizeFileName(String name) {
    // 파일명에 사용 불가한 문자 제거
    return name.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_').trim();
  }

  @override
  Future<List<Note>> listNotes(DateTime date) async {
    final month = _monthFmt.format(date);
    final day = date.day.toString().padLeft(2, '0');
    final dirPath = '$_basePath/$month/$day';

    final files = await _api.listDirectory(dirPath);
    final notes = <Note>[];

    for (final file in files) {
      if (file.type != 'file' || !file.name.endsWith('.md')) continue;
      try {
        final fullFile = await _api.getFile(file.path);
        final content = fullFile.decodedContent;
        if (content == null) continue;
        final note = _parseMarkdown(content, file.path);
        if (note != null) {
          _shaCache[file.path] = fullFile.sha;
          notes.add(note);
        }
      } catch (_) {
        continue;
      }
    }
    return notes;
  }

  @override
  Future<List<DateTime>> listDates(String yearMonth) async {
    final dirPath = '$_basePath/$yearMonth';
    final dirs = await _api.listDirectory(dirPath);
    final dates = <DateTime>[];

    for (final dir in dirs) {
      if (dir.type != 'dir') continue;
      final day = int.tryParse(dir.name);
      if (day == null) continue;
      final parts = yearMonth.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      dates.add(DateTime(year, month, day));
    }
    return dates;
  }

  @override
  Future<Note?> getNote(String noteId, DateTime noteDate) async {
    // noteId 기반으로 해당 날짜 디렉토리를 탐색
    final month = _monthFmt.format(noteDate);
    final day = noteDate.day.toString().padLeft(2, '0');
    final dirPath = '$_basePath/$month/$day';

    final files = await _api.listDirectory(dirPath);
    for (final file in files) {
      if (file.type != 'file' || !file.name.endsWith('.md')) continue;
      final fullFile = await _api.getFile(file.path);
      final content = fullFile.decodedContent;
      if (content == null) continue;
      final note = _parseMarkdown(content, file.path);
      if (note != null && note.id == noteId) {
        _shaCache[file.path] = fullFile.sha;
        return note;
      }
    }
    return null;
  }

  @override
  Future<void> saveNote(Note note) async {
    final path = _notePath(note);
    final content = _serializeNote(note);
    final sha = _shaCache[path];

    try {
      final newSha = await _api.putFile(
        path: path,
        content: content,
        message: 'Update ${note.title}',
        sha: sha,
      );
      _shaCache[path] = newSha;
    } on GitHubConflictException {
      // Last-Write-Wins: 최신 SHA를 가져와서 덮어쓰기
      final latest = await _api.getFile(path);
      final newSha = await _api.putFile(
        path: path,
        content: content,
        message: 'Update ${note.title} (conflict resolved)',
        sha: latest.sha,
      );
      _shaCache[path] = newSha;
    }
  }

  @override
  Future<void> deleteNote(Note note) async {
    final path = _notePath(note);
    final sha = _shaCache[path];
    if (sha == null) return;

    await _api.deleteFile(
      path: path,
      sha: sha,
      message: 'Delete ${note.title}',
    );
    _shaCache.remove(path);
  }

  // ── Serialization ──

  Note? _parseMarkdown(String raw, String filePath) {
    if (!raw.startsWith('---')) return null;
    final endIdx = raw.indexOf('---', 3);
    if (endIdx == -1) return null;

    final frontmatterStr = raw.substring(3, endIdx).trim();
    final content = raw.substring(endIdx + 3).trim();

    try {
      final fm = loadYaml(frontmatterStr);
      if (fm is! YamlMap) return null;

      final tags = <String>[];
      if (fm['tags'] is YamlList) {
        for (final t in fm['tags'] as YamlList) {
          tags.add(t.toString());
        }
      }

      return Note(
        id: (fm['id'] ?? _uuid.v4()).toString(),
        noteDate: DateTime.parse(fm['note_date'].toString()),
        title: (fm['title'] ?? '').toString(),
        content: content,
        isDefault: fm['is_default'] == true,
        tags: tags,
        createdAt: _parseDateTime(fm['created_at']),
        updatedAt: _parseDateTime(fm['updated_at']),
      );
    } catch (_) {
      return null;
    }
  }

  DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    try {
      return DateTime.parse(value.toString());
    } catch (_) {
      return DateTime.now();
    }
  }

  String _serializeNote(Note note) {
    final tagsLine = note.tags.isEmpty
        ? '[]'
        : '[${note.tags.map((t) => '"$t"').join(', ')}]';

    return '''---
id: "${note.id}"
title: "${_escapeYaml(note.title)}"
note_date: ${_dirDateFmt.format(note.noteDate)}
is_default: ${note.isDefault}
tags: $tagsLine
created_at: ${_isoFmt.format(note.createdAt)}
updated_at: ${_isoFmt.format(note.updatedAt)}
---
${note.content}''';
  }

  String _escapeYaml(String value) {
    return value.replaceAll('"', '\\"');
  }
}
```

**Step 2: 테스트 작성 (mock GitHubApiClient)**

```dart
// desktop/test/storage/github/github_note_storage_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:simsync/models/note.dart';
import 'package:simsync/storage/github/github_api_client.dart';
import 'package:simsync/storage/github/github_note_storage.dart';

void main() {
  group('GitHubNoteStorage', () {
    late Note testNote;

    setUp(() {
      testNote = Note(
        id: 'note-1',
        noteDate: DateTime(2026, 3, 10),
        title: '테스트 노트',
        content: '노트 내용입니다.',
        isDefault: false,
        tags: ['dev'],
        createdAt: DateTime(2026, 3, 10, 9, 0),
        updatedAt: DateTime(2026, 3, 10, 10, 0),
      );
    });

    test('saveNote creates file via API', () async {
      String? capturedPath;
      final mockHttp = http_testing.MockClient((request) async {
        if (request.method == 'PUT') {
          capturedPath = request.url.path;
          return http.Response(
            jsonEncode({'content': {'sha': 'new-sha'}}),
            201,
          );
        }
        return http.Response('', 404);
      });

      final api = GitHubApiClient(
        token: 'tok', owner: 'user', repo: 'notes', httpClient: mockHttp,
      );
      final storage = GitHubNoteStorage(api: api);
      await storage.saveNote(testNote);

      expect(capturedPath, contains('2026-03/10'));
      expect(capturedPath, contains('.md'));
    });

    test('saveNote handles 409 conflict with Last-Write-Wins', () async {
      var putCount = 0;
      final noteContent = base64.encode(utf8.encode('''---
id: "note-1"
title: "원래 노트"
note_date: 2026-03-10
is_default: false
tags: []
created_at: 2026-03-10T09:00:00+0000
updated_at: 2026-03-10T09:30:00+0000
---
원래 내용'''));

      final mockHttp = http_testing.MockClient((request) async {
        if (request.method == 'PUT') {
          putCount++;
          if (putCount == 1) {
            return http.Response('', 409);
          }
          return http.Response(
            jsonEncode({'content': {'sha': 'resolved-sha'}}),
            200,
          );
        }
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'name': '테스트 노트.md',
              'path': 'notes/2026-03/10/테스트 노트.md',
              'sha': 'latest-sha',
              'content': noteContent,
              'type': 'file',
            }),
            200,
          );
        }
        return http.Response('', 404);
      });

      final api = GitHubApiClient(
        token: 'tok', owner: 'user', repo: 'notes', httpClient: mockHttp,
      );
      final storage = GitHubNoteStorage(api: api);
      await storage.saveNote(testNote);

      expect(putCount, 2); // 첫 번째 409, 두 번째 성공
    });

    test('listDates returns dates from directory listing', () async {
      final mockHttp = http_testing.MockClient((_) async {
        return http.Response(
          jsonEncode([
            {'name': '10', 'path': 'notes/2026-03/10', 'sha': '1', 'type': 'dir'},
            {'name': '15', 'path': 'notes/2026-03/15', 'sha': '2', 'type': 'dir'},
          ]),
          200,
        );
      });

      final api = GitHubApiClient(
        token: 'tok', owner: 'user', repo: 'notes', httpClient: mockHttp,
      );
      final storage = GitHubNoteStorage(api: api);
      final dates = await storage.listDates('2026-03');

      expect(dates.length, 2);
      expect(dates[0], DateTime(2026, 3, 10));
      expect(dates[1], DateTime(2026, 3, 15));
    });
  });
}
```

**Step 3: 테스트 실행**

Run: `cd desktop && flutter test test/storage/github/github_note_storage_test.dart`
Expected: All tests PASS

**Step 4: 커밋**

```bash
git add desktop/lib/storage/github/github_note_storage.dart desktop/test/storage/github/github_note_storage_test.dart
git commit -m "feat: implement GitHubNoteStorage with Contents API"
```

---

## Task 5: GitHubSyncEngine 구현

**Files:**
- Create: `desktop/lib/storage/github/github_sync_engine.dart`
- Test: `desktop/test/storage/github/github_sync_engine_test.dart`

**Step 1: GitHubSyncEngine 작성**

```dart
// desktop/lib/storage/github/github_sync_engine.dart
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../sync_engine.dart';

/// GitHub 커밋 기반 폴링 동기화 엔진.
class GitHubSyncEngine implements SyncEngine {
  final String _token;
  final String _owner;
  final String _repo;
  final String _branch;
  final Duration _interval;
  final http.Client _httpClient;
  final void Function() _onRemoteChanged;

  Timer? _timer;
  String? _lastCommitSha;
  final _statusController = StreamController<SyncStatus>.broadcast();

  GitHubSyncEngine({
    required String token,
    required String owner,
    required String repo,
    String branch = 'main',
    Duration interval = const Duration(seconds: 5),
    http.Client? httpClient,
    required void Function() onRemoteChanged,
  })  : _token = token,
        _owner = owner,
        _repo = repo,
        _branch = branch,
        _interval = interval,
        _httpClient = httpClient ?? http.Client(),
        _onRemoteChanged = onRemoteChanged;

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $_token',
    'Accept': 'application/vnd.github.v3+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  @override
  Stream<SyncStatus> get statusStream => _statusController.stream;

  @override
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => syncNow());
    // 시작 직후 한 번 동기화
    syncNow();
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<void> syncNow() async {
    _statusController.add(SyncStatus.syncing);
    try {
      final latestSha = await _fetchLatestCommitSha();
      if (latestSha != null && latestSha != _lastCommitSha) {
        _lastCommitSha = latestSha;
        _onRemoteChanged();
      }
      _statusController.add(SyncStatus.idle);
    } catch (_) {
      _statusController.add(SyncStatus.error);
    }
  }

  Future<String?> _fetchLatestCommitSha() async {
    final url = 'https://api.github.com/repos/$_owner/$_repo/commits?sha=$_branch&per_page=1';
    final response = await _httpClient.get(
      Uri.parse(url),
      headers: _headers,
    );
    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body);
    if (json is List && json.isNotEmpty) {
      return json[0]['sha'] as String;
    }
    return null;
  }

  @override
  void dispose() {
    stop();
    _statusController.close();
    _httpClient.close();
  }
}
```

**Step 2: 테스트 작성**

```dart
// desktop/test/storage/github/github_sync_engine_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:simsync/storage/github/github_sync_engine.dart';
import 'package:simsync/storage/sync_engine.dart';

void main() {
  group('GitHubSyncEngine', () {
    test('syncNow calls onRemoteChanged when commit SHA changes', () async {
      var callCount = 0;
      var currentSha = 'sha-1';

      final mockHttp = http_testing.MockClient((_) async {
        return http.Response(
          jsonEncode([{'sha': currentSha}]),
          200,
        );
      });

      final engine = GitHubSyncEngine(
        token: 'tok',
        owner: 'user',
        repo: 'notes',
        httpClient: mockHttp,
        onRemoteChanged: () => callCount++,
      );

      await engine.syncNow();
      expect(callCount, 1); // 첫 호출은 항상 변경으로 감지

      await engine.syncNow();
      expect(callCount, 1); // SHA 동일하면 호출 안 함

      currentSha = 'sha-2';
      await engine.syncNow();
      expect(callCount, 2); // SHA 변경되면 호출

      engine.dispose();
    });

    test('syncNow emits syncing then idle status', () async {
      final mockHttp = http_testing.MockClient((_) async {
        return http.Response(jsonEncode([{'sha': 'sha-1'}]), 200);
      });

      final engine = GitHubSyncEngine(
        token: 'tok',
        owner: 'user',
        repo: 'notes',
        httpClient: mockHttp,
        onRemoteChanged: () {},
      );

      final statuses = <SyncStatus>[];
      engine.statusStream.listen(statuses.add);

      await engine.syncNow();
      await Future.delayed(Duration(milliseconds: 50));

      expect(statuses, contains(SyncStatus.syncing));
      expect(statuses, contains(SyncStatus.idle));

      engine.dispose();
    });

    test('syncNow emits error status on API failure', () async {
      final mockHttp = http_testing.MockClient((_) async {
        return http.Response('', 500);
      });

      final engine = GitHubSyncEngine(
        token: 'tok',
        owner: 'user',
        repo: 'notes',
        httpClient: mockHttp,
        onRemoteChanged: () {},
      );

      final statuses = <SyncStatus>[];
      engine.statusStream.listen(statuses.add);

      await engine.syncNow();
      await Future.delayed(Duration(milliseconds: 50));

      expect(statuses, contains(SyncStatus.error));

      engine.dispose();
    });
  });
}
```

**Step 3: 테스트 실행**

Run: `cd desktop && flutter test test/storage/github/github_sync_engine_test.dart`
Expected: All tests PASS

**Step 4: 커밋**

```bash
git add desktop/lib/storage/github/github_sync_engine.dart desktop/test/storage/github/github_sync_engine_test.dart
git commit -m "feat: implement GitHubSyncEngine with commit polling"
```

---

## Task 6: 기존 NoteService를 NoteStorage 구현체로 리팩터링

**Files:**
- Modify: `desktop/lib/services/note_service.dart`
- Modify: `desktop/lib/screens/document_screen.dart` (NoteStorage 인터페이스 사용으로 전환)
- Modify: 기존 테스트 파일

기존 NoteService가 NoteStorage를 implements 하도록 변경한다.
DocumentScreen이 NoteService 대신 NoteStorage 인터페이스에 의존하도록 수정한다.

**Step 1: NoteService에 NoteStorage implements 추가**

`desktop/lib/services/note_service.dart` 수정:
- `class NoteService` → `class NoteService implements NoteStorage`
- 기존 메서드를 NoteStorage 인터페이스에 맞게 조정 (listNotes, listDates, getNote, saveNote, deleteNote)
- `loadAllNotes()`, `createNote()` 등 NoteService 고유 메서드는 유지 (convenience)

**Step 2: DocumentScreen에서 NoteStorage 인터페이스로 교체**

`desktop/lib/screens/document_screen.dart` 수정:
- `NoteService` 타입 → `NoteStorage` 타입으로 변경 (필요한 곳만)
- NoteService 고유 메서드(createNote 등)를 사용하는 곳은 그대로 유지하되, 향후 추상화 가능하도록 분리

**Step 3: 테스트 실행으로 기존 기능 깨지지 않았는지 확인**

Run: `cd desktop && flutter test`
Expected: All existing tests PASS

**Step 4: 커밋**

```bash
git add desktop/lib/services/note_service.dart desktop/lib/screens/document_screen.dart
git commit -m "refactor: NoteService implements NoteStorage interface"
```

---

## Task 7: GitHub 저장소 설정 UI 및 연결

**Files:**
- Create: `desktop/lib/storage/github/github_storage_config.dart`
- Modify: `desktop/lib/main.dart`

인증 후 GitHub repo 선택/생성 흐름을 추가한다.

**Step 1: 설정 모델 작성**

```dart
// desktop/lib/storage/github/github_storage_config.dart
import 'dart:convert';
import 'dart:io';

/// GitHub 저장소 연결 설정.
class GitHubStorageConfig {
  final String owner;
  final String repo;
  final String branch;
  final Duration syncInterval;

  const GitHubStorageConfig({
    required this.owner,
    required this.repo,
    this.branch = 'main',
    this.syncInterval = const Duration(seconds: 5),
  });

  factory GitHubStorageConfig.fromJson(Map<String, dynamic> json) {
    return GitHubStorageConfig(
      owner: json['owner'] as String,
      repo: json['repo'] as String,
      branch: (json['branch'] as String?) ?? 'main',
      syncInterval: Duration(
        seconds: (json['syncIntervalSeconds'] as int?) ?? 5,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'owner': owner,
    'repo': repo,
    'branch': branch,
    'syncIntervalSeconds': syncInterval.inSeconds,
  };

  /// 설정 파일 경로: ~/.simsync/github_config.json
  static Future<GitHubStorageConfig?> load() async {
    final home = Platform.environment['HOME'] ?? '.';
    final file = File('$home/.simsync/github_config.json');
    if (!await file.exists()) return null;
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return GitHubStorageConfig.fromJson(json);
  }

  Future<void> save() async {
    final home = Platform.environment['HOME'] ?? '.';
    final dir = Directory('$home/.simsync');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}/github_config.json');
    await file.writeAsString(jsonEncode(toJson()));
  }
}
```

**Step 2: main.dart에서 인증 토큰 + 설정 → GitHubNoteStorage / GitHubSyncEngine 조립**

앱 시작 시:
1. 세션 복원 → OAuth 토큰 획득
2. GitHubStorageConfig 로드
3. 설정이 있으면 GitHubNoteStorage + GitHubSyncEngine 생성
4. 설정이 없으면 설정 화면으로 안내

**Step 3: 테스트 실행**

Run: `cd desktop && flutter test`
Expected: All tests PASS

**Step 4: 커밋**

```bash
git add desktop/lib/storage/github/github_storage_config.dart desktop/lib/main.dart
git commit -m "feat: add GitHub storage config and app wiring"
```

---

## 구현 순서 요약

| Task | 내용 | 의존성 |
|------|------|--------|
| 1 | NoteStorage 인터페이스 | 없음 |
| 2 | SyncEngine / ConflictResolver 인터페이스 | 없음 |
| 3 | GitHub API 클라이언트 | 없음 |
| 4 | GitHubNoteStorage 구현 | Task 1, 3 |
| 5 | GitHubSyncEngine 구현 | Task 2, 3 |
| 6 | NoteService 리팩터링 | Task 1 |
| 7 | 설정 + 앱 연결 | Task 4, 5, 6 |

Task 1, 2, 3은 독립적이므로 병렬 실행 가능.
