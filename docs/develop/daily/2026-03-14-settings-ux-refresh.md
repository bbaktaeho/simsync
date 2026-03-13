# 2026-03-14 개발 일지

## 작업 목적

- `MVP Stage 1`의 설정 화면 UI/UX를 다시 정리한다.
- `cmd + +/-`, `cmd + mouse wheel`, trackpad pinch 기반 zoom이 즉시 반영되도록 수정한다.
- 설정 변경이 실제 런타임 저장소 상태와 연결되도록 보완한다.

## Confirmed Requirements

- 설정 화면은 `Dialog`를 유지한다.
- 좌측 category rail, 우측 detail pane 구조의 master-detail settings가 필요하다.
- `local note path`, `synced repository`, `content zoom`, `GitHub sync interval`을 실제로 조정할 수 있어야 한다.
- zoom 입력은 재렌더 지연 없이 바로 feedback이 보여야 한다.

## Assumptions

- local path와 synced repository 변경은 앱 셸에서 `StorageBundle`을 다시 만들지 않으면 실제 note source에 반영되지 않는다.
- zoom 체감 지연의 주원인은 settings 값 변경이 editor/preview rebuild로 즉시 전달되지 않는 데 있다.

## Proposed Decisions

- `SettingsScreen`은 `Storage`, `Editor & Preview`, `Sync` 3개 카테고리의 master-detail dialog로 재구성한다.
- local path와 repo 관련 조작은 `Storage` pane 안에서 inline control로 처리한다.
- `DocumentScreen`은 `settingsController`를 직접 listen해서 zoom 변화를 editor/preview/status bar에 즉시 반영한다.
- `AppSettingsController`는 zoom 값을 즉시 notify하고, persistence만 debounce한다.

## 구현 내용

### 1. Settings dialog 재구성

- `desktop/lib/screens/settings_screen.dart`를 Zed 스타일에 가까운 master-detail dialog 구조로 재작성했다.
- 좌측에는 category rail, 우측에는 detail pane을 두고 설정을 `Storage`, `Editor & Preview`, `Sync`로 분리했다.
- `Storage` pane에서 local note path, current repo, recent repos, existing repo connect, new repo create 흐름을 한 화면에서 다루도록 정리했다.
- 현재 연결된 repo는 recent repo chip에서 제외해 중복 표시를 없앴다.
- dialog 크기는 viewport에 맞춰 줄어들도록 바꿔 작은 창에서도 패널이 화면 밖으로 밀리지 않게 했다.

### 2. Zoom live feedback 수정

- `desktop/lib/screens/document_screen.dart`가 `settingsController`를 listen하도록 연결해 zoom 값이 바뀌면 즉시 rebuild되도록 수정했다.
- storage/localStorage가 교체될 때 note 목록을 다시 로드하도록 보완했다.
- title bar의 avatar는 빈 문자열일 때 `NetworkImage`를 만들지 않고 fallback icon을 사용하도록 방어 로직을 추가했다.
- `desktop/lib/settings/app_settings_controller.dart`에서는 content scale 저장을 debounce로 변경해 wheel/pinch 입력 중 persistence 지연이 체감되지 않게 했다.

### 3. Runtime 설정 연결 보완

- `desktop/lib/main.dart`에서 cached repo load, local note path 변경, repo create/connect/select callback을 `DocumentScreen`으로 전달하도록 확장했다.
- local path 변경 시 현재 session/repo 기준으로 새 `StorageBundle`을 만들고 sync engine을 다시 시작하도록 정리했다.

## 테스트 및 검증

- `flutter test test/settings/settings_screen_test.dart test/screens/document_screen_test.dart test/settings/app_settings_controller_test.dart` 통과
- `flutter analyze` 통과
- `flutter test` 전체 통과
- `flutter build macos` 성공

## 결과

- 설정 화면은 기존 단순 리스트형에서 category 기반 dialog로 바뀌었다.
- content zoom은 keyboard, wheel, pinch 입력 후 editor/preview/status bar에 즉시 반영된다.
- local path와 repo 관련 설정 변경은 UI 표시만 바뀌는 수준이 아니라 런타임 저장소에도 연결된다.
