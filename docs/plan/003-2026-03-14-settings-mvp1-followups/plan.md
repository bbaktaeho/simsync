---
title: Settings MVP 1 Follow-ups Plan
description: settings 화면 버그 수정과 GitHub background sync toggle 추가
type: plan
created: 2026-03-14
---

# Settings MVP 1 Follow-ups

## Goal

- `SettingsScreen`의 좌측 카테고리 선택 표현을 혼동 없이 보이게 수정한다.
- `Local note path`의 `Change...` 액션이 실제로 동작하도록 보완한다.
- settings 안에서 GitHub background sync polling을 켜고 끌 수 있게 한다.

## Scope

- settings navigation/pane label 표현 조정
- local note path change regression test 추가 및 동작 보완
- `AppSettings`에 sync enabled 상태 추가
- `SimSyncApp`, `DocumentScreen`, `SettingsScreen`에 sync on/off wiring 추가
- widget/unit test 추가

## Out of Scope

- 저장소 provider 구조 변경
- GitHub write path 자체를 끄는 완전한 offline mode
- settings 전체 레이아웃 재설계

## Execution Order

1. failing test 추가
2. settings category 표현 버그 수정
3. local note path change 동작 보완
4. sync enabled setting 및 runtime wiring 추가
5. analyze, test, build 검증
