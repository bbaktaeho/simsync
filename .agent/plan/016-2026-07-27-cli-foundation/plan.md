---
title: SimSync CLI 1차 설계 (Go)
description: Go CLI 기반 — 앱 실행, GitHub Device Flow 로그인, 세션 만료 확인(명령 + 상시 자동 체크)
type: plan
created: 2026-07-27
status: active
---

# Plan: SimSync CLI 1차 (Go)

## Confirmed requirements

1. `simsync` — SimSync(데스크톱 앱)를 켠다.
2. `simsync auth login` — GitHub OAuth Device Flow. 터미널에 one-time code와 URL이 그대로 표시되고, 승인까지 폴링한다 (gh auth login 스타일).
3. 로그인 세션이 언제 만료되는지 확인하는 기능 + 그것을 "항상" 확인하는 기능.
4. 언어는 Go (소유자 명시 승인).

## Assumptions

- "항상 확인" = 별도 데몬이 아니라, (a) 전용 `status` 명령 + (b) 모든 CLI 명령 실행 시 자동 만료 체크 후 경고 출력. 두 가지 모두 넣는다.
- 데스크톱 앱과 같은 OAuth App(공개 client_id, Device Flow — PR #41)을 사용한다. 시크릿 불요.
- 세션 만료 정책은 데스크톱과 동일하게 24시간 (`SessionPolicy(maxAge: 24h)` 미러).
- 1차는 macOS만 지원한다 (앱 자체가 macOS 중심).
- CLI 출력 언어는 앱과 동일하게 한국어, 기술 식별자는 영어.
- (개편) CLI의 1차 사용자는 AI agent다: 인증 명령은 `auth` 하위로 묶고(gh CLI 관례 —
  `session status`보다 agent들이 이미 아는 이름), help는 명령마다 동작과 용도를 함께 설명한다.
  노트 작성 워크플로는 [.agent/proposal/cli-note-workflow.md](../../proposal/cli-note-workflow.md) 참고.

## Proposed decisions

### 1차 명령 세트 (v0.1.0)

| 명령 | 동작 |
|------|------|
| `simsync` | 데스크톱 앱 실행 (`open -a simsync`). 실행 전 세션 자동 체크 → 만료/임박 시 경고 |
| `simsync auth login` | Device Flow: code/URL 표시 → 승인 폴링 → `/user` 조회 → 세션 저장. 성공 시 만료 시각 출력 |
| `simsync auth logout` | 세션 파일 삭제 |
| `simsync auth status` | 계정, scope, 발급/만료 시각, 남은 시간 + GitHub API 라이브 토큰 검증. 만료/미로그인 시 exit 1 (스크립트 연동: `simsync auth status \|\| simsync auth login`) |
| `simsync version` | CLI 버전 |
| `simsync help` | 사용법 |

### 상시 만료 체크 (요구 3-b)

- 모든 명령 진입 시 세션 파일을 읽어 stderr로 경고 한 줄:
  - 만료됨: `[알림] 세션이 만료되었습니다 (…). 'simsync login'으로 다시 로그인하세요.`
  - 2시간 미만 남음: `[알림] 세션이 1시간 23분 후 만료됩니다.`
- `login`/`logout`/`version`/`help`는 제외 (login이 곧 해결책, status는 자체가 상세 출력).

### 인증 / 세션

- Device Flow는 데스크톱 `github_oauth_provider.dart`의 이식: scope `read:user repo`,
  최소 폴링 5초, `slow_down` 시 +5초(또는 서버 지정값), `expired_token`/`access_denied` 처리,
  일시적 네트워크 오류·5xx·비JSON 응답은 스킵하고 계속 폴링 (device code 만료가 상한).
- client_id 기본값은 데스크톱과 같은 공개 id, `SIMSYNC_GITHUB_CLIENT_ID` 환경변수로 오버라이드.
- 세션 파일: `~/.simsync/cli/session.json`, 권한 0600.
  스키마는 데스크톱 `AuthSession.toJson()`과 **동일 필드** (provider/accessToken/tokenType/scope/issuedAt/expiresAt/user{id,login,name,avatarUrl}) — 2차에서 앱 세션 공유로 갈 때 포맷 호환이 이미 확보된다.
- `login`은 항상 새로 로그인해 세션을 덮어쓴다 (이미 로그인 상태여도 — 가장 단순하고 만료 갱신 목적과 일치).

### Go 구성

- 위치: `cli/` (desktop/, mobile/ 와 나란히). 모듈 `github.com/bbaktaeho/simsync/cli`.
- 의존성 없음 — stdlib만 (`flag` 수준도 불필요, 단순 서브커맨드 switch). cobra 등 프레임워크는 6개 명령에 과설계.
- 파일: `main.go`(디스패치/도움말/상시 체크), `session.go`(모델·저장·만료), `login.go`(Device Flow + /user), `launch.go`(앱 실행). 테스트 `login_test.go`, `session_test.go` (httptest).
- HTTP 클라이언트 타임아웃 30초.
- 빌드: `cd cli && go build -o simsync .` / 설치: `go install`.

### 2차 후보 (이번 범위 제외)

- `simsync memo "내용"` / `simsync note add` — 터미널 빠른 기록 (GitHub Contents API 직접 쓰기, note-format.md 스키마)
- repo 선택/설정 (`simsync repo set owner/name`)
- 앱 세션 파일 공유 (CLI 로그인 → 앱도 로그인) — 스키마는 이미 호환
- `simsync note list` / 검색, Linux/Windows 지원, `--json` 출력

## Affected files

- `cli/` (신규): go.mod, main.go, session.go, login.go, launch.go, 테스트 2개
- `.gitignore`: `cli/simsync` 바이너리
- `.agent/guide.md`: Tech Stack/레이아웃/Build & Run에 CLI 반영

## Out of scope

- 노트 읽기/쓰기 명령 (2차)
- 데스크톱 앱 세션과의 실시간 공유
- Homebrew 배포, 자동 업데이트
