# SimSync Project Guide

## Product Overview
SimSync (Simple Sync) is a personal markdown note application for mobile and desktop.
Calendar-based daily note entry, markdown authoring, date/tag search, automatic cross-device sync, and AI-powered periodic summaries.

## Architect Role & Working Rules
이 프로젝트의 AI agent는 lead product architect 겸 technical writing partner 역할을 수행한다.

### 고정 규칙
- 기술 스택을 임의로 변경하지 않는다. 변경이 필요하면 caveat을 명시하고 최소한의 예외만 제안한다.
- confirmed requirements, assumptions, proposed decisions을 항상 명확히 구분한다.
- 단순하고 프로덕션 가능한 MVP 결정을 우선한다.
- AI 요약 요청 전에 반드시 사용자의 명시적 동의를 받는다.
- AI 요약 결과는 원본 노트와 별도로 저장한다.
- 노트 변경 및 동기화 이벤트에 소스 디바이스를 기록한다.
- 팀 협업, 공유 워크스페이스, 웹 전용 요구사항은 명시적 요청 없이 추가하지 않는다.
- 기술적으로 불편한 요구사항이 있으면 요구사항을 유지하고 caveat을 명시한다.

### 출력 규칙
- 한국어로 설명한다.
- 기술 식별자(테이블명, struct명, API 경로, 필드명)는 영어를 사용한다.

## Domain Entities
- **User** — 계정 소유자
- **Device** — 등록된 클라이언트 (desktop/mobile)
- **Note** — 날짜에 연결된 마크다운 문서
- **NoteRevision** — 노트 변경 이력
- **Tag** — 사용자 정의 레이블
- **NoteTag** — 노트-태그 연결
- **Summary** — AI 생성 주기별 요약 (weekly/monthly/yearly)
- **SummarySource** — 요약과 원본 노트 간 연결
- **SyncEvent** — 동기화 액션 기록 (create/update/delete) + 디바이스 출처

## Architecture
```
[Flutter App (Desktop/Mobile)] ──▶ [Go Backend API] ──▶ [PostgreSQL]
                                         │
                                         ├──▶ [WebSocket] (실시간 푸시)
                                         └──▶ [AI Provider] (요약 생성)
```

- Client: Flutter 단일 코드베이스 (데스크톱 + 모바일)
- Backend: Go standard library HTTP server + WebSocket
- Database: PostgreSQL 18+
- Sync: 클라이언트 → REST API로 변경 전송, 서버 → WebSocket으로 변경 푸시
- AI: provider-agnostic, 사용자 동의 후에만 호출

## Key Design Decisions
- **Markdown-first**: 모든 노트는 마크다운 기반
- **Date-oriented**: 캘린더는 날짜별 노트 탐색 도구 (스케줄링 도구 아님)
- **Default daily note**: 날짜당 첫 노트 생성 시 기본 일일 노트 1개 필수 생성, 추가 노트는 선택
- **Single-user experience, multi-user architecture**: 개인 앱이지만 계정 기반 데이터 격리
- **Flutter unified client**: 데스크톱과 모바일을 Flutter 단일 코드베이스로 구현
- **Go backend**: 서버는 Go 표준 라이브러리 중심으로 구현
- **Last-Write-Wins (MVP)**: 동기화 충돌 시 최신 `updated_at` 기준으로 병합. 향후 CRDT/OT로 확장 가능

## Tech Stack Details
| Component | Technology | Caveat |
|-----------|-----------|--------|
| Backend Language | Go 1.26.1 | — |
| Backend Framework | Go `net/http` + standard library | WebSocket은 `nhooyr.io/websocket` 사용 (표준 라이브러리에 WebSocket 없음) |
| Database | PostgreSQL 18+ | 드라이버로 `github.com/jackc/pgx/v5` 사용 (최소 필수 의존성) |
| Client (Desktop + Mobile) | Flutter (Dart) | 단일 코드베이스로 데스크톱/모바일 모두 지원 |

## Dependency Policy

### Backend (Go)
Go 표준 라이브러리를 최우선으로 사용한다. 외부 의존성이 불가피한 경우:
1. 요구사항을 유지한다
2. caveat을 명시한다
3. 최소한의 의존성만 추가한다

현재 승인된 외부 의존성:
- `github.com/jackc/pgx/v5` — PostgreSQL 드라이버
- `nhooyr.io/websocket` — WebSocket 지원

### Client (Flutter/Dart)
Flutter 생태계의 안정적이고 널리 사용되는 패키지를 선택한다.
불필요한 의존성 추가를 지양하고, 필요 시 패키지를 명시적으로 승인한다.

## Documentation
- [Development Workflow](workflow.md) — 브랜치 전략, PR 프로세스, 테스트
- [Planning Documents](plan/) — 기획 및 설계 문서
