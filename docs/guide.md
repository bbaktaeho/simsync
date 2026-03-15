---
title: SimSync Guide
description: 프로젝트 핵심 구조, 기술 스택, 도메인 모델, 설계 결정 설명
type: guide
created: 2026-03-09
---

# Project Guide

## Product Overview

SimSync (Simple Sync)는 마크다운 기반 개인 노트 앱이다.
캘린더 기반 일일 노트 작성, 마크다운 편집, 날짜/태그 검색, 자동 멀티 디바이스 동기화, AI 주기별 요약을 제공한다.

## Tech Stack

| Component | Technology | Caveat |
|-----------|-----------|--------|
| Backend Language | Go 1.26.1 | - |
| Backend Framework | Go `net/http` + standard library | WebSocket은 `nhooyr.io/websocket` 사용 |
| Database | PostgreSQL 18+ | 드라이버로 `github.com/jackc/pgx/v5` 사용 |
| Client (Desktop + Mobile) | Flutter (Dart) | 단일 코드베이스로 데스크톱/모바일 모두 지원 |

## Project Structure

> 이 구조는 개발 진행에 따라 변경될 수 있다. 변경 시 이 섹션을 갱신한다.

```
simsync/
├── AGENTS.md          # Agent instruction (single source of truth)
├── app/               # Flutter app (desktop + mobile)
│   ├── lib/
│   │   ├── models/    # Domain models
│   │   ├── services/  # Business logic
│   │   ├── screens/   # UI screens
│   │   └── widgets/   # Shared widgets
│   └── test/
├── backend/           # Go API server
└── docs/
    ├── guide.md       # 이 문서
    ├── workflow.md    # 작업 워크플로우
    ├── plan/          # 기획 및 설계 문서
    ├── mvp/           # MVP 단계 노트
    └── develop/       # 개발 일지
```

## Domain Entities

- **User** - 계정 소유자
- **Device** - 등록된 클라이언트 (desktop/mobile)
- **Note** - 날짜에 연결된 마크다운 문서
- **NoteRevision** - 노트 변경 이력
- **Tag** - 사용자 정의 레이블
- **NoteTag** - 노트-태그 연결
- **Summary** - AI 생성 주기별 요약 (weekly/monthly/yearly)
- **SummarySource** - 요약과 원본 노트 간 연결
- **SyncEvent** - 동기화 액션 기록 (create/update/delete) + 디바이스 출처

## Architecture

```
[Flutter App (Desktop/Mobile)] ──> [Go Backend API] ──> [PostgreSQL]
                                         │
                                         ├──> [WebSocket] (실시간 푸시)
                                         └──> [AI Provider] (요약 생성)
```

- Client: Flutter 단일 코드베이스 (데스크톱 + 모바일)
- Backend: Go standard library HTTP server + WebSocket
- Database: PostgreSQL 18+
- Sync: 클라이언트 -> REST API로 변경 전송, 서버 -> WebSocket으로 변경 푸시
- AI: provider-agnostic, 사용자 동의 후에만 호출

## Key Design Decisions

- **Markdown-first**: 모든 노트는 마크다운 기반
- **Date-oriented**: 캘린더는 날짜별 노트 탐색 도구 (스케줄링 도구 아님)
- **Default daily note**: 날짜당 첫 노트 생성 시 기본 일일 노트 1개 필수 생성, 추가 노트는 선택
- **Single-user experience, multi-user architecture**: 개인 앱이지만 계정 기반 데이터 격리
- **Flutter unified client**: 데스크톱과 모바일을 Flutter 단일 코드베이스로 구현
- **Go backend**: 서버는 Go 표준 라이브러리 중심으로 구현
- **Last-Write-Wins (MVP)**: 동기화 충돌 시 최신 `updated_at` 기준으로 병합. 향후 CRDT/OT로 확장 가능

## Dependency Policy

### Backend (Go)

Go 표준 라이브러리를 최우선으로 사용한다. 외부 의존성이 불가피한 경우:
1. 요구사항을 유지한다
2. caveat을 명시한다
3. 최소한의 의존성만 추가한다

현재 승인된 외부 의존성:
- `github.com/jackc/pgx/v5` - PostgreSQL 드라이버
- `nhooyr.io/websocket` - WebSocket 지원

### Client (Flutter/Dart)

Flutter 생태계의 안정적이고 널리 사용되는 패키지를 선택한다.
불필요한 의존성 추가를 지양하고, 필요 시 패키지를 명시적으로 승인한다.

## Build & Run

### Flutter App (Desktop + Mobile)

```bash
cd app
flutter run -d macos          # macOS desktop
flutter run -d windows        # Windows desktop
flutter run -d linux          # Linux desktop
flutter run                   # connected mobile device
flutter build apk             # Android release
flutter build ios             # iOS release
flutter build macos           # macOS release
flutter test                  # run tests
flutter analyze               # static analysis
```

### Backend

```bash
cd backend
go run .               # run server
go test ./...          # run tests
go vet ./...           # static analysis
```

## Development Log

개발 일지는 `docs/develop/daily/` 에 작성한다.

파일 형식: `{YYYY-MM-DD}-{개발한 내용 요약}.md`

예시: `2026-03-12-auth-api-구현.md`

## Workflow

작업 워크플로우는 [docs/workflow.md](workflow.md)를 참고한다.

## Additional Docs

- [docs/plan/](plan/) - 기획 및 설계 문서
- [docs/mvp/](mvp/) - MVP 단계 노트
- [docs/develop/](develop/) - 개발 일지

특정 토픽의 문서가 여러 개가 되면 디렉토리로 분리한다:

순서가 있는 문서:
- docs/{topic}/001-{상세내용}.md

순서가 없는 문서:
- docs/{topic}/{상세내용}.md
