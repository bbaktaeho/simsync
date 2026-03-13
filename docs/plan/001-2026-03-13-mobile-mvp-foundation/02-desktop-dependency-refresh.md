---
title: Desktop Dependency Refresh
description: 직접 의존성 업그레이드 범위와 검증 기준
type: design
created: 2026-03-13
---

# Desktop Dependency Refresh

## Approved Scope

- `file_picker`를 최신 resolvable major로 올린다.
- `google_fonts`를 최신 resolvable major로 올린다.

## Deferred Scope

- `flutter_markdown`은 지금 올리지 않는다.
- 이유: 현재 preview 핵심 위젯이 `flutter_markdown` API에 직접 결합되어 있고, replacement 패키지 전환은 별도 검증이 필요하다.

## Verification

- `flutter test`
- `flutter analyze`
- `flutter build macos`

## Expected Outcome

- direct dependency 경고 수를 줄인다.
- editor, preview, repo selection 관련 회귀가 없는지 확인한다.
