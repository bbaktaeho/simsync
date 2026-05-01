# SimSync Architecture & Design Document

> 기획 컨텍스트: [2026-03-08-prototype-001.md](2026-03-08-prototype-001.md)

---

## 1. System Architecture Overview

### 전체 구조

```
┌──────────────────────────────────────┐
│       Flutter App (Dart)             │
│  ┌──────────────────────────────┐    │
│  │         Flutter UI           │    │
│  │  (Desktop + Mobile 단일 코드) │    │
│  └──────────┬───────────────────┘    │
└─────────────┼────────────────────────┘
              │     HTTPS + WSS
              │
         ┌────┴─────┐
         │  Backend  │
         │  (Go std) │
         └────┬──────┘
    ┌─────────┼──────────┐
    │         │          │
┌───┴─────┐ ┌┴──────┐ ┌─┴──────┐
│PostgreSQL│ │  WS   │ │AI API  │
│  18+    │ │ Hub   │ │Provider│
└─────────┘ └───────┘ └────────┘
```

### 컴포넌트 역할

| 컴포넌트 | 역할 | 기술 |
|----------|------|------|
| Backend | REST API + WebSocket Hub | Go `net/http` |
| Database | 모든 영속 데이터 저장 | PostgreSQL 18+ via `pgx/v5` |
| WS Hub | 변경사항 실시간 푸시 | `nhooyr.io/websocket` |
| Flutter App | 데스크톱 + 모바일 클라이언트 | Flutter (Dart), 단일 코드베이스 |
| AI Provider | 주기별 요약 생성 | Provider-agnostic HTTP 호출 |

### Caveat: 외부 의존성

#### Backend (Go)
Go 표준 라이브러리에는 PostgreSQL 드라이버와 WebSocket 서버가 없다.
요구사항(Go 표준 라이브러리 중심)을 유지하되, 아래 최소 의존성을 추가한다:
- `github.com/jackc/pgx/v5` — PostgreSQL 드라이버 (pure Go, 가장 널리 사용)
- `nhooyr.io/websocket` — WebSocket (pure Go, `net/http` 호환)

#### Client (Flutter/Dart)
Flutter 앱의 외부 패키지는 필요 시 명시적으로 승인한다.
안정적이고 널리 사용되는 패키지를 우선 선택한다.

---

## 2. Core Domain Model

### Entity Relationship

```
User 1──* Device
User 1──* Note
User 1──* Tag
User 1──* Summary

Note *──1 User
Note *──* Tag  (via NoteTag)
Note 1──* NoteRevision
Note *──* Summary (via SummarySource)

Summary 1──* SummarySource
```

### Go Struct 정의 (Backend)

```go
type User struct {
    ID           string    // UUID
    Email        string
    PasswordHash string
    CreatedAt    time.Time
    UpdatedAt    time.Time
}

type Device struct {
    ID        string    // UUID
    UserID    string
    Name      string    // e.g., "MacBook Pro", "iPhone 15"
    Platform  string    // "desktop" | "mobile"
    LastSeen  time.Time
    CreatedAt time.Time
}

type Note struct {
    ID        string    // UUID
    UserID    string
    NoteDate  string    // "2026-03-08" (YYYY-MM-DD)
    Title     string
    Content   string    // raw markdown
    IsDefault bool      // 해당 날짜의 기본 일일 노트 여부
    Version   int64     // optimistic locking + sync용
    CreatedAt time.Time
    UpdatedAt time.Time
}

type NoteRevision struct {
    ID        string    // UUID
    NoteID    string
    DeviceID  string    // 어떤 디바이스에서 변경했는지
    Content   string    // 변경 시점의 전체 content 스냅샷
    Version   int64
    CreatedAt time.Time
}

type Tag struct {
    ID        string    // UUID
    UserID    string
    Name      string
    CreatedAt time.Time
}

type NoteTag struct {
    NoteID string
    TagID  string
}

type Summary struct {
    ID         string    // UUID
    UserID     string
    PeriodType string    // "weekly" | "monthly" | "yearly"
    PeriodStart string   // "2026-03-01"
    PeriodEnd   string   // "2026-03-07"
    Content    string    // AI 생성 마크다운 요약
    ConsentAt  time.Time // 사용자 동의 시각
    CreatedAt  time.Time
}

type SummarySource struct {
    SummaryID string
    NoteID    string
}

type SyncEvent struct {
    ID        string    // UUID
    UserID    string
    DeviceID  string
    NoteID    string
    Action    string    // "create" | "update" | "delete"
    Version   int64
    CreatedAt time.Time
}
```

---

## 3. PostgreSQL Schema Draft

```sql
-- 확인된 요구사항: PostgreSQL 18+
-- Caveat: UUID 생성에 gen_random_uuid() 사용 (PG 13+ 내장)

CREATE TABLE users (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email       TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE devices (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id),
    name        TEXT NOT NULL,
    platform    TEXT NOT NULL CHECK (platform IN ('desktop', 'mobile')),
    last_seen   TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_devices_user_id ON devices(user_id);

CREATE TABLE notes (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id),
    note_date   DATE NOT NULL,
    title       TEXT NOT NULL DEFAULT '',
    content     TEXT NOT NULL DEFAULT '',
    is_default  BOOLEAN NOT NULL DEFAULT false,
    version     BIGINT NOT NULL DEFAULT 1,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_notes_user_date ON notes(user_id, note_date);
-- 날짜당 기본 노트는 최대 1개
CREATE UNIQUE INDEX idx_notes_default_per_date
    ON notes(user_id, note_date) WHERE is_default = true;

CREATE TABLE note_revisions (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    note_id     UUID NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    device_id   UUID NOT NULL REFERENCES devices(id),
    content     TEXT NOT NULL,
    version     BIGINT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_note_revisions_note_id ON note_revisions(note_id);

CREATE TABLE tags (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id),
    name        TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, name)
);

CREATE TABLE note_tags (
    note_id UUID NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    tag_id  UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (note_id, tag_id)
);

CREATE TABLE summaries (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES users(id),
    period_type  TEXT NOT NULL CHECK (period_type IN ('weekly', 'monthly', 'yearly')),
    period_start DATE NOT NULL,
    period_end   DATE NOT NULL,
    content      TEXT NOT NULL DEFAULT '',
    consent_at   TIMESTAMPTZ NOT NULL,  -- 사용자 동의 시각 (필수)
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_summaries_user_period ON summaries(user_id, period_type, period_start);

CREATE TABLE summary_sources (
    summary_id UUID NOT NULL REFERENCES summaries(id) ON DELETE CASCADE,
    note_id    UUID NOT NULL REFERENCES notes(id),
    PRIMARY KEY (summary_id, note_id)
);

CREATE TABLE sync_events (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES users(id),
    device_id  UUID NOT NULL REFERENCES devices(id),
    note_id    UUID NOT NULL REFERENCES notes(id),
    action     TEXT NOT NULL CHECK (action IN ('create', 'update', 'delete')),
    version    BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_sync_events_user_created ON sync_events(user_id, created_at);
```

---

## 4. Sync Strategy (MVP)

### 기본 방식: Server-Authoritative + Push Notification

```
[Client A] ──PUT /notes/{id}──▶ [Server] ──WebSocket push──▶ [Client B]
```

1. **쓰기**: 클라이언트가 REST API로 변경사항 전송
2. **서버 처리**: 서버가 DB에 저장하고 `version`을 증가
3. **푸시**: 서버가 해당 사용자의 다른 연결된 디바이스에 WebSocket으로 변경 알림
4. **동기화**: 알림 받은 클라이언트가 최신 데이터 fetch

### 동기화 흐름

```
1. 클라이언트 시작 시:
   - WebSocket 연결
   - GET /notes/sync?since={last_sync_timestamp} 로 미반영 변경 가져오기

2. 노트 수정 시:
   - PUT /notes/{id} (body에 version 포함)
   - 서버가 version 확인 → 저장 → version++ → sync_event 기록
   - 서버가 WS로 다른 디바이스에 push

3. WS 메시지 수신 시:
   - { type: "note_updated", note_id: "...", version: N }
   - 클라이언트가 GET /notes/{id} 로 최신 내용 fetch
```

### 제안: 오프라인 동작 (미확인 사항)
MVP에서는 오프라인 편집을 지원하지 않는다. 네트워크 미연결 시 편집 불가 표시.
향후 로컬 큐잉 + 재동기화로 확장 가능.

---

## 5. Conflict Resolution Strategy (MVP)

### 방식: Last-Write-Wins + Version Check

```
Client A (version=3) ──PUT──▶ Server (current version=3) ✅ 저장, version→4
Client B (version=3) ──PUT──▶ Server (current version=4) ❌ 409 Conflict
```

### 상세 동작

1. 모든 노트는 `version` 필드를 가진다 (Optimistic Locking)
2. 클라이언트가 PUT 요청 시 자신이 알고 있는 `version`을 함께 전송
3. 서버는 DB의 현재 `version`과 비교:
   - **일치**: 저장하고 `version++`
   - **불일치**: `409 Conflict` 반환 + 서버의 최신 내용 포함
4. 충돌 시 클라이언트 동작:
   - 서버의 최신 내용을 받아서 에디터에 반영 (서버 우선)
   - 사용자에게 "다른 디바이스에서 수정됨" 알림 표시

### 왜 Last-Write-Wins인가
- MVP에서 CRDT/OT는 과도한 복잡도
- 개인용 앱이므로 동시 편집 빈도가 낮음
- `version` 기반 충돌 감지만으로도 데이터 유실 방지 가능
- 향후 필요 시 CRDT로 확장 가능한 구조 (version + revision 기록)

---

## 6. API Contract Draft

### 인증

```
POST   /api/auth/register     회원가입
POST   /api/auth/login        로그인 → JWT 반환
POST   /api/auth/refresh      토큰 갱신
```

### 디바이스

```
POST   /api/devices            디바이스 등록
GET    /api/devices            내 디바이스 목록
```

### 노트

```
GET    /api/notes?date=2026-03-08           날짜별 노트 목록
GET    /api/notes?tag=work                  태그별 노트 목록
GET    /api/notes/sync?since=<timestamp>    마지막 동기화 이후 변경분
GET    /api/notes/{id}                      노트 상세
POST   /api/notes                           노트 생성 (is_default 자동 판단)
PUT    /api/notes/{id}                      노트 수정 (version 포함)
DELETE /api/notes/{id}                      노트 삭제
```

### 태그

```
GET    /api/tags               내 태그 목록
POST   /api/tags               태그 생성
DELETE /api/tags/{id}          태그 삭제
POST   /api/notes/{id}/tags    노트에 태그 연결
DELETE /api/notes/{id}/tags/{tag_id}   노트에서 태그 제거
```

### 요약

```
GET    /api/summaries?type=weekly&start=2026-03-01   요약 조회
POST   /api/summaries/generate                       요약 생성 요청 (동의 포함)
GET    /api/summaries/{id}                           요약 상세 + 원본 노트 참조
```

### WebSocket

```
GET    /api/ws                 WebSocket 연결 (JWT 인증)
```

WS 메시지 포맷:
```json
// Server → Client
{ "type": "note_created",  "note_id": "uuid", "version": 1 }
{ "type": "note_updated",  "note_id": "uuid", "version": 5 }
{ "type": "note_deleted",  "note_id": "uuid" }
{ "type": "summary_ready", "summary_id": "uuid" }
```

### 공통 응답 포맷

```json
// 성공
{ "data": { ... } }

// 에러
{ "error": { "code": "CONFLICT", "message": "Note was modified by another device" } }
```

### 주요 Request/Response 예시

**POST /api/notes** (노트 생성)
```json
// Request
{
  "note_date": "2026-03-08",
  "title": "오늘의 작업 기록",
  "content": "## 오전\n- API 설계 완료\n- 스키마 리뷰",
  "device_id": "uuid"
}

// Response 201
{
  "data": {
    "id": "uuid",
    "note_date": "2026-03-08",
    "title": "오늘의 작업 기록",
    "content": "...",
    "is_default": true,
    "version": 1,
    "created_at": "2026-03-08T10:30:00Z",
    "updated_at": "2026-03-08T10:30:00Z"
  }
}
```

**PUT /api/notes/{id}** (노트 수정)
```json
// Request
{
  "title": "오늘의 작업 기록 (수정)",
  "content": "## 오전\n- API 설계 완료\n...",
  "version": 1,
  "device_id": "uuid"
}

// Response 200 (성공)
{ "data": { "id": "uuid", "version": 2, ... } }

// Response 409 (충돌)
{
  "error": { "code": "CONFLICT", "message": "Note was modified by another device" },
  "data": { "id": "uuid", "version": 3, "content": "서버의 최신 내용..." }
}
```

**POST /api/summaries/generate** (AI 요약 생성)
```json
// Request — consent_confirmed 필수
{
  "period_type": "weekly",
  "period_start": "2026-03-01",
  "period_end": "2026-03-07",
  "consent_confirmed": true
}

// Response 202 (비동기 처리)
{ "data": { "summary_id": "uuid", "status": "processing" } }
```

---

## 7. Screen Flow

### 화면 구성 (공통)

```
┌──────────────────────────────────────────────┐
│ [Calendar View]  ←→  [Note List]  ←→  [Editor] │
└──────────────────────────────────────────────┘
```

### 화면 목록

| # | 화면 | 설명 |
|---|------|------|
| 1 | Login | 이메일/비밀번호 로그인 |
| 2 | Register | 회원가입 |
| 3 | Calendar | 월별 캘린더, 기록 있는 날짜에 표시 |
| 4 | Note List | 선택한 날짜의 노트 목록 |
| 5 | Editor | 마크다운 에디터 + 미리보기 (분할 또는 전환) |
| 6 | Search | 날짜/태그 기반 검색 |
| 7 | Summary | 주간/월간/연간 요약 조회 + 생성 |
| 8 | Settings | 디바이스 관리, 계정 설정 |

### Desktop 레이아웃 (≥ 768px)

```
Login ──▶ Calendar (메인)
              │
              ├── 날짜 클릭 ──▶ Note List (사이드바)
              │                    │
              │                    ├── 노트 클릭 ──▶ Editor (메인 영역)
              │                    └── [+ 새 노트] ──▶ Editor
              │
              ├── 검색 아이콘 ──▶ Search
              ├── 요약 아이콘 ──▶ Summary
              └── 설정 아이콘 ──▶ Settings
```

```
┌─────────┬──────────────────────────────┐
│ Sidebar │         Main Area            │
│         │                              │
│ Calendar│   Editor    │   Preview      │
│ ─────── │   (markdown)│   (rendered)   │
│ Note    │             │                │
│ List    │             │                │
│         │             │                │
├─────────┴──────────────────────────────┤
│ Status bar (sync status, last saved)   │
└────────────────────────────────────────┘
```

### Mobile 레이아웃 (< 768px)

```
Login ──▶ Calendar (메인, 전체 화면)
              │
              ├── 날짜 탭 ──▶ Note List (전체 화면)
              │                  │
              │                  ├── 노트 탭 ──▶ Editor (전체 화면, 편집/미리보기 전환)
              │                  └── [+ FAB] ──▶ Editor
              │
              ├── 하단 탭: 검색 ──▶ Search
              ├── 하단 탭: 요약 ──▶ Summary
              └── 하단 탭: 설정 ──▶ Settings
```

### Responsive/Adaptive 전략
Flutter 단일 코드베이스에서 `LayoutBuilder` 또는 `MediaQuery`를 사용하여
화면 크기에 따라 데스크톱/모바일 레이아웃을 자동 전환한다.
플랫폼별 차이(네비게이션, 입력 방식)는 adaptive 패턴으로 처리한다.

---

## 8. MVP Implementation Roadmap

### MVP 범위 정의

**포함 (MVP)**:
- 회원가입/로그인 (JWT)
- 캘린더 기반 일일 노트 CRUD
- Default daily note 자동 생성
- 마크다운 에디터 + 미리보기
- 태그 CRUD + 노트-태그 연결
- 날짜/태그 검색
- 멀티 디바이스 동기화 (REST + WebSocket)
- 충돌 감지 (version 기반, LWW)
- 디바이스 등록 + 액션 추적
- 데스크톱 + 모바일 앱 (Flutter 단일 코드베이스)

**제외 (Post-MVP)**:
- AI 요약 기능 (API 연동은 구조만 준비)
- 오프라인 편집
- 노트 히스토리/리비전 브라우징 UI
- Export/Import
- 다크 모드/테마 설정

### 구현 단계

| Phase | 기간 목표 | 내용 |
|-------|----------|------|
| **Phase 1: Backend Core** | 1단계 | DB 스키마 마이그레이션, User/Device/Note CRUD API, JWT 인증 |
| **Phase 2: Sync** | 2단계 | WebSocket Hub, sync_event 기록, version 기반 충돌 감지, 변경 푸시 |
| **Phase 3: Flutter App** | 3단계 | Flutter 앱 구현 (캘린더, 노트 CRUD, 에디터, 로그인), API 연동 |
| **Phase 4: Search & Tags** | 4단계 | 태그 CRUD, 노트-태그 연결, 날짜/태그 검색 API + UI |
| **Phase 5: Polish** | 5단계 | 동기화 안정화, 에러 처리, UX 다듬기 |
| **Phase 6: AI Summary** | 6단계 | AI 요약 API 연동, 동의 흐름, 요약 저장/조회 |

### Phase 1 상세 (다음 구현 대상)

```
backend/
├── main.go              # HTTP 서버 진입점
├── config/
│   └── config.go        # 환경변수 기반 설정
├── handler/
│   ├── auth.go          # 회원가입, 로그인, 토큰 갱신
│   ├── note.go          # 노트 CRUD
│   ├── device.go        # 디바이스 등록/조회
│   └── middleware.go    # JWT 검증 미들웨어
├── store/
│   ├── user.go          # User DB 접근
│   ├── note.go          # Note DB 접근
│   └── device.go        # Device DB 접근
├── model/
│   └── model.go         # 도메인 struct 정의
└── migration/
    └── 001_init.sql     # 스키마 마이그레이션
```

---

## 분류 요약

### 확인된 결정 (이 문서에서 확정)
- Server-authoritative sync (REST 쓰기 + WS 푸시)
- Last-Write-Wins + version 기반 충돌 감지 (MVP)
- JWT 토큰 기반 인증
- Backend 외부 의존성: `pgx/v5`, `nhooyr.io/websocket`
- Flutter 단일 코드베이스 (데스크톱 + 모바일)

### 제안 (오너 승인 필요)
- MVP에서 오프라인 편집 미지원
- MVP에서 AI 요약은 후순위 (Phase 6)
- 노트 삭제는 soft delete가 아닌 hard delete (MVP 단순화)

### 미확인 (추후 결정)
- AI provider 선정
- Flutter 패키지 선정 (마크다운 에디터, 상태관리 등)
- 요약 문서 포맷 상세
- 태그 자동완성/추천 UX
