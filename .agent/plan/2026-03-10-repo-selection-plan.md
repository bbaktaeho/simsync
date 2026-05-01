# 저장소 선택 화면 + Repo 관리 구현 계획

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 로그인 후 GitHub 저장소를 선택/생성하는 화면을 추가하고, 에디터에 프로필 이미지를 표시한다.

**Architecture:** `_AppShell`에 `repoSelection` 상태를 추가하여 로그인→저장소 선택→에디터 흐름을 구현한다. `RepoCache`가 연동 이력을 로컬 JSON으로 관리하고, `GitHubApiClient`에 repo 생성 메서드를 추가한다.

**Tech Stack:** Flutter/Dart, GitHub REST API (Repos API + Contents API), http 패키지

---

## Task 1: OAuth scope에 `repo` 추가

**Files:**
- Modify: `desktop/lib/auth/github_oauth_provider.dart:131`

**Step 1: scope 변경**

`desktop/lib/auth/github_oauth_provider.dart` 131번 줄:
```dart
// 변경 전
'scope': 'read:user user:email',
// 변경 후
'scope': 'read:user user:email repo',
```

**Step 2: 테스트 실행**

Run: `cd /Users/bbaktaeho/github/simsync/desktop && flutter test test/auth/`
Expected: All auth tests PASS (scope 값 체크하는 테스트가 있다면 업데이트)

**Step 3: 커밋**

```bash
git add desktop/lib/auth/github_oauth_provider.dart
git commit -m "feat: add repo scope to OAuth for GitHub storage access"
```

---

## Task 2: RepoCache 구현 (연동 이력 로컬 캐시)

**Files:**
- Create: `desktop/lib/storage/github/repo_cache.dart`
- Test: `desktop/test/storage/github/repo_cache_test.dart`

**Step 1: RepoEntry 모델 + RepoCache 구현**

```dart
// desktop/lib/storage/github/repo_cache.dart
import 'dart:convert';
import 'dart:io';

class RepoEntry {
  final String owner;
  final String repo;
  final String branch;
  final DateTime connectedAt;

  const RepoEntry({
    required this.owner,
    required this.repo,
    this.branch = 'main',
    required this.connectedAt,
  });

  factory RepoEntry.fromJson(Map<String, dynamic> json) {
    return RepoEntry(
      owner: json['owner'] as String,
      repo: json['repo'] as String,
      branch: (json['branch'] as String?) ?? 'main',
      connectedAt: DateTime.parse(json['connectedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'owner': owner,
    'repo': repo,
    'branch': branch,
    'connectedAt': connectedAt.toIso8601String(),
  };

  String get fullName => '$owner/$repo';
}

/// 연동 이력을 ~/.simsync/repos.json에 저장/조회/삭제한다.
class RepoCache {
  final String _path;

  RepoCache._(this._path);

  factory RepoCache() {
    final home = Platform.environment['HOME'] ?? '.';
    return RepoCache._('$home/.simsync/repos.json');
  }

  /// 테스트용 생성자.
  factory RepoCache.withPath(String path) => RepoCache._(path);

  Future<List<RepoEntry>> load() async {
    final file = File(_path);
    if (!await file.exists()) return [];
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! List) return [];
      return json
          .map((e) => RepoEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> add(RepoEntry entry) async {
    final entries = await load();
    // 중복 제거 (같은 owner/repo)
    entries.removeWhere((e) => e.owner == entry.owner && e.repo == entry.repo);
    entries.insert(0, entry); // 최신을 맨 앞에
    await _save(entries);
  }

  Future<void> remove(String owner, String repo) async {
    final entries = await load();
    entries.removeWhere((e) => e.owner == owner && e.repo == repo);
    await _save(entries);
  }

  Future<void> _save(List<RepoEntry> entries) async {
    final dir = Directory(File(_path).parent.path);
    if (!await dir.exists()) await dir.create(recursive: true);
    await File(_path).writeAsString(
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }
}
```

**Step 2: 테스트 작성**

```dart
// desktop/test/storage/github/repo_cache_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/storage/github/repo_cache.dart';

void main() {
  group('RepoCache', () {
    late String tempPath;
    late RepoCache cache;

    setUp(() {
      tempPath = '${Directory.systemTemp.path}/test_repos_${DateTime.now().millisecondsSinceEpoch}.json';
      cache = RepoCache.withPath(tempPath);
    });

    tearDown(() {
      final file = File(tempPath);
      if (file.existsSync()) file.deleteSync();
    });

    test('load returns empty list when file missing', () async {
      final entries = await cache.load();
      expect(entries, isEmpty);
    });

    test('add and load round-trip', () async {
      final entry = RepoEntry(
        owner: 'user', repo: 'notes', connectedAt: DateTime(2026, 3, 10),
      );
      await cache.add(entry);
      final entries = await cache.load();
      expect(entries.length, 1);
      expect(entries.first.fullName, 'user/notes');
    });

    test('add replaces duplicate owner/repo', () async {
      await cache.add(RepoEntry(
        owner: 'user', repo: 'notes', connectedAt: DateTime(2026, 3, 10),
      ));
      await cache.add(RepoEntry(
        owner: 'user', repo: 'notes', connectedAt: DateTime(2026, 3, 11),
      ));
      final entries = await cache.load();
      expect(entries.length, 1);
      expect(entries.first.connectedAt.day, 11);
    });

    test('remove deletes entry by owner/repo', () async {
      await cache.add(RepoEntry(
        owner: 'user', repo: 'notes', connectedAt: DateTime(2026, 3, 10),
      ));
      await cache.remove('user', 'notes');
      final entries = await cache.load();
      expect(entries, isEmpty);
    });

    test('load returns empty on corrupt file', () async {
      await File(tempPath).writeAsString('not json');
      final entries = await cache.load();
      expect(entries, isEmpty);
    });
  });
}
```

**Step 3: 테스트 실행**

Run: `cd /Users/bbaktaeho/github/simsync/desktop && flutter test test/storage/github/repo_cache_test.dart`

**Step 4: 커밋**

```bash
git add desktop/lib/storage/github/repo_cache.dart desktop/test/storage/github/repo_cache_test.dart
git commit -m "feat: implement RepoCache for local repo connection history"
```

---

## Task 3: GitHubApiClient에 repo 생성 메서드 추가

**Files:**
- Modify: `desktop/lib/storage/github/github_api_client.dart`
- Modify: `desktop/test/storage/github/github_api_client_test.dart`

**Step 1: createRepo 메서드 추가**

`GitHubApiClient`에 추가:
```dart
/// 새 private repo 생성. 생성된 repo의 full_name을 반환한다.
Future<String> createRepo({required String name}) async {
  final response = await _httpClient.post(
    Uri.parse('$_baseUrl/user/repos'),
    headers: _headers,
    body: jsonEncode({
      'name': name,
      'private': true,
      'auto_init': true, // README 생성하여 빈 repo 방지
    }),
  );
  if (response.statusCode == 422) {
    throw GitHubApiException(422, 'Repository already exists');
  }
  if (response.statusCode != 201) {
    throw GitHubApiException(response.statusCode, response.body);
  }
  final json = jsonDecode(response.body) as Map<String, dynamic>;
  return json['full_name'] as String;
}

/// repo 존재 여부 확인.
Future<bool> repoExists({required String owner, required String repo}) async {
  final response = await _httpClient.get(
    Uri.parse('$_baseUrl/repos/$owner/$repo'),
    headers: _headers,
  );
  return response.statusCode == 200;
}
```

**Step 2: 테스트 추가**

```dart
test('createRepo creates private repo and returns full_name', () async {
  final mockHttp = http_testing.MockClient((request) async {
    expect(request.method, 'POST');
    expect(request.url.path, '/user/repos');
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['private'], true);
    expect(body['auto_init'], true);
    return http.Response(
      jsonEncode({'full_name': 'user/my-notes'}),
      201,
    );
  });
  client = createClient(mockHttp);
  final name = await client.createRepo(name: 'my-notes');
  expect(name, 'user/my-notes');
});

test('createRepo throws on 422 (already exists)', () async {
  final mockHttp = http_testing.MockClient((_) async {
    return http.Response('', 422);
  });
  client = createClient(mockHttp);
  expect(
    () => client.createRepo(name: 'existing'),
    throwsA(isA<GitHubApiException>()),
  );
});

test('repoExists returns true for existing repo', () async {
  final mockHttp = http_testing.MockClient((_) async {
    return http.Response('{}', 200);
  });
  client = createClient(mockHttp);
  expect(await client.repoExists(owner: 'user', repo: 'notes'), true);
});

test('repoExists returns false for missing repo', () async {
  final mockHttp = http_testing.MockClient((_) async {
    return http.Response('', 404);
  });
  client = createClient(mockHttp);
  expect(await client.repoExists(owner: 'user', repo: 'missing'), false);
});
```

**Step 3: 테스트 실행**

Run: `cd /Users/bbaktaeho/github/simsync/desktop && flutter test test/storage/github/github_api_client_test.dart`

**Step 4: 커밋**

```bash
git add desktop/lib/storage/github/github_api_client.dart desktop/test/storage/github/github_api_client_test.dart
git commit -m "feat: add createRepo and repoExists to GitHubApiClient"
```

---

## Task 4: RepoSelectionScreen 구현

**Files:**
- Create: `desktop/lib/screens/repo_selection_screen.dart`

**Step 1: 화면 구현**

저장소 선택 화면. 세 영역으로 구성:
1. **캐시된 repo 리스트** (있을 때만) — 탭하면 바로 연결, 스와이프/X버튼으로 연동 해제
2. **새 저장소 만들기** — repo 이름 텍스트 입력 + "만들기" 버튼
3. **기존 저장소 연결** — `owner/repo` 텍스트 입력 + "연결" 버튼

콜백:
- `onRepoSelected(RepoEntry entry)` — 선택/생성 완료 시 호출
- `avatarUrl` — 우측 상단 프로필 이미지 표시용

에러 처리:
- repo 생성 실패 (이미 존재 등) → 에러 메시지 표시
- 기존 repo 연결 시 존재 여부 확인 → 없으면 에러 표시
- 로딩 상태 표시

기존 앱의 디자인 시스템(`AppColorsExtension`, `AppDimensions`, `GoogleFonts.manrope`) 사용.

**Step 2: 테스트 실행**

Run: `cd /Users/bbaktaeho/github/simsync/desktop && flutter test`

**Step 3: 커밋**

```bash
git add desktop/lib/screens/repo_selection_screen.dart
git commit -m "feat: implement RepoSelectionScreen UI"
```

---

## Task 5: _AppShell에 저장소 선택 상태 추가

**Files:**
- Modify: `desktop/lib/main.dart`

**Step 1: _AuthStatus에 `repoSelection` 상태 추가**

```dart
enum _AuthStatus {
  restoring,
  unauthenticated,
  repoSelection, // 추가
  authenticated,
}
```

**Step 2: _AppShellState 수정**

- `AuthSession? _session` 필드 추가 (repo 선택 화면에서 token, user 정보 필요)
- `_handleLogin`: signIn 후 `_session` 저장, `repoSelection` 상태로 전환
- `_restoreSession`: 세션 복원 성공 시 → `GitHubStorageConfig` 로드 → 있으면 바로 `authenticated`, 없으면 `repoSelection`
- `_handleRepoSelected(RepoEntry)`: config 저장, StorageBundle 생성, `authenticated`로 전환
- `build()`: `repoSelection` 상태일 때 `RepoSelectionScreen` 표시

**Step 3: DocumentScreen에 avatarUrl 전달**

`AuthSession.user.avatarUrl`을 DocumentScreen에 전달.

**Step 4: 테스트 실행**

Run: `cd /Users/bbaktaeho/github/simsync/desktop && flutter test`

**Step 5: 커밋**

```bash
git add desktop/lib/main.dart
git commit -m "feat: add repo selection state to app shell navigation"
```

---

## Task 6: DocumentScreen에 프로필 이미지 추가

**Files:**
- Modify: `desktop/lib/screens/document_screen.dart`

**Step 1: avatarUrl 파라미터 추가**

DocumentScreen 생성자에 `String? avatarUrl` 추가.

**Step 2: 우측 최상단에 프로필 이미지 표시**

에디터 패널 상단 (다크/라이트 토글, 로그아웃 버튼이 있는 영역) 우측 최상단에:
```dart
CircleAvatar(
  radius: 16,
  backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
  child: avatarUrl == null ? Icon(Icons.person, size: 16) : null,
)
```

**Step 3: 테스트 실행**

Run: `cd /Users/bbaktaeho/github/simsync/desktop && flutter test`

**Step 4: 커밋**

```bash
git add desktop/lib/screens/document_screen.dart
git commit -m "feat: display GitHub profile avatar in editor header"
```

---

## Task 7: 기존 GitHubStorageConfig를 RepoCache로 교체

**Files:**
- Modify: `desktop/lib/main.dart`
- Delete: `desktop/lib/storage/github/github_storage_config.dart` (RepoCache로 대체)

**Step 1: _defaultStorageFactory에서 GitHubStorageConfig 대신 선택된 RepoEntry 사용**

`_defaultStorageFactory`는 이제 `_handleRepoSelected`에서 이미 config가 확정된 상태로 호출되므로, `GitHubStorageConfig.load()` 로직을 제거하고 파라미터로 받는 방식으로 변경.

또는 `StorageFactory` typedef를 조정하여 `RepoEntry`를 포함하도록 변경.

**Step 2: 테스트 실행**

Run: `cd /Users/bbaktaeho/github/simsync/desktop && flutter test`

**Step 3: 커밋**

```bash
git add desktop/lib/main.dart
git rm desktop/lib/storage/github/github_storage_config.dart
git commit -m "refactor: replace GitHubStorageConfig with RepoCache"
```

---

## 구현 순서 요약

| Task | 내용 | 의존성 |
|------|------|--------|
| 1 | OAuth scope에 `repo` 추가 | 없음 |
| 2 | RepoCache 구현 | 없음 |
| 3 | GitHubApiClient에 repo 생성 추가 | 없음 |
| 4 | RepoSelectionScreen UI | Task 2, 3 |
| 5 | _AppShell 상태 흐름 수정 | Task 4 |
| 6 | DocumentScreen 프로필 이미지 | 없음 |
| 7 | GitHubStorageConfig → RepoCache 교체 | Task 2, 5 |

Task 1, 2, 3, 6은 독립적.
