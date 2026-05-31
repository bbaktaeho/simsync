---
title: Persistent GitHub Storage Cache
description: lastCommitSha + 트리/파일 SHA + 노트 markdown 을 디스크에 영속화. 변경 없으면 첫 화면 GitHub API 0회.
type: plan
created: 2026-05-02
status: active
---

# Persistent GitHub Storage Cache

## Problem

PR #21·#22 적용 후에도 **앱 재실행마다** 첫 로드 비용이 다시 발생한다 (`branches` 1 + `git/trees` 1 + `contents` × N). 이유: `GitHubNoteStorage` 의 `_shaCache` / `_noteCache` / `_treeMap` 그리고 `GitHubSyncEngine._lastCommitSha` 가 모두 in-memory only 라 프로세스 종료 시 사라짐.

## Insight (사용자 제안)

> "어디까지 동기화 받았다"를 기억하고 있으면 변경된 파일만 fetch → 두 번째부터는 빨라진다.

이미 그 절반은 구현되어 있다 (in-memory). 영속화만 추가하면 정상 동작 사이클에서 **첫 화면 GitHub API 호출 0회** 가 가능.

## Confirmed Decisions

| 항목 | 결정 |
|------|------|
| 영속화 대상 | `lastCommitSha`, path → `{sha, markdown}` 매핑 |
| `_noteCache` / `_idToPath` | 로드 시 markdown 에서 derived (parseNote) |
| `_treeMap` | 디스크 로드 시 `_shaCache` 와 동일 매핑으로 채움 → 트리 fetch 없이도 listAllNotes 가능 |
| 캐시 위치 | `path_provider.getApplicationSupportDirectory()` / `simsync_cache/<owner>__<repo>__<branch>.json` |
| 직렬화 | JSON. markdown 원문 그대로 저장 (Note 포맷 변경에 강함) |
| 쓰기 정책 | write-through with **1초 debounce** (연쇄 변경 시 합침) |
| 캐시 비활성화 | `cachePath: null` 로 생성하면 영속화 비활성. 기존 테스트 회귀 없음 |
| repo 분리 | owner/repo/branch 별 파일 분리. 다른 repo 로 전환해도 안전 |

## Expected Behavior After

| 시나리오 | API 호출 (Before this PR) | API 호출 (After) |
|------|------|------|
| 앱 재실행, 원격 변경 0 | `branches` 1 + `trees` 1 + `contents` N | `commits` 1 (sync polling). 화면은 디스크 캐시로 즉시 |
| 앱 재실행, 원격 노트 3개 변경 | `branches` 1 + `trees` 1 + `contents` N (전부 다시) | `commits` 1, `branches` 1, `trees` 1, `contents` 3 |
| 앱 사용 중, 다른 디바이스 1개 변경 | (지금도 OK) `commits` 1, `branches` 1, `trees` 1, `contents` 1 | 동일 |

## Files Affected

### 새 파일
- `desktop/lib/storage/github/github_note_cache.dart` (mobile mirror)
  - `class GitHubNoteCache { String? lastCommitSha; Map<String, _CacheEntry> files; load(); save(); }`
  - `_CacheEntry { String sha; String markdown; }`
  - JSON 직렬화 + atomic write (`writeAsString` 후 rename)

### 수정
- `desktop/lib/storage/github/github_note_storage.dart` (mobile mirror)
  - 생성자에 `GitHubNoteCache? cache` 파라미터
  - `loadCache()` async — 인스턴스 생성 직후 호출. `_shaCache` / `_treeMap` / `_noteCache` / `_idToPath` 채움
  - `lastCommitSha` getter / setter (cache 통해 영속)
  - 변경 발생 시 `_scheduleCacheSave()` (1초 debounce)
    - `_hydrateNotesFromTree` 의 새 fetch 후
    - `saveNote` / `deleteNote` 후
    - `setLastCommitSha` 후
- `desktop/lib/storage/github/github_sync_engine.dart` (mobile mirror)
  - 생성자에 `String? initialCommitSha` 파라미터 → `_lastCommitSha` 초기값
  - `String? get lastCommitSha` 노출 (외부에서 영속화용)
- `desktop/lib/main.dart` (mobile mirror): storage factory 변경
  - `path_provider.getApplicationSupportDirectory()` → cache 디렉토리
  - `GitHubNoteCache` 생성 + `await cache.load()`
  - `GitHubNoteStorage(..., cache: cache)`
  - `GitHubSyncEngine(initialCommitSha: storage.lastCommitSha, onRemoteChanged: ...)`
  - `onRemoteChanged` 콜백에서 `storage.setLastCommitSha(engine.lastCommitSha)` (영속화)

## Race / Consistency

- `_scheduleCacheSave` 는 다음 microtask 까지 변경을 모은 뒤 1초 debounce. 마지막 변경만 디스크에 도달.
- `setLastCommitSha` 후 `invalidateTreeCache()` 호출 (sync engine 콜백 패턴 그대로). 트리는 다음 listing 호출에서 재 fetch — 이때 `_shaCache` 가 살아있어 변경된 파일만 blob fetch.
- 앱 종료 시 미저장 캐시는 잃을 수 있다 (debounce 1초 안에 종료). 다음 실행 시 sync engine 의 commit SHA 비교가 회복: HEAD ≠ 디스크 lastCommitSha 면 정상 fetch 사이클.
- 두 인스턴스 동시 실행 (사용자가 두 데스크탑 창)? 하나의 cache 파일에 두 process 가 쓰면 race. **본 PR 범위 외** — 단일 인스턴스 가정.

## Test Strategy

`desktop/test/storage/github/github_note_storage_cache_test.dart` 신설:

1. **저장→로드 round-trip**: storage 인스턴스에서 listAllNotes 호출 → 캐시 파일 생김 → 새 인스턴스에서 cache 로드 → API 호출 0회로 listAllNotes 즉시 반환
2. **변경 감지 후 부분 fetch**: 새 인스턴스에서 listAllNotes (캐시 hit), 그 후 invalidateTreeCache + 트리에 한 파일 sha 변경 → blob fetch 1회만
3. **lastCommitSha 영속화**: storage.setLastCommitSha → 디스크에 반영 → 새 인스턴스 lastCommitSha 동일
4. **cache: null** (캐시 비활성): 기존 트리/blob 동작 그대로 (회귀 검증)

기존 테스트는 `cache: null` 또는 default null 이라 회귀 없음.

## Out of Scope

- 두 process 동시 실행 시 file lock
- 캐시 무결성 체크섬
- 캐시 크기 제한 / 오래된 노트 evict
- Compare API 도입 (현 SHA-cache 비교로 충분)
- mobile 캐시 디렉토리 권한 / iOS sandbox 차이 (path_provider 가 처리)

## Checklist

- [ ] `GitHubNoteCache` 클래스 + JSON 스키마 (desktop+mobile)
- [ ] `GitHubNoteStorage` 에 cache 통합
- [ ] `GitHubSyncEngine` initialCommitSha + lastCommitSha getter
- [ ] main.dart factory wire-up (path_provider, await load, sync engine)
- [ ] 신규 테스트 4 케이스
- [ ] desktop/mobile `flutter analyze` clean
- [ ] desktop/mobile `flutter test` 회귀 없음
- [ ] PR 작성 + push
