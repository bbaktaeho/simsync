---
title: 메모 노트 기능 및 로컬 우선 스토리지 아키텍처
date: 2026-03-19
branch: feat/memo-and-storage-refactor
---

# 메모 노트 기능 및 로컬 우선 스토리지 아키텍처

## 목적

1. 날짜에 독립적인 메모 노트 기능을 데스크탑/모바일 양쪽에 추가한다.
2. GitHub API 직접 읽기(N+1 문제)를 로컬 파일시스템 읽기로 전환하여 성능과 안정성을 개선한다.
3. 앱 시작 시 블로킹되던 clone/mirror 작업을 백그라운드로 전환하여 시작 성능을 개선한다.

## 주요 변경

### 메모 노트 (Phase 1)

- `Note` 모델에 `isMemo` 필드 추가 (기본값 `false`). YAML frontmatter에 `is_memo: true`로 직렬화.
- `NoteStorage` 인터페이스에 `listMemoNotes()` 추가.
- 데스크탑: `NoteListSection`에 daily/memo 탭 바 추가. 우클릭 컨텍스트 메뉴로 "메모로 이동" / "daily로 이동" 지원.
- 모바일: `CalendarScreen`에 daily/memo 탭 추가. 롱프레스 컨텍스트 메뉴와 `EditorScreen` AppBar 팝업 메뉴로 메모 전환 지원.
- 메모로 이동 시 즉시 메모 탭 목록에 반영되도록 `_loadMemoNotes()` 호출 추가.
- 캘린더 날짜 dot 표시에서 메모 노트를 제외하는 필터 추가.

### 로컬 우선 스토리지 아키텍처 (Storage Refactor)

**데스크탑:**
- `GitService` 신규 생성: git binary wrapper (clone, pull, add, commit, push). `GIT_CONFIG` extraheader 방식으로 토큰 인증 (URL에 토큰 미포함).
- `GitRepoNoteStorage` 신규 생성: 로컬 git clone 디렉토리(`~/.simsync/git/{owner}/{repo}/notes/`)에서 파일을 읽고, 쓰기는 로컬 파일 저장 후 git add + commit (awaited) + push (unawaited/fire-and-forget).
- git clone이 완료되지 않은 경우 GitHub API fallback.
- `GitHubSyncEngine`에 `gitService` 옵션 파라미터 추가, sync 시 `git pull` 실행.

**모바일:**
- `GitMirrorService` 신규 생성: GitHub Trees API + Contents API 기반 파일 미러링. SHA 추적으로 변경분만 incremental 다운로드.
- `MirrorNoteStorage` 신규 생성: 로컬 미러 디렉토리에서 파일을 읽고, 쓰기는 API PUT + 로컬 파일 업데이트.
- `GitHubSyncEngine`에 `mirrorService` 옵션 파라미터 추가, sync 시 `mirrorService.pull()` 실행.

### 시작 성능 개선

- 데스크탑: `gitService.cloneIfNeeded()`를 `unawaited`로 백그라운드 실행.
- 모바일: `mirrorService.resolvePath()`만 await하고 `mirrorIfNeeded()`는 `unawaited`로 백그라운드 실행.

### 보안

- `git_service.dart`의 모든 catch(e) 블록에서 `_sanitize(e.toString())`으로 토큰 마스킹.
- `_sanitize()` 메서드가 result.stderr뿐 아니라 exception 메시지에서도 토큰을 제거.

## 신규 파일

| 파일 | 설명 |
|------|------|
| `desktop/lib/storage/github/git_service.dart` | Git binary wrapper |
| `desktop/lib/storage/github/git_repo_note_storage.dart` | 로컬 git repo 기반 NoteStorage |
| `mobile/lib/storage/github/git_mirror_service.dart` | API 기반 파일 미러링 서비스 |
| `mobile/lib/storage/github/mirror_note_storage.dart` | 로컬 미러 기반 NoteStorage |

## 테스트

- `desktop/`: `flutter test` - 85개 통과
- `mobile/`: `flutter test` - 6개 통과
- `mobile/`: `flutter analyze` - 이슈 없음
- `desktop/`: `flutter build macos --release` - 50.0MB 빌드 성공

## 발견된 이슈 및 해결

| 이슈 | 원인 | 해결 |
|------|------|------|
| 메모 이동 후 즉시 안 보임 | `_moveToMemo()` 후 `_loadMemoNotes()` 미호출 | 메모 탭 활성 시 `_loadMemoNotes()` 호출 추가 |
| 캘린더에 메모 전용 날짜 dot 표시 | `_datesWithNotes`가 메모 포함 | `.where((n) => !n.isMemo)` 필터 추가 |
| 메모 삭제 후 목록 잔존 | `_deleteNote`에서 `_memoNotes` 미제거 | `_memoNotes.removeWhere` 추가 |
| git clone URL에 토큰 노출 | URL에 토큰 임베딩 | GIT_CONFIG extraheader 방식 전환 |
| catch 블록 토큰 누출 | `$e`가 raw 출력 | `_sanitize(e.toString())` 적용 |
| 시작 시 로딩 오래 걸림 | clone/mirror가 UI 블로킹 | `unawaited` 백그라운드 실행 |
| N+1 API 호출 (150개 노트에 184회) | 노트마다 API 호출 | 로컬 파일시스템 읽기로 전환 |
| sync 후 캐시 stale | 캐시 무효화 누락 | `clearCache()` + refresh handler 연결 |
