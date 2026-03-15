# 2026-03-14 개발 일지

## 작업 목적

- `MVP 1` settings 후속 버그 3건을 수정한다.

## Confirmed Requirements

- settings 좌측 카테고리 클릭 시 두 개가 선택된 것처럼 보이는 표현을 고친다.
- `syncEnabled`가 꺼져 있을 때 synced note 생성이 remote write로 이어지지 않게 한다.
- local note path 변경 후에는 새 경로의 로컬 노트만 보이게 한다.
- 수정 후 커밋, 푸시, `develop` 대상 PR까지 진행한다.

## Assumptions

- `syncEnabled`는 background polling만이 아니라 synced note mutation 허용 여부에도 영향을 줘야 한다.
- local path 문제는 단순 UI 갱신 문제가 아니라 stale async load race일 가능성이 높다.

## Proposed Decisions

- settings navigation은 단일 selected indicator만 남기도록 시각 표현을 단순화한다.
- sync off 상태에서는 synced note create, edit, delete를 막고 read-only 메시지를 제공한다.
- local path change 시 stale `_loadNotes()` 결과가 state를 덮지 못하게 generation guard를 추가한다.
- local path change 직후의 불필요한 `_refreshSignal` trigger는 제거한다.

## 구현 내용

### 1. Settings navigation selected 표현 수정

- `desktop/lib/screens/settings_screen.dart`
  - 좌측 category item의 selected 상태를 accent bar 1개로 통일했다.
  - icon container와 outer surface의 중복 강조를 줄였다.
  - selected item 검증용 key를 추가했다.

### 2. Sync off 상태의 synced note mutation 차단

- `desktop/lib/screens/document_screen.dart`
  - `syncEnabled`가 꺼져 있으면 synced note `create`, `delete`, `save` 경로를 막는다.
  - synced note는 read-only 메시지와 함께 editor에서 수정 불가 상태로 노출한다.
- `desktop/lib/widgets/editor_panel.dart`
  - read-only 상태를 받아 title/content/tag 편집을 막는다.

### 3. Local path switching race 제거

- `desktop/lib/screens/document_screen.dart`
  - `_loadGeneration` guard를 추가해 stale async load 결과를 무시한다.
- `desktop/lib/main.dart`
  - local path 변경 시 bundle 교체 이후 불필요한 `_refreshSignal` 증가를 제거했다.

## 테스트 및 검증

- `desktop/test/settings/settings_screen_test.dart`
  - settings navigation selected indicator 회귀 테스트 추가
- `desktop/test/widget_test.dart`
  - sync off 상태의 synced note create 차단 테스트 추가
  - local path change 후 새 경로 노트만 보이는지 테스트 추가
- `desktop/test/screens/document_screen_test.dart`
  - 기존 zoom 관련 회귀 테스트 유지 확인

## 결과

- settings 좌측 카테고리 선택은 단일 selected indicator로 보이도록 정리됐다.
- sync off 상태에서는 synced note remote mutation이 차단된다.
- local path 변경 후 stale load로 이전 경로 노트가 다시 보이는 문제를 막았다.
