---
title: 오픈소스 대비 GitHub 인증 전면 개편 — Device Flow 전환 (desktop)
description: 배포 바이너리에서 client_secret을 제거하기 위해 desktop 인증을 GitHub Device Flow로 교체
type: plan
created: 2026-07-03
status: active
related:
  - desktop/lib/auth/github_oauth_provider.dart
  - desktop/lib/auth/auth_provider.dart
  - desktop/lib/auth/auth_service.dart
  - desktop/lib/screens/login_screen.dart
  - desktop/lib/app_bootstrap.dart
---

# 오픈소스 대비 GitHub 인증 전면 개편 — Device Flow (desktop)

## 배경

SimSync를 오픈소스로 공개하고 macOS 데스크톱 앱을 GitHub Releases로 배포하는 것이 목표다.
현재 인증은 authorization code(web) flow로, 토큰 교환에 `client_secret`이 필수라 빌드에
시크릿을 임베드해야 한다. 배포 바이너리에서 시크릿은 추출 가능하므로 이 구조는 배포와 양립 불가.
GitHub Device Flow는 처음부터 끝까지 `client_id`(공개 값)만 사용한다 — `gh` CLI와 동일한 방식.

참고: GitHub는 OAuth App에서 PKCE를 client_secret 대체로 지원하지 않는다 (현재 코드가 PKCE
파라미터를 보내지만 시크릿도 함께 요구되는 이유). 시크릿 없는 네이티브 앱 = Device Flow.

## Confirmed Requirements (소유자 확정, 2026-07-03)

- 배포 형태: GitHub Releases 바이너리 배포 (일반 사용자 다운로드) — 질문 1 답변 B.
- 권한 모델: 단계적 — 이번 작업은 기존 OAuth App 유지 + Device Flow 전환. GitHub App
  (레포 단위 fine-grained 권한) 전환은 후속 로드맵 — 질문 2 답변 C.
- 플랫폼 범위: desktop 먼저. mobile은 후속 (redirect flow와 device flow는 공존 가능) — 질문 3 답변 A.
- 접근: 전면 교체 (web flow/loopback/secret 경로 삭제, device flow 단일 경로) — 설계 승인됨.
- 외부 라이브러리: 추천 방향대로 소유자 승인 없이 진행 (결과: 신규 의존성 없음, `crypto`는
  PKCE 전용이었으므로 제거).

## 사전 확인 (완료)

- Device Flow가 OAuth App에 **이미 활성화됨** — `POST login/device/code`가 실제 user_code를
  반환하는 것을 확인 (2026-07-03).
- Device flow 스펙 (GitHub docs 재확인): `POST github.com/login/device/code`(client_id, scope) →
  device_code/user_code/verification_uri/expires_in(900s)/interval(5s). 폴링은
  `POST github.com/login/oauth/access_token`(client_id, device_code,
  grant_type=urn:ietf:params:oauth:grant-type:device_code). 에러: authorization_pending(계속),
  slow_down(+5s), expired_token(만료), access_denied(거부). **client_secret 불필요.**
  rate limit: user code 발급 앱 전체 50회/시간.
- `user:email` scope는 코드에서 미사용 (AuthUser에 email 없음) → scope를 `read:user repo`로 축소.
- `crypto` 패키지는 desktop에서 PKCE 외 사용처 없음 → 의존성 제거.

## Proposed Decisions (채택)

### D1. Provider 전면 교체 (파일/클래스명 유지)

`github_oauth_provider.dart`의 `GitHubOAuthProvider` 내부를 device flow로 재작성.
클래스/파일명을 유지해 diff 표면 최소화. 삭제: loopback HTTP 서버, PKCE(crypto), state 검증,
BrowserLauncher/LoopbackServerFactory, `clientSecret` 설정.

### D2. 인증 진행 상태의 UI 전달

Device flow는 사용자에게 코드를 보여줘야 하므로 인터페이스에 진행 콜백 추가:

```dart
class DeviceAuthorization {
  final String userCode;      // "XXXX-XXXX"
  final Uri verificationUri;  // https://github.com/login/device
  final DateTime expiresAt;
}
typedef DeviceAuthorizationPrompt = void Function(DeviceAuthorization authorization);

abstract class AuthProvider {
  Future<AuthGrant> signIn({DeviceAuthorizationPrompt? onAuthorizationPrompt});
  void cancelSignIn();   // 폴링 중단 (다이얼로그 취소)
  Future<SessionValidationResult> validateAccessToken(String accessToken);
}
```

`AuthService`도 동일하게 통과. 취소는 provider 내부 completer로 대기 중인 폴링 딜레이를 깨우고
`AuthCancelledException`을 던진다.

### D3. LoginScreen UX

- "Continue with GitHub" 클릭 → provider가 코드 발급 → 콜백으로 다이얼로그 표시.
- 다이얼로그: user_code 크게 표시(selectable) + 복사 버튼 + "Open GitHub" 버튼 + 진행 스피너 +
  Cancel. 다이얼로그가 열릴 때 코드를 클립보드에 자동 복사하고 verification_uri를 자동으로 연다
  (사용자는 붙여넣기 + 승인만 하면 됨).
- 승인 완료/실패/취소 시 다이얼로그 자동 닫힘. `AuthCancelledException`은 사용자 액션이므로
  에러 메시지 없이 조용히 복귀.
- 스타일: 기존 테마 토큰(AppTextStyles/AppDimensions/context.colors) 사용, DESIGN.md 준수.

### D4. client_id 기본값 하드코딩

`client_id`는 공개 값이므로 코드에 기본값으로 커밋:
`String.fromEnvironment('SIMSYNC_GITHUB_CLIENT_ID', defaultValue: 'Ov23likpPsGK5U4sCxI5')`.
포크 사용자는 dart-define으로 자기 OAuth App id를 오버라이드 가능. **`.env.local` 없이 빌드해도
로그인 동작** — 오픈소스 사용자/기여자의 진입 장벽 제거. desktop에서 SECRET 환경변수는 완전 제거.

### D5. 폴링 규칙

- 첫 대기부터 서버 응답 `interval`(최소 5초) 준수, `slow_down` 시 +5초.
- `expires_in` 초과 또는 `expired_token` → "코드 만료" 오류로 종료(재시도는 사용자 버튼).
- `access_denied` → 취소로 처리. 네트워크 오류는 AuthException으로 표면화.
- 테스트를 위해 딜레이 함수 주입 가능하게 설계.

## Out of Scope (로드맵 기록)

- **GitHub App 전환**: 레포 단위 fine-grained 권한 + 설치 플로우 + 만료 토큰/리프레시.
  오픈소스 신뢰성 향상의 다음 단계. (OAuth App의 `repo` scope는 모든 프라이빗 레포 권한을
  요구한다는 한계를 README에 명시할 것.)
- **mobile device flow 전환**: 전환 전까지 mobile 셀프 빌드는 기존 redirect flow + `.env.local`.
- **secret rotate**: desktop 머지 후 소유자가 OAuth App secret을 rotate (기존 로컬 빌드 임베드
  이력 정리). rotate 시 mobile `.env.local` 갱신 필요.
- LICENSE/README/기여 가이드/히스토리 시크릿 스캔 등 나머지 오픈소스 준비.

## 구현 순서

1. `auth_provider.dart`: `DeviceAuthorization`/prompt typedef/`cancelSignIn` 추가.
2. `github_oauth_provider.dart`: device flow로 재작성 (D1/D5).
3. `auth_service.dart`: signIn 시그니처 통과 + cancelSignIn 위임.
4. `app_bootstrap.dart`: config에서 secret 제거, client_id 기본값.
5. `login_screen.dart`: 다이얼로그 UX (D3). `main.dart` 배선.
6. 의존성: `crypto` 제거. `.env.local.example` 갱신 (desktop은 CLIENT_ID 오버라이드만,
   SECRET은 mobile 전용 표기).
7. 테스트: provider 단위(성공/pending/slow_down/expired/denied/cancel/미설정/시크릿 미전송 검증),
   auth_service 갱신, login_screen 위젯(다이얼로그 표시/취소).
8. 문서: guide.md 인증 행 갱신, 개발 일지.

## Testing & Verification

- `flutter analyze` 클린, 전체 테스트(회귀 포함) 통과.
- **시크릿 부재 증명**: `.env.local` 없이 빌드 → 바이너리에서 기존 secret 문자열 미검출 확인
  (값 비노출 방식으로 검사), client_id는 검출(정상).
- 런타임: 로그인 버튼 → 실제 device code 다이얼로그 표시 확인(코드 발급 API는 실호출),
  취소 동작 확인. 최종 승인 클릭(브라우저 GitHub 세션 필요)은 소유자 수동 확인 항목.
- 회귀: 기존 348+ 테스트, 앱 부팅/메뉴바 popover 스모크 (restoreSession 경로 무변경).
