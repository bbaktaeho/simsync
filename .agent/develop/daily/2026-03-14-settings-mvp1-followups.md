# 2026-03-14 개발 일지

## 작업 목적

- `MVP 1` settings 후속 버그를 수정한다.
- settings 안에서 GitHub background sync on/off 토글을 추가한다.

## Confirmed Requirements

- 좌측 카테고리 선택 시 중복 선택처럼 보이는 표현을 줄여야 한다.
- `Storage > Local note path > Change...`가 실제로 동작해야 한다.
- `Storage` 안에서 GitHub sync를 켜고 끌 수 있어야 한다.
- 이번 범위는 하나의 브랜치와 하나의 PR로 정리해야 한다.

## Assumptions

- 사용자가 말한 sync on/off는 synced note의 background polling on/off를 의미한다.
- synced note의 GitHub write path 자체를 끄는 full offline mode는 이번 범위가 아니다.
- local path change의 실사용 문제는 UI wiring 외에도 macOS file picker 조건 문제일 수 있다.

## Proposed Decisions

- 좌측 카테고리 라벨과 우측 pane title을 다른 문구로 분리해 중복 선택 인상을 줄인다.
- local path picker는 현재 경로가 실제로 존재할 때만 `initialDirectory`로 넘긴다.
- macOS file picker가 요구하는 `user-selected read-write` entitlement를 추가한다.
- sync toggle은 `AppSettings`, `AppSettingsController`, `SimSyncApp`, `SettingsScreen`에 연결한다.

## 구현 내용

### 1. Settings 표현 정리

- `desktop/lib/screens/settings_screen.dart`의 pane title을 `Workspace storage`, `Reading & zoom`, `Background sync`로 바꿨다.
- 좌측 navigation label과 우측 pane heading이 같은 문자열로 중복되지 않게 조정했다.

### 2. Local note path 변경 보완

- `desktop/lib/screens/settings_screen.dart`에 `resolveDirectoryPickerInitialPath()`를 추가해 존재하지 않는 경로는 `initialDirectory`로 넘기지 않도록 했다.
- `desktop/lib/screens/settings_screen.dart`의 action button을 `OutlinedButton` 기반으로 바꿔 desktop에서 hit target이 명확하도록 정리했다.
- `desktop/macos/Runner/DebugProfile.entitlements`와 `desktop/macos/Runner/Release.entitlements`에 `com.apple.security.files.user-selected.read-write` entitlement를 추가했다.

### 3. GitHub background sync toggle 추가

- `desktop/lib/settings/app_settings.dart`와 `desktop/lib/settings/app_settings_controller.dart`에 `syncEnabled`를 추가하고 persistence를 연결했다.
- `desktop/lib/screens/settings_screen.dart`의 `Storage` pane에 `GitHub background sync` toggle을 추가했다.
- `desktop/lib/screens/document_screen.dart`와 `desktop/lib/main.dart`에서 toggle 변경 시 현재 `GitHubSyncEngine`을 `start()` 또는 `stop()` 하도록 연결했다.
- 앱 시작 시에도 `syncEnabled` 설정을 읽어 sync engine을 시작할지 결정하도록 수정했다.

## 테스트 및 검증

- `desktop/test/settings/app_settings_controller_test.dart`
  - `syncEnabled` persistence 추가
- `desktop/test/settings/settings_screen_test.dart`
  - pane heading 구분 회귀 테스트 추가
  - local path change + sync toggle 테스트 추가
  - invalid initial path fallback 테스트 추가
- `desktop/test/widget_test.dart`
  - sync disabled startup 시 `GitHubSyncEngine.start()` 미호출 테스트 추가
  - settings toggle off 시 `GitHubSyncEngine.stop()` 호출 테스트 추가

## 결과

- settings 좌측 카테고리 선택이 이전보다 덜 혼동되게 정리됐다.
- local note path 변경은 invalid initial path와 macOS entitlement 조건까지 보완됐다.
- 사용자는 settings에서 GitHub background sync polling을 직접 끄고 켤 수 있다.
