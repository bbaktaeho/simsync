---
title: MVP 3 - Mobile App
description: Flutter 모바일 앱 설계 및 구현 계획
type: plan
created: 2026-03-15
---

# MVP 3: Mobile App

## Overview

Flutter 모바일 앱을 `mobile/` 디렉토리에 별도 프로젝트로 구현한다.
`desktop/`의 비즈니스 로직(auth, models, storage, search, settings)을 복사하고,
UI 레이어만 모바일에 맞게 새로 작성한다.

## Scope

**포함:**
- GitHub OAuth 로그인 (ASWebAuthenticationSession / Chrome Custom Tabs)
- 캘린더 (접기/펼치기) + 날짜별 노트 목록
- 노트 CRUD + 마크다운 에디터/프리뷰 (탭 전환)
- GitHub 동기화 (polling) + 로컬 노트 저장
- 검색 (텍스트 + 태그/날짜 필터, context lines, 키워드 하이라이트)
- 설정 (기본 배율, 검색 컨텍스트 줄, 동기화 토글/주기, 계정)
- 라이트/다크 테마
- 핀치 줌 (에디터/프리뷰)
- 마크다운 툴바 (H1, H2, H3, B, I, code, bullet, checkbox, quote, link)

**제외:**
- 키보드 단축키
- 로컬 저장 경로 변경 (앱 전용 디렉토리 고정)

## 상세 문서

- [01-project-structure.md](01-project-structure.md) - 프로젝트 구조 및 코드 복사 전략
- [02-screen-design.md](02-screen-design.md) - 화면별 상세 UI 설계
- [03-mobile-adaptations.md](03-mobile-adaptations.md) - 데스크톱 대비 모바일 적응 포인트
