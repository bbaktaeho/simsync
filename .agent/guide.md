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

## Purpose & Vision

> 상세: [.agent/proposal/2026-03-09-product-proposal-draft.md](proposal/2026-03-09-product-proposal-draft.md)

### Why this exists

기존 개인 기록 도구는 두 갈래로 갈린다 — 메모 앱은 빠르지만 시간이 지나면 맥락이 약해지고, 문서 앱은 구조적이지만 일상 기록과 회고로 이어지지 않는다.
SimSync는 그 중간을 노린다. `기록 → 축적 → 동기화 → 회고`로 이어지는 **개인 문서 워크플로우**가 핵심이다.

### Core value (3 pillars)

1. **Date-oriented writing** — 날짜를 기준으로 생각하고 기록한다
2. **Multi-device continuity** — 데스크톱과 모바일을 오가도 작업이 끊기지 않는다
3. **AI-powered reflection** — 누적된 기록을 주/월/년 단위로 정리해 회고를 돕는다 (계획)

### Target user

- 업무 기록을 날짜 기준으로 관리하는 개인
- 마크다운 기반 작성에 익숙한 사용자
- 여러 디바이스를 오가며 작업하는 사용자

### Positioning

- 메모 앱보다 구조적, 전통 문서 앱보다 가볍다
- Obsidian류보다 **날짜 진입**이 강하다
- Notion류보다 **개인 기록/회고**에 집중한다

## Required Expertise

Agent가 이 프로젝트에 효과적으로 기여하려면 아래 영역의 지식이 필요하다. 부족한 영역은 작업 전 관련 문서나 코드를 명시적으로 확인한다.

| Area | 요점 |
|------|------|
| **Flutter / Dart** | adaptive layout (LayoutBuilder/MediaQuery), state management 패턴, `flutter analyze` clean 유지 |
| **Cross-platform UX** | desktop vs. mobile 차이 (입력 방식, file dialog, OAuth callback, IA) |
| **GitHub OAuth App** | loopback callback (desktop), Custom URL Scheme `simsync://callback` (mobile), token 안전 저장 |
| **GitHub Contents API** | file CRUD, base64 인코딩, sha 기반 conflict 감지, rate limit 대응 |
| **Sync patterns** | Last-Write-Wins, polling-based change detection, dirty note 보호 |
| **Markdown ecosystem** | CommonMark, frontmatter, 편집 UX 패턴 |
| **Domain (date-oriented note)** | daily note, calendar 탐색, 주/월/년 집계, 회고 workflow |

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

모든 개발 작업은 [.agent/workflow.md](workflow.md)의 14단계 흐름을 따른다.

핵심 요지:
1. **계획 수립** → `.agent/plan/{순번}-{날짜}-{이름}/plan.md`
2. **계획 검토** → 과도 설계/누락 확인
3. **구현** → 변경 범위 최소화, 한 번에 한 관심사
4. **검토 루프** (4–13) → 목적 적합성, 보안, 사이드 이펙트, 코드 품질, 사용자 흐름
5. **커밋 & PR** → `develop` 브랜치 대상, conventional commit (`type: subject`)

브랜치는 항상 최신 `develop`에서 시작한다. 상세는 workflow.md 참고.

## Working with Project Documents

> Agent는 문서를 처음부터 끝까지 읽지 않는다. CLI 도구로 필요한 부분만 찾아 컨텍스트를 절약한다.

### Frontmatter convention

`.agent/` 아래 모든 새 markdown 문서는 frontmatter로 시작한다:

```yaml
---
title: 문서 제목
description: 한 줄 요약 (검색/식별용)
type: guide | workflow | plan | design | develop | proposal
created: YYYY-MM-DD
status: draft | active | archived   # 선택
related:                              # 선택 - 관련 문서 경로
  - .agent/plan/.../plan.md
---
```

기존 frontmatter가 없는 문서는 수정 시 함께 추가한다. frontmatter 덕분에 `head -n 10`만으로 문서 성격을 파악할 수 있다.

### Discovery commands (use BEFORE reading whole files)

```bash
# 1. 구조 파악 - 깊이 제한 필수
tree -L 2 .agent/
ls .agent/plan/

# 2. 파일 목록 정렬
ls -t .agent/develop/daily/          # 최근 수정순
ls .agent/plan/ | sort                # 이름순

# 3. frontmatter만 빠르게 훑기
head -n 10 .agent/plan/006-2026-03-15-mobile-mvp3/plan.md

# 4. 여러 파일 metadata 일괄 비교 (카탈로그 모드)
for f in .agent/plan/*/plan.md; do echo "=== $f ==="; head -n 7 "$f"; done

# 5. 키워드/패턴 검색
find .agent -name "*sync*" -type f
grep -rl "Last-Write-Wins" .agent/

# 6. 섹션 위치 확인 → 부분만 읽기
grep -n "^## " .agent/guide.md        # h2 + 줄번호

# 7. 구조화된 메타데이터 - YAML(pubspec)은 yq, JSON(API 응답 등)은 jq
yq '.dependencies | keys' desktop/pubspec.yaml    # YAML 키 목록
jq -r '.[].name' response.json                     # JSON 필드 추출
gh api repos/:owner/:repo/contents/notes | jq '.[].name'  # GitHub API 응답 파싱
```

### When to read full file vs. partial

| 상황 | 권장 |
|------|------|
| 코드 파일 수정 전 | 전체 읽기 (필수) |
| 짧은 문서 (< 100 줄) | 전체 읽기 |
| 후보 파일 식별 | frontmatter + 제목만 |
| 특정 섹션 참조 | grep으로 위치 찾고 부분만 |
| 카탈로그 확인 | `for f in ...; head -n 7` 일괄 |

## Additional Docs

- [.agent/plan/](plan/) - 기획 및 설계 문서
- [.agent/develop/](develop/) - 개발 일지

특정 토픽의 문서가 여러 개가 되면 디렉토리로 분리한다:

순서가 있는 문서:
- .agent/{topic}/001-{상세내용}.md

순서가 없는 문서:
- .agent/{topic}/{상세내용}.md
