---
title: Memo Tab Restore (Desktop)
description: 데스크톱 사이드바 노트 리스트에 daily | memo 탭 복원. memo 탭은 날짜 무관 전체 메모를 updatedAt desc로 표시.
type: plan
created: 2026-05-02
status: active
related:
  - .agent/plan/005-2026-05-02-persistent-github-cache/plan.md
---

# Memo Tab Restore (Desktop)

## Problem

예전 `feat/memo-and-storage-refactor` 브랜치(commit `61cff5e`, 2026-03-19)에서 구현되었으나 develop/main 에 머지되지 않은 채 사라진 **메모 탭**을 복원한다.

- 사용자 기대: 좌측 사이드바 노트 리스트에서 `daily | memo` 두 탭으로 전환할 수 있고, memo 탭은 날짜와 무관하게 전체 메모를 `updatedAt desc`로 보여준다.
- 우클릭 컨텍스트 메뉴에서 노트를 daily ↔ memo 로 이동할 수 있다.
- 데이터는 frontmatter `is_memo: bool` 필드로 영속화한다 (없으면 false).

원본 `61cff5e` 커밋의 메모 부분만 채택한다. 같은 커밋에 묶여 있던 "local-first git clone storage" 리팩토링은 현재 아키텍처(Contents API 기반 + persistent cache)와 안 맞으므로 가져오지 않는다.

## Confirmed Decisions

| 항목 | 결정 |
|------|------|
| 모델 | `Note.isMemo: bool` 필드 추가, default `false`. `copyWith` 에 포함 |
| Frontmatter | `is_memo: true/false` 한 줄 추가. 없으면 `false`로 파싱 (기존 노트 무영향) |
| 위치 | `NoteListSection` 헤더와 리스트 사이의 탭 바 (원안 동일) |
| 탭 동작 | `daily` 활성: 기존 동작 그대로. `memo` 활성: `_allNotes` 전체에서 `isMemo == true` 만, `updatedAt` desc로 정렬 |
| 컨텍스트 메뉴 | 우클릭 시 `메모로 이동` (daily 탭) 또는 `daily로 이동` (memo 탭) + 기존 `삭제` |
| 이동 동작 | `note.copyWith(isMemo: !current, updatedAt: now)` → `saveNote` → `_allNotes` 갱신. 별도 파일 이동/리네임 없음 (원래 노트 경로 유지) |
| 검색 | search index는 daily/memo 구분 없이 전체 노트 대상. 검색 결과 패널은 isMemo와 관계없이 표시 |
| Tag/날짜 필터 | 기존 그대로 — memo도 일반 노트와 동일하게 tags/noteDate 보존 |
| 새 노트 생성 | 기존 동작 유지: 새 노트는 항상 `isMemo: false` (daily). memo 노트는 "이동" 액션으로만 생성 |
| Local 노트 | 메모 가능. `LocalNoteStorage` 는 `GitHubNoteStorage.serializeNote/parseNote` 를 재사용하므로 자동 처리 |
| Pagination | memo 탭에서도 동일 페이지네이션 적용. 탭 전환 시 `_currentPage = 0` 리셋 |
| Empty state | memo 탭 + 노트 없음: "No memos yet" |
| 모바일 | UI 변경 없음. **데이터만 round-trip 안전**하게 유지 (parse/serialize 에 `is_memo` 추가). UI 추가는 별도 PR 로 분리 |
| `NoteService` (`~/.simsync/documents`) | 사용처 확인 결과 `desktop/lib/main.dart` 의 mobile-only 경로에서는 안 쓰이고, desktop 에서는 widget tree 에 주입되지만 실제 read/write 호출이 거의 없음. 일단 frontmatter `is_memo` 만 read/write 에 추가. 깊은 리팩토링 없음 |

## Files Affected

### 수정
- `desktop/lib/models/note.dart`
  - `final bool isMemo;` 필드 추가 (default false)
  - 생성자 named param `this.isMemo = false`
  - `copyWith` 에 `bool? isMemo` 추가
- `desktop/lib/storage/github/github_note_storage.dart`
  - `serializeNote`: `is_memo: ${note.isMemo}` 줄 추가
  - `parseNote`: `final isMemo = yaml['is_memo'] == true;` 추가, `Note(...)` 생성 시 전달
- `desktop/lib/storage/local/local_note_storage.dart`
  - `LocalNoteStorage.listNotes` 가 만드는 local copy `Note(...)` 에 `isMemo: note.isMemo` 전달 (parser 가 이미 채우므로 그대로 전달만)
- `desktop/lib/services/note_service.dart`
  - `_serializeNote`: `is_memo` 라인 추가
  - `_parseNoteFile`: `isMemo: fm['is_memo'] == true` 추가
- `desktop/lib/widgets/note_list_section.dart`
  - 새 props: `bool memoTabActive`, `ValueChanged<bool> onMemoTabChanged`, `Future<void> Function(Note)? onMoveToMemo`, `Future<void> Function(Note)? onMoveToDailyNote`
  - `_buildTabBar` (헤더 직후, divider 위): `daily | memo` 텍스트 탭 + active underline
  - `_buildEmptyState`: memo 탭일 때 카피 분기 ("No memos yet" / "메모로 이동해 시작하세요")
  - `_NoteListItem._showContextMenu`: `note.isMemo` 와 콜백 유무에 따라 "메모로 이동" / "daily로 이동" entry 추가
- `desktop/lib/screens/document_screen.dart`
  - state: `bool _memoTabActive = false;`
  - getter: `_memoNotes` (`_allNotes.where(isMemo).toList()..sort(updatedAt desc)`)
  - `_visibleNotes` 분기: `_memoTabActive` 면 `_memoNotes` 반환 (날짜/검색 필터 우선순위 유지: 검색 활성 시 검색 결과 그대로)
  - 핸들러:
    - `_onMemoTabChanged(bool memo)`: setState + `_currentPage = 0` + `_selectedNote` 첫 노트로 갱신
    - `_onMoveToMemo(Note)` / `_onMoveToDailyNote(Note)`: `_canMutateNote` 체크 → `copyWith` → `saveNote` → `_allNotes` 갱신 + search index upsert
  - `NoteListSection(...)` 호출에 새 props 전달
  - 검색 활성 시에는 탭 바 영역의 의미가 약하므로 **검색 활성 동안에도 탭은 보여주되, 탭 전환 시 검색을 클리어**(같은 자리에 있는 컨트롤은 서로 배타적으로 동작) — 단순함 우선
- `mobile/lib/models/note.dart`: 동일하게 `isMemo` 필드 추가
- `mobile/lib/storage/github/github_note_storage.dart`: serialize/parse 에 `is_memo` 추가 (UI 변경 없음, round-trip 안전 목적)
- `mobile/lib/storage/local/local_note_storage.dart`: parser 결과 그대로 전달 (변경 미미할 수도 있음)

### 새 파일
- 없음 (모두 기존 파일 수정)

### 테스트
- `desktop/test/storage/note_storage_test.dart` 또는 동등 위치
  - `serializeNote → parseNote` round-trip 시 `isMemo == true` 보존
  - `is_memo` 누락된 markdown 입력 시 `parseNote` 가 `isMemo == false` 로 채움
- `desktop/test/screens/document_screen_test.dart`
  - 메모 탭 전환 시 `_visibleNotes` 가 `isMemo == true` 만 포함
  - daily 탭에서는 `isMemo == true` 노트가 보이지 않음
  - "메모로 이동" 후 같은 노트가 memo 탭에서 보이고, 원본 daily 탭에서는 사라짐
- `mobile/test/...` round-trip 1건만 추가 (UI 미변경이므로 위젯 테스트는 생략)

## Behavior

### Daily 탭 (기존 + 필터)
- `_visibleNotes` = (`_isSearchActive` 면 search results, else `_notesForSelectedDate`) 에서 `isMemo == false` 만
- 빈 상태 카피 그대로

### Memo 탭 (신규)
- `_visibleNotes` = `_allNotes.where(isMemo == true).sort(updatedAt desc)` (검색 비활성 시)
- 검색 활성 + memo 탭: search results 중 `isMemo == true` 만 — 단, 사용자가 의도적으로 탭을 누른 거면 검색을 풀고 메모 전체 보여주는 게 더 자연스러움 → **탭 전환 시 검색 클리어**로 단순화
- 캘린더 셀의 dot 표시는 daily 노트 기준으로 유지 (memo 는 날짜 indicator 에 영향 없음)

### 이동 액션
- daily 탭 우클릭 → "메모로 이동": `note.copyWith(isMemo: true, updatedAt: now)` → `saveNote`
- memo 탭 우클릭 → "daily로 이동": `note.copyWith(isMemo: false, updatedAt: now)` → `saveNote`
- 동기화 비활성 + sync 노트: `_canMutateNote` false → snackbar 노출 (`'동기화가 꺼져 있어 ...'` 기존 패턴 재사용)

## Out of Scope

- 모바일 메모 탭 UI (별도 PR)
- 메모를 별도 디렉토리(`memos/`)에 저장하는 파일 경로 변경 — 현재는 `notes/{YYYY-MM}/{DD}/` 그대로 두고 frontmatter flag 만으로 구분
- 메모 ↔ daily 이동 시 `noteDate` 변경 (그대로 유지)
- 키보드 단축키 (Cmd+1/2 같은 탭 토글) — 별도 작업
- 마이그레이션 스크립트 — `is_memo` 누락은 false 로 기본값 처리되므로 불필요

## Branch / Workflow

- Base: `develop` (latest, includes PR #21 = persistent cache 머지 후 시점)
- Branch: `feature/memo-tab-restore`
- 005 (`perf/persistent-github-cache`) 가 develop 에 아직 머지 전이면 `is_memo` frontmatter 추가가 `parseNote` 영역에서 작은 conflict 가능 — manual 해결
- 14단계 워크플로우 적용. 단일 PR

## Test Strategy

1. **단위 round-trip**: `GitHubNoteStorage.serializeNote(noteWithMemo)` → `parseNote` → `isMemo == true`
2. **하위 호환**: `is_memo` 없는 markdown → `parseNote` 시 `isMemo == false`
3. **document_screen 위젯 테스트**:
   - 초기 렌더에 daily 탭 active, memo 노트 hidden
   - memo 탭 전환 → memo 만 표시, updatedAt desc
   - "메모로 이동" tap → daily 탭에서 사라지고 memo 탭에서 나타남
4. **regress**: 기존 search/pagination/delete 테스트 회귀 없음
5. `flutter analyze` clean (desktop + mobile)
6. `flutter test` 통과 (desktop + mobile)

## Checklist

- [ ] `Note` 모델에 `isMemo` 필드 (desktop + mobile)
- [ ] `serializeNote` / `parseNote` 에 `is_memo` (desktop github storage + service + mobile github storage)
- [ ] `local_note_storage` 에 `isMemo` 전달 보장 (desktop + mobile)
- [ ] `NoteListSection` 탭 바 + 컨텍스트 메뉴 entry
- [ ] `DocumentScreen` 메모 탭 state + 필터 + 이동 핸들러
- [ ] `note_service.dart` frontmatter 동기화
- [ ] 신규 unit + widget 테스트
- [ ] desktop/mobile `flutter analyze` clean
- [ ] desktop/mobile `flutter test` 회귀 없음
- [ ] 개발 일지 `.agent/develop/daily/2026-05-02-memo-tab-restore.md` 작성
- [ ] PR 작성 (develop 대상)
