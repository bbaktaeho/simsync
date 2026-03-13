---
title: Mobile MVP Foundation Plan
description: desktop 의존성 정리, 저장 구조 분석, 모바일 MVP 단계 정리
type: plan
created: 2026-03-13
---

# Mobile MVP Foundation

## Goal

- 현재 저장소 상태를 문서와 맞춘다.
- `desktop/` Flutter 클라이언트의 직접 의존성을 안전하게 정리한다.
- GitHub/local 저장 구조를 확인한 뒤 mobile-first MVP 단계를 확정한다.

## Scope

- direct dependency 업그레이드: `file_picker`, `google_fonts`
- current storage behavior 분석: GitHub synced note, local note, cache/session path
- mobile-first MVP stage 정의: 설정, 검색, storage abstraction, Google Cloud 연동

## Out of Scope

- `flutter_markdown` 교체
- backend 도입
- Google Cloud 실제 구현
- 검색 엔진 실제 구현

## Execution Order

1. 문서 정합화
2. direct dependency 업그레이드
3. 검증
4. 저장 구조 분석 정리
5. mobile-first MVP 단계 문서화

## Detail Docs

- [01-current-repo-state.md](01-current-repo-state.md)
- [02-desktop-dependency-refresh.md](02-desktop-dependency-refresh.md)
- [03-mobile-mvp-stages.md](03-mobile-mvp-stages.md)
- [04-settings-foundation-implementation.md](04-settings-foundation-implementation.md)
- [05-search-foundation-implementation.md](05-search-foundation-implementation.md)
