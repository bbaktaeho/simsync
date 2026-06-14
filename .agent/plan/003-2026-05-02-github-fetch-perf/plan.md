---
title: GitHub Fetch Performance Optimization
description: 첫 로드/검색 인덱싱 시 GitHub API N+1 호출 패턴을 트리 캐시 + 병렬 fetch로 개선
type: plan
created: 2026-05-02
status: active
related:
  - .agent/plan/003-2026-05-02-github-fetch-perf/01-current-cost.md
---

# GitHub Fetch Performance Optimization

## Problem

로그인 후 GitHub 레포에서 노트를 처음 불러올 때 매우 느림. 사용자 보고: "매우 느려".

원인: Contents API의 N+1 호출 패턴 + 직렬 호출.

상세: [01-current-cost.md](01-current-cost.md)

## Confirmed Decisions

| 항목 | 결정 |
|------|------|
| 접근 방식 | **Git Trees API (recursive)** + **콘텐츠 fetch 병렬화** |
| Tarball download | 미채택 (압축해제/메모리 비용 + 큰 코드 변경 vs 추가 이득 작음) |
| GraphQL | 미채택 (학습 곡선/유지보수 비용) |
| Persistent cache | 별도 작업 (이번 범위 외) |
| 병렬 동시성 제한 | 10 (GitHub secondary rate limit 보호) |
| Tree truncation | recursive=true 응답이 truncated이면 legacy listing logic으로 fallback |
| 캐시 무효화 | sync engine이 commit SHA 변경 감지 시 `storage.invalidateTreeCache()` 호출 |

## Why Trees API + 병렬

**현재 비용** (한 달 30일, 노트 30개 가정):
- `listDates(currentMonth)` 1회 → 디렉토리 listing
- 각 day마다 `listNotes` → 디렉토리 listing (D회)
- 각 file마다 `getFile` → 콘텐츠 fetch (N회)
- 모두 직렬: D + N = 60회 × 100~300ms latency = **6~18초**

**개선 후**:
- `branches/{branch}` → tree sha (1회)
- `git/trees/{tree_sha}?recursive=1` → 모든 path/sha (1회)
- listDates / listNotes 는 트리 캐시에서 동기 추출 (0 RTT)
- 미캐시 콘텐츠는 `Future.wait` 으로 병렬 fetch (HTTP/2 multiplex 또는 chunk-10 직렬)
- 총: 2 + ceil(N / 10) RTT × 100~300ms = **~1초**

GitHub Trees API는 한 호출에 모든 path/sha를 반환하므로 listing 단계의 모든 N+1을 1회로 압축한다. 콘텐츠 fetch는 여전히 파일별이지만 병렬화로 latency 누적 제거.

## Files Affected

### desktop
- `lib/storage/github/github_api_client.dart` — `listRepoTree`, `GitHubTreeEntry` 추가
- `lib/storage/github/github_note_storage.dart` — 트리 캐시, `_ensureTree`, `invalidateTreeCache`. listDates / listNotes / listAllNotes 가 트리 캐시 사용. 콘텐츠 fetch는 병렬 (chunked).
- `lib/storage/github/github_sync_engine.dart` — commit SHA 변경 감지 시 `onTreeStale` 콜백 (또는 storage.invalidateTreeCache 직접 호출).
- `lib/main.dart` (또는 storage factory) — sync engine이 invalidate 콜백을 호출하도록 연결.

### mobile
- desktop과 동일 변경을 mirror.

## API Surface

```dart
// github_api_client.dart 추가
class GitHubTreeEntry {
  final String path;   // e.g. 'notes/2026-05/02/My Note.md'
  final String sha;    // blob sha
  final String type;   // 'blob' or 'tree'
  final int? size;
}

class GitHubTreeResult {
  final List<GitHubTreeEntry> entries;
  final bool truncated;
}

class GitHubApiClient {
  /// 1) /repos/{owner}/{repo}/branches/{branch} → tree sha
  /// 2) /git/trees/{tree_sha}?recursive=1 → flat listing
  Future<GitHubTreeResult> listRepoTree({required String branch});
}

// github_note_storage.dart 추가
class GitHubNoteStorage {
  String? _cachedTreeSha;             // tree sha (commit-derived)
  Map<String, String>? _treeMap;      // path → blob sha (only notes/*.md)
  bool _treeTruncated = false;

  /// Sync engine이 새 commit 감지 시 호출. 다음 listing 호출이 트리 재 fetch.
  void invalidateTreeCache() {
    _cachedTreeSha = null;
    _treeMap = null;
    _treeTruncated = false;
  }

  Future<Map<String, String>?> _ensureTree(String branch) async {
    if (_treeMap != null) return _treeMap;
    final result = await _client.listRepoTree(branch: branch);
    _treeTruncated = result.truncated;
    if (result.truncated) {
      // Big repo: skip tree path entirely; legacy listing falls back automatically.
      return null;
    }
    final map = <String, String>{};
    for (final e in result.entries) {
      if (e.type == 'blob' &&
          e.path.startsWith('notes/') &&
          e.path.endsWith('.md')) {
        map[e.path] = e.sha;
      }
    }
    _treeMap = map;
    return map;
  }
}
```

## Concurrency Helper

```dart
Future<List<R>> _mapWithConcurrency<T, R>(
  Iterable<T> items,
  Future<R> Function(T) fn, {
  int concurrency = 10,
}) async {
  final list = items.toList();
  final results = List<R?>.filled(list.length, null);
  var index = 0;
  Future<void> worker() async {
    while (true) {
      final i = index++;
      if (i >= list.length) return;
      results[i] = await fn(list[i]);
    }
  }
  await Future.wait(List.generate(concurrency, (_) => worker()));
  return results.cast<R>();
}
```

## Branch Awareness

`GitHubNoteStorage` 는 현재 branch를 알지 못하므로 생성자에서 받도록 변경:

```dart
GitHubNoteStorage(this._client, {String branch = 'main'}) : _branch = branch;
```

기존 호출처 (storage factory)에서 branch 전달.

## Sync Engine 통합

`GitHubSyncEngine` 가 commit SHA 변경 감지 시 storage 의 `invalidateTreeCache()` 를 먼저 호출하고, 기존 `onRemoteChanged` 콜백을 호출. 이렇게 하면 다음 listing 호출이 새 트리를 fetch.

연결 방식: 두 가지 옵션

A. storage 인스턴스를 sync engine에 주입 (storage 의 invalidate를 sync 가 직접 호출)
B. sync engine 의 `onRemoteChanged` 콜백 안에서 storage.invalidateTreeCache() 호출 (storage factory 가 wire-up)

→ **B 선호** (의존 방향 단방향 유지, sync engine이 storage 모름).

## Fallback / Backward Compatibility

1. tree response 가 truncated → `_treeMap = null` → listDates / listNotes / listAllNotes 가 legacy logic 자동 사용.
2. Trees API 자체가 실패 (네트워크 오류, 권한) → catch 후 legacy logic 자동 사용.
3. 기존 `_shaCache` / `_noteCache` / `_idToPath` 는 그대로 유지. 트리 캐시는 추가 레이어.

## Test Strategy

### 단위 테스트 (`github_note_storage_test.dart` 보강)

1. **트리 호출 횟수 검증**: `listAllNotes` / `listNotes` 호출 시 `branches/{branch}` + `git/trees/{sha}` 합 2회만 호출되고, 디렉토리 listing 추가 호출은 발생하지 않음.
2. **콘텐츠 병렬 fetch 검증**: 미캐시 .md 파일 N개에 대해 N개의 GET 호출 발생. (concurrency 제한은 직접 측정 어려우니 단순히 모든 파일 fetch 됐는지 검증.)
3. **캐시 사용 검증**: 두 번째 listing 호출에서 sha 동일이면 콘텐츠 GET 미발생.
4. **무효화 검증**: `invalidateTreeCache` 호출 후 트리 재 fetch.
5. **truncated fallback**: tree response 가 truncated 인 경우 legacy listing logic 사용.
6. **API 실패 fallback**: trees endpoint 503 → legacy listing.

### 회귀 테스트
- 기존 desktop/mobile 모든 테스트 통과.

## Out of Scope

- Persistent disk cache (앱 재시작 후 즉시 표시)
- Tarball download
- GraphQL API
- Tree pagination (초대규모 레포 대응)
- 변경된 파일만 fetch (incremental sync) — 트리 캐시가 commit SHA에 묶여 자연히 처리되지만, "diff 기반 minimal fetch" 는 별도

## Checklist

- [ ] `GitHubApiClient.listRepoTree` 추가 (desktop + mobile)
- [ ] `GitHubTreeEntry`, `GitHubTreeResult` 모델 추가
- [ ] `GitHubNoteStorage` 트리 캐시 + `_ensureTree` + `invalidateTreeCache`
- [ ] listDates / listNotes / listAllNotes 가 트리 캐시 사용 + 콘텐츠 병렬 fetch
- [ ] storage factory 가 sync engine ↔ storage 무효화 wire-up
- [ ] 단위 테스트 (호출 횟수, 캐시, 무효화, fallback)
- [ ] desktop / mobile `flutter analyze` clean
- [ ] desktop / mobile `flutter test` 회귀 없음
- [ ] PR 작성 + push
