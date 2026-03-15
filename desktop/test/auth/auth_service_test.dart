import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/auth/auth_models.dart';
import 'package:simsync/auth/auth_provider.dart';
import 'package:simsync/auth/auth_service.dart';
import 'package:simsync/auth/session_policy.dart';
import 'package:simsync/auth/session_store.dart';

void main() {
  test('DefaultAuthService signs in and persists stamped session', () async {
    final provider = _FakeAuthProvider(
      result: const AuthGrant(
        provider: 'github',
        accessToken: 'token',
        tokenType: 'bearer',
        scope: 'read:user',
        user: AuthUser(
          id: '1',
          login: 'octocat',
          name: 'Octo Cat',
          avatarUrl: 'https://example.com/avatar.png',
        ),
      ),
    );
    final store = _MemorySessionStore();
    final service = DefaultAuthService(
      provider: provider,
      store: store,
      policy: SessionPolicy(maxAge: const Duration(hours: 24)),
      nowProvider: () => DateTime.utc(2026, 3, 10, 9),
    );

    final session = await service.signIn();

    expect(provider.signInCalls, 1);
    expect(store.savedSession, isNotNull);
    expect(session.issuedAt, DateTime.utc(2026, 3, 10, 9));
    expect(session.expiresAt, DateTime.utc(2026, 3, 11, 9));
  });

  test('DefaultAuthService restores valid saved session', () async {
    final store = _MemorySessionStore(
      savedSession: AuthSession(
        provider: 'github',
        accessToken: 'token',
        tokenType: 'bearer',
        scope: 'read:user',
        issuedAt: DateTime.utc(2026, 3, 10, 9),
        expiresAt: DateTime.utc(2026, 3, 11, 9),
        user: const AuthUser(
          id: '1',
          login: 'octocat',
          name: null,
          avatarUrl: 'https://example.com/avatar.png',
        ),
      ),
    );
    final service = DefaultAuthService(
      provider: _FakeAuthProvider(
        result: const AuthGrant(
          provider: 'github',
          accessToken: 'unused',
          tokenType: 'bearer',
          scope: 'read:user',
          user: AuthUser(
            id: '1',
            login: 'octocat',
            name: null,
            avatarUrl: 'https://example.com/avatar.png',
          ),
        ),
      ),
      store: store,
      policy: SessionPolicy(maxAge: const Duration(hours: 24)),
      nowProvider: () => DateTime.utc(2026, 3, 10, 10),
    );

    final session = await service.restoreSession();

    expect(session, isNotNull);
    expect(store.clearCalls, 0);
  });

  test('DefaultAuthService clears expired session on restore', () async {
    final store = _MemorySessionStore(
      savedSession: AuthSession(
        provider: 'github',
        accessToken: 'token',
        tokenType: 'bearer',
        scope: 'read:user',
        issuedAt: DateTime.utc(2026, 3, 10, 9),
        expiresAt: DateTime.utc(2026, 3, 10, 10),
        user: const AuthUser(
          id: '1',
          login: 'octocat',
          name: null,
          avatarUrl: 'https://example.com/avatar.png',
        ),
      ),
    );
    final service = DefaultAuthService(
      provider: _FakeAuthProvider(
        result: const AuthGrant(
          provider: 'github',
          accessToken: 'unused',
          tokenType: 'bearer',
          scope: 'read:user',
          user: AuthUser(
            id: '1',
            login: 'octocat',
            name: null,
            avatarUrl: 'https://example.com/avatar.png',
          ),
        ),
      ),
      store: store,
      policy: SessionPolicy(maxAge: const Duration(hours: 24)),
      nowProvider: () => DateTime.utc(2026, 3, 10, 11),
    );

    final session = await service.restoreSession();

    expect(session, isNull);
    expect(store.clearCalls, 1);
  });

  test('DefaultAuthService logout clears persisted session', () async {
    final store = _MemorySessionStore();
    final service = DefaultAuthService(
      provider: _FakeAuthProvider(
        result: const AuthGrant(
          provider: 'github',
          accessToken: 'unused',
          tokenType: 'bearer',
          scope: 'read:user',
          user: AuthUser(
            id: '1',
            login: 'octocat',
            name: null,
            avatarUrl: 'https://example.com/avatar.png',
          ),
        ),
      ),
      store: store,
      policy: SessionPolicy(maxAge: const Duration(hours: 24)),
      nowProvider: DateTime.now,
    );

    await service.logout();

    expect(store.clearCalls, 1);
  });
}

class _FakeAuthProvider implements AuthProvider {
  _FakeAuthProvider({required this.result});

  final AuthGrant result;
  int signInCalls = 0;

  @override
  Future<AuthGrant> signIn() async {
    signInCalls += 1;
    return result;
  }
}

class _MemorySessionStore implements SessionStore {
  _MemorySessionStore({this.savedSession});

  AuthSession? savedSession;
  int clearCalls = 0;

  @override
  Future<void> clear() async {
    clearCalls += 1;
    savedSession = null;
  }

  @override
  Future<AuthSession?> read() async => savedSession;

  @override
  Future<void> write(AuthSession session) async {
    savedSession = session;
  }
}
