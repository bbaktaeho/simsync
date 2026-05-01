---
title: Current Repo State
description: 현재 저장소 구현 상태와 MVP 계획의 제약 조건
type: design
created: 2026-03-13
---

# Current Repo State

## Confirmed State

- 현재 구현 기준 앱은 `desktop/` Flutter 프로젝트다.
- synced note는 GitHub repo의 markdown 파일로 저장된다.
- local note는 사용자가 선택한 로컬 디렉토리에 markdown 파일로 저장된다.
- GitHub repo 연결 정보는 로컬 JSON cache에 저장된다.
- GitHub sync는 git clone 기반이 아니라 API 호출 + commit SHA polling 방식이다.

## Constraints

- 현재 UI는 desktop-first다.
- settings/search/global storage provider 전환을 위한 전용 설정 모델이 아직 없다.
- editor/preview font size는 theme 고정값과 widget 내부 상수에 흩어져 있다.
- sync interval은 코드 상수로 박혀 있다.
- search index, query parser, background indexing 계층이 없다.

## Implications

- MVP 첫 단계는 새 provider를 붙이는 것보다 settings/state foundation을 먼저 만들어야 한다.
- 검색은 storage abstraction 위에서 돌아가야 하므로, GitHub/local note를 함께 다루는 read model이 먼저 필요하다.
- Google Cloud 연동은 storage provider abstraction과 migration flow 정의 뒤에 와야 한다.
