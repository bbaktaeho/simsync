---
title: GitHub 인증 Device Flow 전환 (desktop) — 오픈소스 대비
description: 배포 바이너리에서 client_secret을 제거하기 위해 desktop 인증을 device flow로 교체
type: develop
created: 2026-07-03
related:
  - .agent/plan/012-2026-07-03-open-source-oauth-device-flow/plan.md
---

# 2026-07-03 개발 일지 — Device Flow 전환

## 목표

SimSync를 오픈소스로 공개하고 macOS 앱을 GitHub Releases로 배포하기 위해, 배포 바이너리에
client_secret이 임베드되지 않도록 desktop 인증을 GitHub Device Flow로 전환.

## 왜 device flow인가

- 기존 authorization code(web) flow는 토큰 교환에 client_secret 필수 → 배포 바이너리에서 추출 가능.
- GitHub는 OAuth App에서 PKCE를 secret 대체로 지원하지 않음.
- Device Flow는 처음부터 끝까지 **client_id(공개 값)만** 사용 (gh CLI와 동일). 시크릿 배포 문제 소멸.

## 변경 사항

- `auth_provider.dart`: `DeviceAuthorization`(userCode/verificationUri/expiresAt) +
  `DeviceAuthorizationPrompt` typedef + `signIn({onAuthorizationPrompt})` + `cancelSignIn()` 추가.
- `github_oauth_provider.dart`: device flow로 전면 재작성. `POST login/device/code`(client_id, scope)
  → 사용자에게 코드 노출 → `POST login/oauth/access_token`(client_id, device_code, grant_type)
  폴링. interval 준수, slow_down +5s, expired_token/access_denied 처리. cancel은 completer로
  폴링 대기를 깨움. loopback 서버/PKCE/state/clientSecret 전부 제거. scope는 `read:user repo`로
  축소 (user:email 미사용 확인).
- `app_bootstrap.dart`: `GitHubOAuthConfig`에서 clientSecret 제거. client_id는
  `String.fromEnvironment(defaultValue: 'Ov23likpPsGK5U4sCxI5')` — 공개 값이라 코드에 기본값 커밋,
  `.env.local` 없이도 로그인 동작. 포크는 dart-define으로 오버라이드.
- `login_screen.dart`: device code 다이얼로그(`_DeviceCodeDialog`). 열릴 때 코드 자동 클립보드
  복사 + verification_uri 자동 오픈. Cancel → cancelSignIn. AuthCancelledException은 에러 배너 없이
  조용히 복귀. `main.dart`에서 onCancelLogin 배선.
- `auth_service.dart`: signIn 시그니처 통과 + cancelSignIn 위임.
- 의존성: `crypto` 제거 (PKCE 전용이었음). 신규 의존성 없음.
- `.env.local.example`: desktop는 CLIENT_ID 오버라이드만/SECRET은 mobile 전용으로 주석 갱신.
- 테스트: provider 단위(성공/pending/slow_down/expired/denied/cancel/미설정/**시크릿 미전송 검증**),
  login_screen 위젯(다이얼로그 표시/취소/에러), 기존 fake auth 3곳(auth_service/document_screen/
  widget_test) 시그니처 갱신.

## 검증

- `flutter analyze` 클린, 전체 366개 테스트 통과.
- **시크릿 부재 증명**: `.env.local` 없이 debug 빌드 → 바이너리 전체에서 기존 secret 문자열
  미검출(0건), client_id는 kernel_blob에 존재(정상).
- **런타임 E2E** (실기기, `.env.local` 없이 빌드한 바이너리):
  로그인 → 실제 device code(`610A-F552`) 다이얼로그 표시 + 자동 복사("Copied") + 브라우저에
  github.com/login/device 자동 오픈 + "Waiting for authorization…" 폴링 + 만료 시간 표시 확인.
  Cancel → 다이얼로그 닫힘 + 에러 없이 로그인 화면 복귀 확인.
  (최종 승인 클릭까지의 세션 진입은 소유자 GitHub 계정 승인 필요 — 수동 확인 항목.)

## 후속 (로드맵)

- 소유자: 머지 후 OAuth App secret rotate (기존 로컬 빌드 임베드 이력 정리 — rotate 시 mobile
  `.env.local` 갱신 필요). Device Flow 활성화는 이미 켜져 있음(확인됨).
- GitHub App 전환(레포 단위 fine-grained 권한), mobile device flow 전환, LICENSE/README/
  히스토리 시크릿 스캔 등 나머지 오픈소스 준비.
