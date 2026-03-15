---
title: Settings UX Design
description: dialog 기반 master-detail settings와 live zoom 반영 설계
type: design
created: 2026-03-14
---

# Settings UX Design

## Confirmed Requirements

- settings는 `Dialog`를 유지한다.
- 좌측 category rail, 우측 detail pane 구조를 사용한다.
- `local note path`, `synced repository`, `content zoom`, `GitHub sync interval`은 설정에서 수정 가능해야 한다.
- `cmd + +/-`, `cmd + mouse wheel`, trackpad pinch 입력은 즉시 반영되어야 한다.

## Assumptions

- repo 변경과 local path 변경은 앱 셸 레벨에서 storage bundle을 다시 만들어야 실제 note source가 반영된다.
- zoom 끊김은 `settingsController` 변경이 editor/preview rebuild로 즉시 전파되지 않는 것이 주요 원인이다.

## Proposed Decisions

- `SettingsScreen`은 `Storage`, `Editor & Preview`, `Sync` 3개 카테고리를 가진 master-detail dialog로 재구성한다.
- `Storage` 패널 안에서 local path 변경과 repo 변경 흐름을 inline controls로 처리한다.
- `DocumentScreen`은 `settingsController`를 listen해서 zoom 값 변화를 즉시 렌더링에 반영한다.
- `AppSettingsController`는 zoom 값은 즉시 notify하고, persistence는 debounce해서 입력 체감 지연을 줄인다.
- `AppShell`은 repo/local path 변경 callback을 내려주고, 해당 변경 시 `StorageBundle`을 다시 만들어 런타임 상태를 갱신한다.
