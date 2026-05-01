# GitHub 기반 노트 동기화 설계

> 작성일: 2026-03-10
> 상태: confirmed

## 개요

Go 백엔드/DB를 제거하고, GitHub repo를 노트 저장소 + 동기화 백엔드로 사용한다.
Flutter 앱이 GitHub REST API를 직접 호출하여 노트를 CRUD하고 자동 동기화한다.

## 아키텍처

```
[Flutter App (Desktop/Mobile)]
        │
        ├── NoteStorageInterface (추상 레이어)
        │       │
        │       ├── GitHubStorageAdapter (GitHub REST API)
        │       └── (향후 다른 저장소 어댑터 추가 가능)
        │
        └── SyncEngineInterface (추상 레이어)
                │
                ├── GitHubSyncEngine (폴링 기반)
                └── (향후 다른 동기화 엔진 추가 가능)
```

백엔드 서버 없음. 클라이언트가 저장소 API를 직접 호출한다.

## 핵심 인터페이스

### NoteStorage

노트 CRUD를 추상화한다. 저장소 구현에 의존하지 않는다.

- `listNotes(date)` — 특정 날짜의 노트 목록 조회
- `getNote(path)` — 노트 내용 읽기
- `saveNote(path, content)` — 노트 생성/수정
- `deleteNote(path)` — 노트 삭제
- `listDates(yearMonth)` — 특정 월의 노트가 있는 날짜 목록

### SyncEngine

동기화 로직을 추상화한다. 저장소별 충돌 처리도 여기서 담당한다.

- `start()` — 동기화 시작 (인터벌 폴링)
- `stop()` — 동기화 중지
- `syncNow()` — 즉시 동기화
- `onConflict` — 충돌 처리 콜백 (저장소별 전략 다름)

### ConflictResolver

충돌 해결 전략을 추상화한다.

- `resolve(local, remote)` — 충돌 발생 시 최종 내용 결정

## GitHub 구현 상세

### 인증

- GitHub OAuth (별도 개발 중)
- OAuth 토큰으로 API 인증

### 저장 구조

```
notes/
└── {YYYY-MM}/
    └── {DD}/
        └── {title}.md
```

예시:
```
notes/
└── 2026-03/
    └── 10/
        ├── 오늘의 회의.md
        └── 개발 일지.md
```

### API 사용

GitHub REST API — Contents API (`/repos/{owner}/{repo}/contents/{path}`)

| 동작 | HTTP Method | 비고 |
|------|------------|------|
| 노트 읽기 | GET | Base64 디코딩 필요 |
| 노트 생성/수정 | PUT | SHA 필수, 자동 커밋 생성 |
| 노트 삭제 | DELETE | SHA 필수 |
| 디렉토리 조회 | GET | 파일 목록 반환 |

### 동기화

- 인터벌: 3~5초 폴링
- 변경 감지: 커밋 SHA 비교
- Rate limit: 인증 기준 시간당 5,000회 (충분)

### 충돌 처리

- Last-Write-Wins 전략
- PUT 시 409 Conflict 발생 → 최신 SHA로 GET → 로컬 내용으로 다시 PUT
- 개인 앱이므로 동시 편집 가능성 낮음

## PoC 범위

### 포함

- 데스크톱 (macOS) 우선
- GitHub OAuth 인증
- 노트 CRUD (GitHub Contents API)
- 자동 동기화 (3~5초 인터벌 폴링)
- 인터페이스 기반 저장소/동기화 추상화

### 제외 (추후)

- 모바일 (동일 코드로 확장 예정)
- AI 요약
- 오프라인 편집
- 태그 검색
- 다른 저장소 어댑터 (예: local filesystem, S3 등)

## 제거 대상

기존 설계에서 다음 항목은 이 PoC에서 불필요:

- Go 백엔드
- PostgreSQL
- WebSocket 실시간 푸시
- JWT 인증
- NoteRevision, SyncEvent, Device 엔티티 (git history가 대체)
