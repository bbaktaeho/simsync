# 2026-03-14 개발 일지

## 작업 목적

- 설정 창에서 local note path를 실제로 변경할 수 없던 문제를 수정한다.
- 이미 작업 중이던 브랜치를 계속 쓰지 않고 `origin/develop` 기준 새 fix 브랜치로 정리한다.

## Confirmed Requirements

- 설정 창에서 local path change가 실제로 동작해야 한다.
- 작업 브랜치는 `origin/develop` 기준으로 다시 맞추고 새 PR을 열어야 한다.

## Assumptions

- 현재 `develop` 기준 `SettingsScreen`은 local note path를 표시만 하고 있으며, 변경 action이 없다.
- path를 바꿔도 runtime storage가 다시 묶이지 않으면 실제 note source는 계속 이전 경로를 보게 된다.

## Proposed Decisions

- `SettingsScreen`에 `Change...` action과 path picker callback을 추가한다.
- `SimSyncApp`은 path 변경 시 `StorageBundle`을 다시 만들고 `DocumentScreen`은 storage 변경을 감지해 note를 다시 로드한다.
- 이 수정은 `fix/settings-local-path-change` 브랜치에서 독립 커밋으로 정리한다.

## 구현 내용

- `desktop/test/settings/settings_screen_test.dart`에 local path change action이 실제로 path를 바꾸는 failing test를 먼저 추가했다.
- `desktop/lib/screens/settings_screen.dart`에 `onPickLocalNotePath`, `onLocalNotePathChanged`를 추가하고, local note path 카드에 `Change...` action을 연결했다.
- `desktop/lib/main.dart`에 `_handleLocalNotePathChanged`를 추가해 새 path를 저장하고 `StorageBundle`을 다시 만들도록 했다.
- `desktop/lib/screens/document_screen.dart`는 local storage가 바뀌면 note를 다시 로드하고, settings dialog로 path 변경 callback을 전달하도록 수정했다.

## 검증

- `flutter test test/settings/settings_screen_test.dart` 통과
- `flutter analyze` 통과
- `flutter test` 전체 통과
- `flutter build macos` 성공
