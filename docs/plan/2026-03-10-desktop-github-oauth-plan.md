# Desktop GitHub OAuth Login Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add real GitHub OAuth login to the Flutter desktop app with DI-based auth abstractions, persistent local session storage, and absolute session expiry.

**Architecture:** The UI depends on a small `AuthService` interface. A concrete `GitHubOAuthProvider` performs the loopback OAuth flow, `SessionStore` persists session state, and `SessionPolicy` decides whether a stored session is still valid. `main.dart` composes concrete implementations and injects them into the app shell.

**Tech Stack:** Flutter desktop, `flutter_test`, `url_launcher`, `http`, `path_provider`, `crypto`, `dart:io`

---

### Task 1: Add auth domain model and tests

**Files:**
- Create: `desktop/lib/auth/auth_models.dart`
- Create: `desktop/test/auth/auth_models_test.dart`

**Step 1: Write the failing tests**

- Add tests for session JSON serialization and required fields.

**Step 2: Run test to verify it fails**

- Run: `flutter test test/auth/auth_models_test.dart`

**Step 3: Write minimal implementation**

- Add `AuthUser` and `AuthSession` models with `toJson`/`fromJson`.

**Step 4: Run test to verify it passes**

- Run: `flutter test test/auth/auth_models_test.dart`

### Task 2: Add session policy and storage with tests

**Files:**
- Create: `desktop/lib/auth/session_policy.dart`
- Create: `desktop/lib/auth/session_store.dart`
- Create: `desktop/test/auth/session_policy_test.dart`
- Create: `desktop/test/auth/session_store_test.dart`

**Step 1: Write the failing tests**

- Add tests for expiry calculation and JSON file persistence.

**Step 2: Run test to verify it fails**

- Run: `flutter test test/auth/session_policy_test.dart test/auth/session_store_test.dart`

**Step 3: Write minimal implementation**

- Add `SessionPolicy` and file-backed `SessionStore`.

**Step 4: Run test to verify it passes**

- Run: `flutter test test/auth/session_policy_test.dart test/auth/session_store_test.dart`

### Task 3: Add provider abstraction and auth service with tests

**Files:**
- Create: `desktop/lib/auth/auth_provider.dart`
- Create: `desktop/lib/auth/auth_service.dart`
- Create: `desktop/test/auth/auth_service_test.dart`

**Step 1: Write the failing tests**

- Add tests for successful sign-in, restore with valid session, restore with expired session, and logout.

**Step 2: Run test to verify it fails**

- Run: `flutter test test/auth/auth_service_test.dart`

**Step 3: Write minimal implementation**

- Add provider interface and `AuthService`.

**Step 4: Run test to verify it passes**

- Run: `flutter test test/auth/auth_service_test.dart`

### Task 4: Add real GitHub OAuth provider

**Files:**
- Create: `desktop/lib/auth/github_oauth_provider.dart`
- Modify: `desktop/pubspec.yaml`

**Step 1: Write the failing tests**

- Add focused tests for PKCE helper behavior and configuration validation.

**Step 2: Run test to verify it fails**

- Run: `flutter test test/auth/github_oauth_provider_test.dart`

**Step 3: Write minimal implementation**

- Add GitHub authorize URL creation, callback handling, token exchange, and profile fetch.

**Step 4: Run test to verify it passes**

- Run: `flutter test test/auth/github_oauth_provider_test.dart`

### Task 5: Wire app shell and login UI

**Files:**
- Modify: `desktop/lib/main.dart`
- Modify: `desktop/lib/screens/login_screen.dart`
- Modify: `desktop/test/widget_test.dart`

**Step 1: Write the failing tests**

- Add widget tests for GitHub login button, restore loading state, and authenticated shell routing.

**Step 2: Run test to verify it fails**

- Run: `flutter test test/widget_test.dart`

**Step 3: Write minimal implementation**

- Inject `AuthService` into app shell and login screen.
- Replace legacy form with GitHub button.

**Step 4: Run test to verify it passes**

- Run: `flutter test test/widget_test.dart`

### Task 6: Verify full app checks

**Files:**
- Modify: `desktop/README.md`

**Step 1: Update usage docs**

- Document required `--dart-define` variables and local run command.

**Step 2: Run verification**

- Run: `flutter test`
- Run: `flutter analyze`
