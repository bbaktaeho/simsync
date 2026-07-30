---
title: 세션 만료 30일 sliding window 전환
description: 24시간 고정 세션 만료를 30일 sliding window로 바꿔 잦은 재로그인 제거
type: plan
created: 2026-07-30
status: active
---

# 세션 만료 30일 sliding window 전환

## 문제

로그인이 24시간마다 풀린다. GitHub OAuth Device Flow 토큰은 서버 측 만료가
없는데(classic OAuth App, refresh token 없음), 앱이 자체적으로
`SessionPolicy(maxAge: 24h)`를 부과하고 1분 주기 세션 체크가 이를 감지해
사용 중에도 강제 로그아웃 + 세션 파일 삭제를 수행한다.

- 데스크톱: `desktop/lib/app_bootstrap.dart` (24h), `desktop/lib/main.dart` 1분 주기 체크
- 모바일: `mobile/lib/main.dart` (24h)
- CLI: `cli/session.go` `sessionMaxAge = 24h`

네트워크 오류는 `SessionValidationResult.unknown`으로 안전 처리되어 로그아웃
사유가 아니다. 토큰 폐기(401/403)만 진짜 무효 사유다.

## 결정

- confirmed: 24시간 자체 만료가 원인. 토큰은 서버 측 만료 없음. 폐기 감지는 기존 로직 유지.
- proposed: maxAge 24h -> 30일. 세션 복원 성공 시 만료를 now+30일로 연장해
  저장(sliding window). 매일 쓰는 앱이므로 사실상 재로그인이 사라지고,
  30일 미사용 기기만 재인증한다.
- assumption: 로컬 만료는 방치 기기 위생용이다. 실제 보안 경계는 GitHub 토큰
  폐기이며 이는 기존 validateAccessToken 경로가 처리한다.

## 변경 범위

1. desktop: `app_bootstrap.dart` maxAge 30일, `auth/auth_service.dart`
   restoreSession 성공 시 sliding 갱신 저장
2. mobile: 동일 변경 (`main.dart`, `auth/auth_service.dart`)
3. cli: `session.go` sessionMaxAge 30일 + formatDuration 일 단위 표기,
   `main.go` 도움말 문구
4. 문서: `.agent/guide.md` CLI 만료 정책 문구
5. 테스트: desktop/mobile auth_service_test sliding 케이스, cli formatDuration 케이스

## 하지 않는 것

- 세션 스키마 변경 없음 (`expiresAt` 유지 — 구버전 CLI 바이너리 호환)
- 1분 주기 세션 체크 로직 변경 없음 (폐기 감지 용도로 유지)
- 토큰 암호화/keychain 이전 등 저장 방식 변경 없음
