---
title: Settings MVP 1 Bug Fixes Plan
description: settings 선택 표현, sync off 동작, local path switching 버그 수정
type: plan
created: 2026-03-14
---

# Settings MVP 1 Bug Fixes

## Goal

- settings 좌측 카테고리 선택 표현을 하나의 선택 상태로 명확하게 보이게 수정한다.
- `syncEnabled`가 꺼져 있을 때 synced note의 remote mutation이 일어나지 않도록 수정한다.
- local note path 변경 시 새 경로의 로컬 노트만 보이도록 reload race를 제거한다.

## Scope

- settings navigation selected style 조정
- synced note create/edit/delete guard 추가
- local path switch 시 stale note load 방지
- 관련 widget test, screen test 추가
- 개발 일지 작성

## Out of Scope

- settings 전체 레이아웃 재설계
- GitHub/local storage abstraction 개편
- sync provider 확장

## Execution Order

1. 현재 버그를 재현하는 failing test 추가
2. settings navigation selected style 수정
3. sync off 상태의 synced note mutation guard 추가
4. local path switching race 제거
5. analyze, test, build 검증
