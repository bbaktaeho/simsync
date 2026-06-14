---
title: Mobile Memo Tab
description: 모바일 캘린더 화면(노트 탭)에 daily | memo 탭 스트립 추가. memo 탭은 날짜 무관 전체 메모를 updatedAt desc로 표시. 데스크톱 메모 기능의 모바일 대응.
type: plan
created: 2026-05-31
status: active
related:
  - .agent/plan/006-2026-05-02-memo-tab-restore/plan.md
---

# Mobile Memo Tab Implementation Plan

> **Goal:** 모바일에서도 데스크톱처럼 `daily | memo` 탭으로 전환할 수 있고, memo 탭은 날짜와 무관하게 전체 메모를 보여준다.
>
> **Architecture:** `CalendarScreen`(하단 네비 "노트")에 탭 상태(`_memoTabActive`)를 추가하고, memo 활성 시 캘린더/날짜 UI를 숨기고 `listAllNotes()`로 모은 메모 목록을 보여준다. 모델/저장소는 변경 없음(이미 `isMemo` + `is_memo` 영속화 + `listAllNotes()` 존재).
>
> **Tech Stack:** Flutter (Dart), 기존 `NoteStorage` 추상화, `flutter_test` 위젯 테스트.

---

## Problem

006(`feature/memo-tab-restore`)에서 데스크톱 메모 탭을 복원하면서 **모바일 메모 UI는 의도적으로 별도 PR로 분리**했다(006 plan Out of Scope: "모바일 메모 탭 UI (별도 PR)"). 당시 모바일은 데이터(`is_memo`)만 round-trip 안전하게 유지했다.

이번 작업은 그 후속으로, 모바일 `CalendarScreen`에 `daily | memo` 탭을 추가해 데스크톱과 동등한 메모 경험을 제공한다.

- 사용자 기대: 노트 탭 안에서 `daily | memo` 전환. memo 탭은 날짜 무관 전체 메모를 `updatedAt desc`로 표시.
- 노트를 **롱프레스 → 하단 시트**로 daily ↔ memo 이동 (모바일엔 우클릭이 없음).
- 모델/저장소 변경 없음.

## Confirmed Decisions

| 항목 | 결정 |
|------|------|
| 위치 | `CalendarScreen` body 최상단 `daily \| memo` 탭 스트립 (AppBar 아래). 기본 `daily` |
| memo 탭 데이터 | `storage.listAllNotes()` (+ `localStorage?.listAllNotes()`) → `where(isMemo)` → `updatedAt` desc. 데스크톱 `_memoNotes` 로직과 동일 |
| 로딩 시점 | memo 탭 최초 활성 시 lazy 로드. 이동 후/`refreshSignal` 시 활성 탭 기준 재로드 |
| daily 리스트 정합성 | `_loadNotes`가 만드는 날짜별 리스트에서 `where(!isMemo)` 제외 필터 추가 (메모는 noteDate 폴더에 남아 `listNotes(date)`에 포함되므로). 데스크톱 `_notesForSelectedDate`의 `if (n.isMemo) return false`와 동일 이유 |
| 이동 UI | 노트 카드 롱프레스 → `showModalBottomSheet`. `!isMemo` → "메모로 이동", `isMemo` → "daily로 이동" |
| 이동 동작 | `note.copyWith(isMemo: 대상, updatedAt: now)` → `_storageFor(note).saveNote(updated)`. `noteDate`/`isDefault` 변경 없음 (데스크톱과 동일). 별도 파일 이동/리네임 없음 |
| AppBar (memo 활성) | 월 네비(이전/오늘/다음) 숨김, 타이틀 "메모". avatar·sync 인디케이터 유지 |
| memo 빈 상태 | "메모가 없습니다" + 힌트 "노트를 길게 눌러 메모로 옮기세요" |
| 메모 생성 | 직접 생성 버튼 없음. 이동으로만 생성 (데스크톱과 동일). memo 탭에는 "새 노트" 버튼 미표시 |
| 삭제 | 기존 왼쪽 스와이프 유지. 하단 시트엔 이동 액션만 (MVP 범위) |
| 모델/저장소 | 변경 없음 (`Note.isMemo`, `copyWith(isMemo:)`, `is_memo` 영속화, `listAllNotes()` 모두 기구현) |

## Files Affected

### 수정
- `mobile/lib/screens/calendar_screen.dart` (유일한 소스 변경)
  - state 추가: `bool _memoTabActive = false;`, `List<Note> _memoNotes = [];`, `bool _memoLoaded = false;`
  - `_loadNotes()`: `notes` 구성 후 `notes.removeWhere((n) => n.isMemo)` 추가 (daily 리스트에서 메모 제외)
  - 신규 `_loadMemoNotes()`: `listAllNotes()` (+local) → `where(isMemo)` → `sort(updatedAt desc)` → setState
  - 신규 `_onMemoTabChanged(bool memo)`: setState; `memo && !_memoLoaded`면 `_loadMemoNotes()`
  - 신규 `_setMemoFlag(Note note, bool isMemo)`: copyWith → saveNote → `_loadNotes()` + (memo 로드됐으면) `_loadMemoNotes()`
  - 신규 `_showNoteActions(Note note)`: `showModalBottomSheet`로 이동 액션 시트
  - `_onRefresh()`: 기존 + `if (_memoTabActive) _loadMemoNotes()`
  - `build()`: body 최상단에 `_buildTabBar(c)`; `_memoTabActive`면 캘린더/날짜헤더 대신 `_buildMemoList(c)`
  - `_buildAppBar()`: `_memoTabActive`면 월 네비 actions 숨기고 타이틀 "메모"
  - 신규 `_buildTabBar(c)`, `_buildMemoList(c)` (메모 빈 상태 포함, 카드 렌더는 기존 `_buildNoteCard` 재사용)
  - `_buildNoteCard(c, note)`의 `GestureDetector`에 `onLongPress: () => _showNoteActions(note)` 추가

### 새 파일
- `mobile/test/screens/calendar_screen_memo_tab_test.dart` (위젯 테스트)

### 변경 없음 (확인됨)
- `mobile/lib/models/note.dart` — `isMemo` + `copyWith(isMemo:)` 존재
- `mobile/lib/storage/**` — `is_memo` 영속화 + `listAllNotes()` 존재
- `mobile/lib/services/note_service.dart` — `is_memo` read/write 존재

## Behavior

### Daily 탭 (기존 + 필터)
- 레이아웃: 캘린더 + 날짜 헤더 + "새 노트" + 날짜별 노트 리스트 (기존 그대로).
- `_loadNotes`가 `listNotes(_selectedDate)` 결과에서 `isMemo == true`를 제외.

### Memo 탭 (신규)
- 레이아웃: 탭 스트립 + 전체 메모 평면 리스트. 캘린더/날짜헤더/"새 노트" 숨김.
- 데이터: `listAllNotes()`(synced) + `localStorage?.listAllNotes()` 합쳐 `isMemo == true`만, `updatedAt` desc.
- AppBar: 타이틀 "메모", 월 네비 숨김.

### 이동 (롱프레스 → 하단 시트)
- daily 노트 롱프레스 → "메모로 이동": `copyWith(isMemo: true, updatedAt: now)` → `saveNote` → daily 리스트에서 사라지고 memo 리스트에 등장.
- 메모 롱프레스 → "daily로 이동": `copyWith(isMemo: false, updatedAt: now)` → `saveNote` → 원래 `noteDate`의 daily 리스트로 복귀.

## Test Strategy (코드 기반, 에뮬레이터 미사용)

`mobile/test/screens/calendar_screen_memo_tab_test.dart`에 자체 `_FakeStorage`(NoteStorage 구현, `mobile_bug_regressions_test.dart`의 InMemoryNoteStorage 패턴) 사용. `setUpAll`에서 `initializeDateFormatting('ko')`.

테스트 케이스:
1. **탭 렌더/기본값**: `daily`, `memo` 텍스트 존재. 기본은 daily(캘린더 보임).
2. **memo 탭 = 날짜 무관**: 서로 다른 `noteDate`의 메모 2개를 두고 memo 탭 진입 → 둘 다 보임. 같은 날짜의 비메모 노트는 안 보임.
3. **daily 탭 = 메모 제외**: 선택 날짜에 비메모 1 + 메모 1 → daily 탭엔 비메모만.
4. **이동(메모로)**: daily 노트 롱프레스 → "메모로 이동" 탭 → 저장소 노트의 `isMemo == true`, memo 탭에 등장.
5. **이동(daily로)**: 메모 롱프레스 → "daily로 이동" → `isMemo == false`.
6. **빈 상태**: 메모 0개 + memo 탭 → "메모가 없습니다" 노출.

추가 검증:
- `cd mobile && flutter analyze` clean
- `cd mobile && flutter test` 전체 통과 (기존 테스트 회귀 없음)
- desktop은 변경 없음 — 회귀 확인용으로 `cd desktop && flutter test` 1회 실행

## TDD 순서 (bite-sized)

1. 테스트 파일 + `_FakeStorage`/`_note` 헬퍼 작성, 케이스 1~3 작성 → 실패 확인(탭 미존재).
2. state + `_buildTabBar` + `_onMemoTabChanged` + build 분기 + `_loadMemoNotes` + daily 필터 구현 → 1~3 통과.
3. 케이스 6(빈 상태) 작성 → 실패 → `_buildMemoList` 빈 상태 구현 → 통과.
4. 케이스 4~5(이동) 작성 → 실패 → `_showNoteActions` + `_setMemoFlag` + `onLongPress` 구현 → 통과.
5. AppBar 분기(memo 타이틀/월네비 숨김) 구현.
6. `flutter analyze` + `flutter test` (mobile), desktop `flutter test` 회귀 확인.
7. 커밋.

## Out of Scope

- 메모 전용 디렉토리 저장(파일 경로 변경) — frontmatter flag만으로 구분 (006과 동일).
- 메모 ↔ daily 이동 시 `noteDate`/`isDefault` 변경.
- memo 탭 직접 "새 메모" 생성 버튼.
- 하단 시트 내 삭제/태그 등 추가 액션 (이동만).
- 데스크톱 변경 (이미 완료).
- 검색 화면 변경 (이미 `listAllNotes` 기반, 메모 포함되어 동작).

## Branch / Workflow

- Base: 최신 `develop` (PR #22~#24 머지 후 시점).
- Branch: `feature/mobile-memo-tab`.
- 14단계 워크플로우 적용. 단일 PR (develop 대상).
- 개발 일지: `.agent/develop/daily/2026-05-31-mobile-memo-tab.md`.

## Checklist

- [ ] `CalendarScreen` 탭 state + `_buildTabBar` + `_onMemoTabChanged`
- [ ] `_loadMemoNotes()` (listAllNotes + isMemo 필터 + updatedAt desc)
- [ ] `_loadNotes` daily 리스트에서 `isMemo` 제외
- [ ] build 분기 + `_buildMemoList` (빈 상태 포함)
- [ ] AppBar memo 분기 (타이틀/월네비)
- [ ] 롱프레스 `_showNoteActions` + `_setMemoFlag` 이동
- [ ] 위젯 테스트 6케이스 작성/통과
- [ ] mobile `flutter analyze` clean
- [ ] mobile `flutter test` 통과, desktop 회귀 없음
- [ ] 개발 일지 작성
- [ ] PR 작성 (develop 대상)
