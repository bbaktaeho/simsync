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

## 2차 후보 (plan.md 참고)

- `simsync memo "..."` 터미널 빠른 기록, repo 설정, 앱 세션 공유, note list/검색
