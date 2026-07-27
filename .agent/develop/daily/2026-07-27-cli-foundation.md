---
title: SimSync CLI 1차 (Go)
description: Go CLI 신설 — 앱 실행, GitHub Device Flow 로그인, 세션 만료 확인(status + 상시 자동 체크)
type: develop
created: 2026-07-27
related:
  - .agent/plan/016-2026-07-27-cli-foundation/plan.md
---

# 2026-07-27 — SimSync CLI 1차 (Go)

## 작업 내용

`cli/` 신설 (Go 1.26, 의존성 0 — stdlib만, cobra 등 프레임워크 배제).

| 명령 | 동작 |
|------|------|
| `simsync` | 앱 실행 (`open -a simsync`, macOS LaunchServices) + 상시 세션 체크 경고 |
| `simsync login` | GitHub Device Flow — 일회용 코드/URL 터미널 표시, 승인 폴링, 세션 저장 |
| `simsync logout` | 세션 파일 삭제 |
| `simsync status` | 계정/scope/발급/만료(남은 시간) + GitHub API 라이브 토큰 검증. 만료·미로그인·무효면 exit 1 |
| `simsync version` / `help` | 버전 / 사용법 |

- Device Flow는 데스크톱 `github_oauth_provider.dart` 이식: scope `read:user repo`,
  최소 5초 폴링, slow_down 백오프, 일시 오류(네트워크/5xx/비JSON) 스킵, 같은 공개
  client_id 기본값 + `SIMSYNC_GITHUB_CLIENT_ID` 오버라이드.
- 세션: `~/.simsync/cli/session.json` (0600), 스키마는 데스크톱 `AuthSession.toJson()`과
  동일 필드 (2차 앱 세션 공유 대비), 만료 정책 24h 동일.
- 상시 체크: 명령 진입 시 세션이 만료/2시간 미만이면 stderr 경고 한 줄.

## 검증

- `gofmt` clean, `go vet` clean, `go test` 통과 (폴링 pending→slow_down→성공,
  거부/만료/일시오류 스킵, device code 요청, 숫자 id 변환, 토큰 검증 3분류,
  세션 라운드트립/권한/손상 복구/만료 포맷).
- 스모크: version/help/status(exit 1)/unknown(exit 2), 만료 세션 상태 출력과
  launch 경고, 실제 GitHub device code 발급까지 확인.

## 개편: AI agent용 CLI (같은 PR)

- 소유자 결정: CLI의 1차 사용자는 AI agent.
- 인증 명령을 `auth` 하위로 재구성: `auth login` / `auth logout` / `auth status`
  (gh CLI 관례 — agent들이 이미 아는 이름. 1차의 `login`/`status`는 미배포라 clean break).
- help 전면 개편: 명령마다 동작 + 용도(agent가 언제 쓰는지) + exit code 계약 명시.
- 노트 작성 워크플로 제안(`.agent/proposal/cli-note-workflow.md`) → 소유자 결정:
  **클론 기반 우선(C)** + **bare `simsync`는 help 출력, 앱 실행은 `simsync open`**.

## 클론 기반 노트 워크플로 구현 (v0.2.0, 같은 PR)

- `store clone <owner/repo> [dir]`: 클론 + 설정 저장(`~/.simsync/cli/config.json`).
  인증은 클론 로컬 git 설정에 `simsync auth git-credential` helper 등록 (gh 방식) —
  토큰이 git 설정/URL에 남지 않고, 클론 안 맨 git pull/push도 CLI 세션으로 동작.
  기존 클론 재실행 시 설정과 helper(바이너리 이동 대비)만 갱신.
- `note new [--date] [--title] [--memo] [--tags]`: 데스크톱 GitHubNoteStorage와
  동일 규칙으로 스캐폴드 (경로 sanitize, 밀리초 id, frontmatter, 날짜 첫 일일
  노트만 is_default — 메모는 세지 않음). stdout 마지막 줄 = 파일 경로 (agent 계약).
- `store sync`: dirty면 커밋 요구 후 실패, 아니면 pull --rebase + push.
- `guide [overview|note-format|guidelines]`: 클론의 `.agents/` 우선, 없으면
  go:embed 내장본(cli/guides/*.md — 하네스 템플릿과 동일 원문). 출처는 stderr.
- bare `simsync` → help 출력 (agent가 GUI를 실수로 띄우는 사고 방지), 앱 실행은
  `simsync open`. 버전 0.2.0.

## 검증 (2차분)

- go test: 클론→note new→커밋→sync 엔드투엔드(로컬 bare repo), 스캐폴드
  frontmatter/기본노트 규칙/메모 예외, git-credential get(정상·만료 거부),
  guide 내장/클론 우선, dirty sync 거부, 기존 클론 재설정.

## 2차 후보 (plan.md 참고)

- `simsync memo "..."` 터미널 빠른 기록, repo 설정, 앱 세션 공유, note list/검색
