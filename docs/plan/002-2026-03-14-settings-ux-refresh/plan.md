---
title: Settings UX Refresh Plan
description: Stage 1 설정 UX 개선과 zoom live feedback 수정 계획
type: plan
created: 2026-03-14
---

# Settings UX Refresh

## Goal

- `SettingsScreen`을 Zed 스타일의 master-detail dialog로 재구성한다.
- `local note path`, `synced repository`, `content zoom`, `GitHub sync interval`을 설정 안에서 자연스럽게 다룰 수 있게 한다.
- keyboard, mouse wheel, trackpad pinch 기반 zoom이 즉시 반영되도록 런타임 연결을 수정한다.

## Scope

- settings dialog information architecture 재설계
- storage/editor/sync 카테고리 네비게이션 추가
- local note path 변경 UI 추가
- synced repository 변경 UI 추가
- content zoom live feedback 개선
- local path / repo 변경 시 runtime storage rebind

## Out Of Scope

- 설정 전체를 별도 full-screen page로 전환
- Google Cloud provider 설정
- search UX 추가 변경

## Detail Docs

- [01-settings-ux-design.md](01-settings-ux-design.md)
