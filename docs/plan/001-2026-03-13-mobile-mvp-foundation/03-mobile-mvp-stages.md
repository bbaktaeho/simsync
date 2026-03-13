---
title: Mobile MVP Stages
description: mobile-first MVP 단계와 구현 순서
type: design
created: 2026-03-13
---

# Mobile MVP Stages

## Recommended Order

1. Settings Foundation
2. Search Foundation
3. Storage Provider Abstraction + Migration
4. Google Cloud Sync

## Stage 1. Settings Foundation

### Goal

- mobile/desktop 공통 설정 모델을 만든다.

### Included

- settings screen
- shortcut: `cmd + ,`
- local note path 확인
- synced note source 확인
- editor/preview font size 조절
- shortcut: `cmd + +`, `cmd + -`
- mouse wheel/trackpad zoom for editor + preview only
- GitHub sync interval 설정

### Notes

- settings 값은 `SharedPreferences` 기반으로 먼저 저장한다.
- font scale은 app-wide typography 전체가 아니라 editor/preview 영역에만 적용한다.

## Stage 2. Search Foundation

### Goal

- GitHub/local note 전체를 대상으로 빠른 검색이 가능한 read model을 만든다.

### Included

- full-text search
- tag search
- filter search
- date range filter

### Notes

- 첫 단계는 앱 시작 시 memory index 구축 + note 변경 시 증분 갱신으로 단순하게 간다.
- external search engine은 이 단계에 도입하지 않는다.

## Stage 3. Storage Provider Abstraction + Migration

### Goal

- GitHub 외 storage provider를 붙일 수 있게 설정과 migration 흐름을 분리한다.

### Included

- provider descriptor
- current provider status in settings
- migration entry point
- GitHub -> next provider migration flow

### Notes

- 이 단계가 끝나야 Google Cloud 연동을 안정적으로 붙일 수 있다.

## Stage 4. Google Cloud Sync

### Goal

- Google OAuth + Google Cloud storage provider를 추가한다.

### Included

- Google OAuth 인증
- Google Cloud storage sync
- settings에서 provider 연결/전환
- GitHub에서 Google Cloud로 migration

### Notes

- provider는 GitHub 구현과 동일한 note/storage abstraction을 재사용해야 한다.
