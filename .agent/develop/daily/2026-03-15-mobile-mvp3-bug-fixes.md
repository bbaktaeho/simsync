---
title: Mobile MVP3 버그 수정
date: 2026-03-15
branch: fix/mobile-mvp3-bugs
---

# Mobile MVP3 버그 수정

## 목적

모바일 MVP3에서 확인된 preview, calendar, sync, profile avatar, search filter, navigation label 문제를 현재 코드 구조를 유지한 채 수정한다.

## 주요 수정

- `HomeScreen`이 `avatarUrl`과 `refreshSignal`을 필요한 screen에 전달하도록 정리했다.
- 하단 navigation 첫 탭 label을 `캘린더`에서 `노트`로 변경했다.
- `CalendarScreen`의 today cell을 채워진 원형 강조에서 subtle border 강조로 변경했다.
- `EditorScreen` preview 탭이 공용 `MarkdownPreview`를 사용하도록 바꾸고, title 표시와 세로 스크롤을 복구했다.
- `EditorScreen`이 `refreshSignal`을 구독해 dirty 상태가 아닐 때 remote note 변경을 다시 불러오도록 보강했다.
- `SearchScreen`이 remote refresh 시 index를 다시 만들고, filter bottom sheet가 bottom safe area를 반영하도록 수정했다.
- `MarkdownPreview`가 title-only 상태도 렌더링하도록 보강하고, 기존 double scaling을 제거했다.

## 테스트

- `flutter test test/screens/mobile_bug_regressions_test.dart`
- `flutter test`
- `flutter analyze`

## 추가 메모

- 회귀 방지용 widget test 5개를 `mobile/test/screens/mobile_bug_regressions_test.dart`에 추가했다.
- 문서 계획은 `docs/plan/007-2026-03-15-mobile-mvp3-bug-fixes/plan.md`에 기록했다.
