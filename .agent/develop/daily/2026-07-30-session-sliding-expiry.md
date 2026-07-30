---
title: 세션 만료 30일 sliding window 전환
description: 24시간 고정 세션 만료가 매일 재로그인을 강제하던 문제를 30일 sliding window로 해결
type: develop
created: 2026-07-30
related:
  - .agent/plan/017-2026-07-30-session-sliding-expiry/plan.md
---

# 2026-07-30 — 세션 만료 30일 sliding window

## 문제

로그인이 24시간마다 풀렸다. 원인 조사 결과:

- GitHub OAuth Device Flow 토큰(classic OAuth App)은 **서버 측 만료가 없다**.
  refresh token도 없다. 즉 토큰은 사용자가 GitHub에서 폐기하기 전까지 유효.
- 그런데 앱이 자체적으로 `SessionPolicy(maxAge: 24h)`를 부과하고, 데스크톱은
  1분 주기 세션 체크(`sessionCheckInterval`)가 이를 감지해 **사용 중에도**
  강제 로그아웃 + 세션 파일 삭제를 수행했다.
- 네트워크 오류는 `SessionValidationResult.unknown`으로 안전 처리되어 있어
  로그아웃 사유가 아니다. 시간 만료가 유일한 원인이었다.
- 로컬 만료를 지워도 디스크의 토큰이 GitHub에서 폐기되는 게 아니므로, 24시간
  정책은 보안 이득 없이 UX 비용만 내고 있었다.

## 구현

### 정책: 24h -> 30일 sliding window

- `desktop/lib/app_bootstrap.dart`, `mobile/lib/main.dart`:
  `SessionPolicy(maxAge: Duration(days: 30))`
- `desktop/lib/auth/auth_service.dart`, `mobile/lib/auth/auth_service.dart`:
  `restoreSession()` 성공 시 `expiresAt`을 now+30일로 갱신해 저장하고 갱신본을
  반환. `issuedAt`은 원본 유지. 갱신은 복원 시점에만 일어난다 — 1분 주기
  체크는 검증만 하고 연장하지 않는다 (매분 디스크 쓰기 방지).
- 결과: 앱을 열 때마다 만료가 30일 뒤로 밀린다. 매일 쓰는 앱이므로 사실상
  재로그인 없음. 30일 미사용 기기만 재인증. 토큰 폐기(401/403) 감지는 기존
  `validateAccessToken` 경로 그대로.
- 알려진 한계: 앱을 30일 이상 재시작 없이 켜두면 in-memory 세션의 만료로
  1회 로그아웃된다. 릴리즈/재부팅 주기상 실질 발생 없음이라 수용.

### CLI 동기화

- `cli/session.go`: `sessionMaxAge = 30 * 24 * time.Hour`. CLI 로그인은 30일
  창으로 발급하고, 연장은 앱의 세션 복원이 담당 (같은 session.json 공유).
- `formatDuration`에 일 단위 표기 추가 ("30일", "29일 13시간") — status/login
  출력이 "720시간 0분"이 되지 않도록.
- `cli/main.go` 도움말, `.agent/guide.md` CLI 섹션 문구 갱신.

### 스키마/호환

- session.json 스키마 변경 없음 (`expiresAt` 유지). 구버전 CLI 바이너리는
  파일의 `expiresAt`을 그대로 읽으므로 호환. 기존 24h 세션은 남은 유효기간
  내 첫 복원에서 30일로 연장된다.

## 검증

- desktop: flutter test 485개 통과 (sliding 갱신 케이스 추가 — 갱신된
  expiresAt 반환/저장, issuedAt 보존), flutter analyze clean
- mobile: flutter test 16개 통과, flutter analyze clean
- cli: go test 통과 (formatDuration 일 단위 케이스 추가), go vet/gofmt clean
