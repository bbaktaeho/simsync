---
title: Local Note Path Change Fix Plan
description: settings 화면에서 local note path를 실제로 변경할 수 있도록 하는 수정
type: plan
created: 2026-03-14
---

# Local Note Path Change Fix

## Goal

- `SettingsScreen`에서 local note path를 실제로 변경할 수 있게 한다.
- 경로 변경 후 앱 런타임이 새 local storage path를 사용하도록 연결한다.

## Scope

- `SettingsScreen`에 local path change action 추가
- `DocumentScreen`과 `SimSyncApp`에 local path 변경 callback 연결
- storage 교체 시 note reload 동작 보완
- widget test 추가

## Out of Scope

- settings 화면 전체 UI 재설계
- repo selection 흐름 변경
- search, sync, Google Cloud 관련 작업

## Execution Order

1. failing test 추가
2. settings action 및 callback 구현
3. local storage rebind 연결
4. analyze, test, build 검증
