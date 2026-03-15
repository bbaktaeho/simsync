# Mobile MVP3 Bug Fixes

## Overview

`mobile/` MVP 3에서 보고된 UX/동기화 버그를 현재 저장소 구현 기준으로 수정한다.
이번 작업은 신규 기능 추가가 아니라 기존 화면/동기화 흐름의 결함 보정에 집중한다.

## Confirmed Requirements

- 모바일 마크다운 preview에서 세로 스크롤이 가능해야 한다.
- 모바일 마크다운 preview에서 문서 title이 보여야 한다.
- 모바일 달력의 오늘 날짜 표현은 desktop처럼 원형 강조 대신 더 가벼운 강조로 바뀌어야 한다.
- 모바일에서 desktop이 작성한 remote 변경이 실시간 polling 흐름으로 반영되어야 한다.
- 모바일 캘린더 상단에 GitHub profile image가 보여야 한다.
- 검색 filter bottom sheet가 Galaxy S24 계열의 system navigation 영역에 가려지지 않아야 한다.
- 하단 navigation의 첫 탭 label은 `캘린더` 대신 `노트`여야 한다.

## Assumptions

- "실시간"은 push가 아니라 현재 구현된 polling 기반 `GitHubSyncEngine` 주기 반영을 의미한다.
- 동기화 문제는 현재 구조상 mobile `EditorScreen`이 remote refresh를 구독하지 않는 것이 핵심 원인이다.
- 달력 today 디자인은 desktop의 사각 강조 패턴을 그대로 복제하기보다 mobile 레이아웃에 맞는 얇은 border 강조로 충분하다.
- 검색 filter 이슈는 bottom sheet content가 `viewPadding.bottom`을 반영하지 않아 발생한다.

## Root Cause Summary

- `mobile/lib/screens/editor_screen.dart`
  - preview 탭이 직접 `Markdown`을 렌더링하고 `InteractiveViewer` + `NeverScrollableScrollPhysics` 조합을 사용한다.
  - title 렌더링이 빠져 있고, remote refresh listener도 없다.
- `mobile/lib/screens/home_screen.dart`
  - `avatarUrl`을 `CalendarScreen`에 전달하지 않는다.
  - 첫 탭 label이 `캘린더`로 고정되어 있다.
- `mobile/lib/screens/calendar_screen.dart`
  - today cell을 채워진 원형으로 렌더링한다.
- `mobile/lib/screens/search_screen.dart`
  - filter sheet 하단 padding이 keyboard inset만 반영하고 safe area를 반영하지 않는다.

## Proposed Decisions

- preview 탭은 공용 `MarkdownPreview` 위젯을 사용하도록 맞추고, title/scroll/pinch zoom을 그 위젯 중심으로 정리한다.
- `EditorScreen`에 optional `refreshSignal`을 주입해 remote change 발생 시 dirty 상태가 아닐 때만 note를 다시 로드한다.
- `HomeScreen`은 `refreshSignal`과 `avatarUrl`을 필요한 screen으로 전달한다.
- calendar today cell은 mobile 기존 배치를 유지하면서 circle fill을 제거하고 subtle background + border 강조로 바꾼다.
- search filter sheet는 bottom safe area를 padding에 포함한다.

## Files To Modify

- `mobile/lib/screens/home_screen.dart`
- `mobile/lib/screens/calendar_screen.dart`
- `mobile/lib/screens/editor_screen.dart`
- `mobile/lib/screens/search_screen.dart`
- `mobile/lib/widgets/markdown_preview.dart`
- `mobile/test/...` 신규 widget test
- `docs/develop/daily/...` 개발 일지

## Verification

- `cd mobile && flutter test`
- `cd mobile && flutter analyze`
