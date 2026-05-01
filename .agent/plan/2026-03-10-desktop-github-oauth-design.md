# Desktop GitHub OAuth Login Design

## Scope

- 대상: `desktop/` Flutter app
- 단계: PoC
- 목표: 실제 `GitHub OAuth` 로그인, 로컬 세션 유지, 절대 만료 시 재로그인

## Confirmed Requirements

- 로그인 화면은 기존 카드 레이아웃과 애니메이션을 크게 바꾸지 않는다.
- 기존 이메일/비밀번호 입력은 제거하고 `Continue with GitHub` 버튼으로 대체한다.
- 로그인은 실제 GitHub OAuth로 동작해야 한다.
- 로그인 후에는 로컬 세션을 유지하고, `logout` 하거나 세션이 절대 만료되면 다시 로그인한다.
- 인증 구조는 앞으로 다른 로그인 방식을 추가할 수 있도록 `dependency injection` 기반으로 설계한다.
- 설계는 `SOLID` 원칙을 따른다.

## Caveats

- GitHub OAuth App의 토큰 교환에는 `client_secret`이 필요하다.
- 데스크톱 앱은 public client에 가깝기 때문에 `client_secret`을 완전히 안전하게 숨길 수 없다.
- 이번 PoC에서는 secret을 저장소에 넣지 않고 `--dart-define`으로 주입한다.
- 보안 강도가 더 중요해지는 단계에서는 backend-mediated OAuth 또는 GitHub App 기반 재검토가 필요하다.

## Proposed Decision

- 인증 플로우는 `Authorization Code + PKCE + loopback redirect`를 사용한다.
- 토큰과 프로필은 앱 내부에서 직접 조회한다.
- 세션은 app support directory 아래 JSON 파일로 저장한다.
- 세션 만료는 `issuedAt + 24 hours` 절대 만료로 판정한다.

## Architecture

### UI Layer

- `LoginScreen`
  - 브랜드 카드와 진입 애니메이션은 유지
  - `Continue with GitHub` 버튼만 표시
  - 진행 중 spinner, 오류 메시지, 환경설정 누락 메시지 표시
- `_AppShell`
  - 앱 시작 시 저장된 세션 복원
  - 유효 세션이 있으면 `DocumentScreen`
  - 없거나 만료되면 `LoginScreen`

### Auth Layer

- `AuthProvider`
  - 외부 로그인 방식 추상화
  - `signIn()` 한 메서드만 노출
- `GitHubOAuthProvider`
  - `state`, `code_verifier`, `code_challenge` 생성
  - `HttpServer.bind(InternetAddress.loopbackIPv4, 0)`로 임시 callback 서버 시작
  - `url_launcher`로 GitHub authorize URL 오픈
  - callback에서 `code`와 `state` 검증
  - access token 교환 후 GitHub user profile 조회
- `AuthService`
  - 로그인, 세션 복원, 로그아웃 orchestration
  - UI는 provider와 storage 세부사항을 직접 알지 않음
- `SessionPolicy`
  - 세션 만료 판정만 담당
- `SessionStore`
  - 세션 JSON 파일 저장, 조회, 삭제만 담당

### Dependency Composition

- `main.dart`에서 concrete implementation을 조립해 `_AppShell`에 주입
- UI는 `AuthService`만 의존
- 향후 `GoogleAuthProvider`, `EmailPasswordAuthProvider`를 같은 인터페이스 뒤에 추가 가능

## Data Model

### AuthSession

- `provider`: `github`
- `accessToken`
- `tokenType`
- `scope`
- `issuedAt`
- `expiresAt`
- `user`

### AuthUser

- `id`
- `login`
- `name`
- `avatarUrl`

## Configuration

- `SIMSYNC_GITHUB_CLIENT_ID`
- `SIMSYNC_GITHUB_CLIENT_SECRET`
- 값은 `--dart-define`으로 주입
- 둘 중 하나라도 없으면 로그인 버튼은 눌러도 인증을 시작하지 않고 명확한 오류를 표시

## Error Handling

- 브라우저 실행 실패
- callback timeout
- state mismatch
- token exchange 실패
- GitHub profile 조회 실패
- session file 파손

처리 원칙:

- UI에는 사용자 친화적 메시지 표시
- 내부 오류는 `Exception` 계층으로 분리
- 파손된 세션 파일은 삭제 후 비로그인 상태로 복구

## Testing Strategy

- `flutter_test` 기반 unit/widget test 추가
- `SessionPolicy` 만료 판정 테스트
- `SessionStore` 저장/복원/삭제 테스트
- `AuthService` 로그인 성공, 만료 세션 제거, 로그아웃 테스트
- `LoginScreen` GitHub 버튼 렌더링과 로딩 상태 테스트
- `AppShell` 유효 세션 복원 시 `DocumentScreen` 진입 테스트

## Out of Scope

- backend session issuance
- refresh token
- mobile OAuth
- multi-provider account linking
