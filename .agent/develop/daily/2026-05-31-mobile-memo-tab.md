---
title: Mobile Memo Tab
description: 모바일 캘린더 화면에 daily | memo 탭 추가. memo 탭은 날짜 무관 전체 메모를 표시. 006(데스크톱)에서 별도 PR로 미뤄둔 모바일 UI 후속.
type: develop
created: 2026-05-31
status: active
related:
  - .agent/plan/007-2026-05-31-mobile-memo-tab/plan.md
  - .agent/plan/006-2026-05-02-memo-tab-restore/plan.md
---

# Mobile Memo Tab — 개발 일지

## 배경

006(`feature/memo-tab-restore`)에서 데스크톱 메모 탭을 복원하면서 모바일 UI는 "Out of scope (다음 PR 후보): 모바일 메모 탭 UI (long-press menu / editor popup)"로 명시 분리했다. 당시 모바일은 `is_memo` 데이터만 round-trip 안전하게 유지. 이 작업이 그 후속이다.

데이터/저장소는 이미 갖춰져 있었다: `Note.isMemo` + `copyWith(isMemo:)`, frontmatter `is_memo` 영속화, `NoteStorage.listAllNotes()`(SearchScreen이 이미 사용 중).

## 구현 개요 (모바일 단일 파일)

`mobile/lib/screens/calendar_screen.dart` 만 수정. 모델/저장소 변경 없음.

### 탭
- state `_memoTabActive`, `_memoNotes`, `_memoLoaded` 추가
- body 최상단에 `daily | memo` 탭 스트립(`_buildTabBar` / `_buildTabItem`, active underline)
- `daily`: 기존 캘린더+날짜헤더+날짜별 리스트. `memo`: 캘린더/날짜헤더 숨기고 전체 메모 평면 리스트

### 날짜 독립 데이터
- `_loadMemoNotes()`: `storage.listAllNotes()` (+`localStorage?.listAllNotes()`) → `where(isMemo)` → `updatedAt` desc. memo 탭 최초 진입 시 lazy 로드, 이동/`refreshSignal` 시 활성 탭 기준 재로드
- `_loadNotes()`에 `notes.removeWhere((n) => n.isMemo)` 추가 — 메모는 noteDate 폴더에 남아 `listNotes(date)`에 잡히므로 daily 리스트에서 제외 (데스크톱 `_notesForSelectedDate`와 동일 이유)

### 이동 (모바일엔 우클릭 없음)
- 노트 카드 `onLongPress` → `_showNoteActions` 하단 시트(`showModalBottomSheet`)
- `!isMemo` → "메모로 이동", `isMemo` → "daily로 이동"
- `_setMemoFlag`: `copyWith(isMemo:, updatedAt:)` → `_storageFor(note).saveNote` → 리스트 갱신. `noteDate`/`isDefault` 불변 (데스크톱과 동일)

### AppBar
- memo 활성 시 월 네비(이전/오늘/다음) 숨기고 타이틀 "메모". avatar·sync 인디케이터 유지

## 의식적으로 빠뜨린 것

- 하단 시트 삭제/태그 액션: 삭제는 기존 왼쪽 스와이프 유지, 이동만 노출 (MVP)
- memo 탭 직접 "새 메모" 생성 버튼: 데스크톱과 동일하게 이동으로만 생성
- 메모 별도 디렉토리: frontmatter flag만으로 구분 (006과 동일)

## 막힌 지점 / 수정

- **RenderFlex 오버플로우 회귀**: 탭 바(~37px)가 HomeScreen(하단 네비 포함, body 높이 축소) 맥락에서 daily **빈 상태** Column을 27px 넘치게 만들어 기존 테스트 `home screen shows note tab label` 실패.
  - 원인: 빈 상태가 `Center(child: Column(min))`라 가용 높이보다 크면 overflow.
  - 수정: `_scrollableCenter` 헬퍼(`LayoutBuilder` + `SingleChildScrollView` + `ConstrainedBox(minHeight: maxHeight)` + `Center`)로 daily/memo 빈 상태를 감쌈. 공간 충분 시 중앙 정렬, 좁으면 스크롤 → 작은 화면에서도 안전.

## 검증 (코드 기반, 에뮬레이터 미사용)

- `flutter analyze`: mobile clean
- `flutter test`:
  - mobile 12/12 통과 (신규 메모 탭 6 + 기존 6)
  - desktop 101/101 통과 (소스 미변경, 회귀 확인용)
- 신규 테스트 `mobile/test/screens/calendar_screen_memo_tab_test.dart` 6케이스:
  1. daily/memo 탭 렌더, 기본 daily
  2. memo 탭 = 서로 다른 날짜 메모 모두 표시 + 비메모 제외
  3. daily 탭 = 선택 날짜 비메모만 (메모 제외)
  4. 롱프레스 → "메모로 이동" → `isMemo=true` + memo 리스트 등장
  5. 메모 롱프레스 → "daily로 이동" → `isMemo=false`
  6. 메모 0개 빈 상태 문구

## 결정 로그

| 결정 | 근거 |
|------|------|
| 탭을 캘린더 화면 안에 배치 (4번째 하단 네비 X) | 데스크톱 `daily \| memo` 형태와 일치 (사용자 선택) |
| 롱프레스 → 하단 시트 이동 | 데스크톱 우클릭 메뉴의 모바일 대응. 기존 스와이프-삭제와 비충돌 |
| 빈 상태 scroll-tolerant 래핑 | 탭 바 추가로 좁아진 높이에서 overflow 방지. 실제 소형 기기도 안전 |
| memo lazy 로드 | 메모 미사용자에게 불필요한 `listAllNotes` 회피 |

## Out of scope (다음 후보)

- 키보드/제스처 단축 전환
- memo 검색 결과 시각 구분
- memo 탭 직접 생성 버튼
