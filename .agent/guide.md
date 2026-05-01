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
| Client (Desktop) | Flutter (Dart) | `desktop/` - macOS/Windows/Linux |
| Client (Mobile) | Flutter (Dart) | `mobile/` - Android/iOS |
| Auth (Desktop) | GitHub OAuth App | loopback callback + local session restore |
| Auth (Mobile) | GitHub OAuth App | Custom URL Scheme (`simsync://callback`) + app_links |
| Synced Storage | GitHub Contents API | 로컬 git clone 없이 API로 markdown 파일 CRUD |
| Local Storage | Local filesystem | 사용자가 고른 디렉토리 아래 markdown 파일 저장 |

## Project Structure

> 이 구조는 개발 진행에 따라 변경될 수 있다. 변경 시 이 섹션을 갱신한다.

```
simsync/
├── AGENTS.md          # Agent instruction (single source of truth)
├── .agent/            # Agent 가이드 및 작업 문서
│   ├── guide.md       # 이 문서
│   ├── workflow.md    # 작업 워크플로우
│   ├── plan/          # 기획 및 설계 문서
│   ├── develop/       # 개발 일지
│   ├── proposal/      # 제품 제안서
│   └── rules/         # rules.md (AGENTS.md symlink)
├── desktop/           # Flutter client (macOS/Windows/Linux)
│   ├── lib/
│   │   ├── auth/      # GitHub OAuth, session 관리
│   │   ├── models/    # Domain models
│   │   ├── screens/   # UI screens
│   │   ├── search/    # Full-text search
│   │   ├── services/  # Business logic
│   │   ├── settings/  # App settings, shortcuts
│   │   ├── storage/   # GitHub/local storage abstraction
│   │   ├── theme/     # Theme and design tokens
│   │   └── widgets/   # Shared widgets
│   └── test/
└── mobile/            # Flutter client (Android/iOS)
    ├── lib/
    │   ├── auth/      # GitHub OAuth (Custom URL Scheme)
    │   ├── models/    # Domain models (desktop과 동일)
    │   ├── screens/   # Mobile UI (Bottom Navigation)
    │   ├── search/    # Full-text search (desktop과 동일)
    │   ├── services/  # Business logic (desktop과 동일)
    │   ├── settings/  # App settings (shortcuts 제외)
    │   ├── storage/   # GitHub/local storage (desktop과 동일)
    │   ├── theme/     # Theme (mobile dimensions)
    │   └── widgets/   # Mobile widgets
    └── test/
```

## Domain Entities

> 현재 PoC에서 구현된 Flutter 모델은 `Note`, `Tag`, `NoteTag`다.  
> `NoteRevision`, `Device`, `SyncEvent`, `Summary`, `SummarySource`는 미래 백엔드 구현을 위한 개념 설계이며 아직 코드에 존재하지 않는다.

- **User** - 계정 소유자
- **Note** - 날짜에 연결된 마크다운 문서
- **Tag** - 사용자 정의 레이블
- **NoteTag** - 노트-태그 연결
- **Device** - 등록된 클라이언트 (desktop/mobile) — 미구현
- **NoteRevision** - 노트 변경 이력 — 미구현
- **Summary** - AI 생성 주기별 요약 (weekly/monthly/yearly) — 미구현
- **SummarySource** - 요약과 원본 노트 간 연결 — 미구현
- **SyncEvent** - 동기화 액션 기록 (create/update/delete) + 디바이스 출처 — 미구현

## Architecture

```
[Flutter App] ──> [GitHub OAuth + Contents API]
      │
      └──> [Local Filesystem]
```

- Client: `desktop/` (데스크톱)과 `mobile/` (모바일) 두 Flutter 프로젝트로 분리. 비즈니스 로직은 동일, UI는 플랫폼별 최적화
- Auth: GitHub OAuth로 access token 발급 및 로컬 session 저장
- Synced storage: GitHub Contents API로 `notes/.../*.md` 파일 CRUD
- Local storage: 사용자가 선택한 로컬 경로에 markdown 파일 저장
- Sync: branch 최신 commit SHA polling 기반 변경 감지
- AI/전용 backend: 현재 저장소에는 아직 구현되지 않음

## Key Design Decisions

- **Markdown-first**: 모든 노트는 마크다운 기반
- **Date-oriented**: 캘린더는 날짜별 노트 탐색 도구 (스케줄링 도구 아님)
- **Default daily note**: 날짜당 첫 노트 생성 시 기본 일일 노트 1개 필수 생성, 추가 노트는 선택
- **Single-user experience, multi-user architecture**: 개인 앱이지만 계정 기반 데이터 격리 — 현재 PoC는 GitHub 계정 단위로 repo가 분리되므로 자연히 격리됨. 전용 백엔드 도입 시에도 이 원칙을 유지한다
- **Flutter dual project**: 데스크톱(`desktop/`)과 모바일(`mobile/`)을 별도 Flutter 프로젝트로 분리. 비즈니스 로직(models, storage, services, search)은 복제, UI는 플랫폼별 작성
- **GitHub-backed PoC**: 현재 PoC는 별도 backend 없이 GitHub repo를 synced storage로 사용
- **Local + synced split**: 로컬 노트와 synced 노트를 같은 UI에서 다루되 저장소는 분리
- **Last-Write-Wins (current behavior)**: 동기화 충돌 시 최신 remote state 기준으로 다시 로드하고 dirty note는 로컬에서 보호

## Dependency Policy

### Client (Flutter/Dart)

Flutter 생태계의 안정적이고 널리 사용되는 패키지를 선택한다.
불필요한 의존성 추가를 지양하고, 필요 시 패키지를 명시적으로 승인한다.

## Build & Run

### Flutter App

```bash
# Desktop
cd desktop
flutter run -d macos          # macOS desktop
flutter run -d windows        # Windows desktop
flutter run -d linux          # Linux desktop
flutter build macos           # macOS release
flutter test                  # run tests
flutter analyze               # static analysis

# Mobile
cd mobile
flutter run                   # connected mobile device
flutter build apk --debug \   # Android debug APK (OAuth 자격증명 필요)
  --dart-define=SIMSYNC_GITHUB_CLIENT_ID=<id> \
  --dart-define=SIMSYNC_GITHUB_CLIENT_SECRET=<secret>
flutter build ios             # iOS release
flutter test                  # run tests
flutter analyze               # static analysis
```

## Workflow

작업 워크플로우는 [.agent/workflow.md](workflow.md)를 참고한다.

## Additional Docs

- [.agent/plan/](plan/) - 기획 및 설계 문서
- [.agent/develop/](develop/) - 개발 일지

특정 토픽의 문서가 여러 개가 되면 디렉토리로 분리한다:

순서가 있는 문서:
- .agent/{topic}/001-{상세내용}.md

순서가 없는 문서:
- .agent/{topic}/{상세내용}.md
