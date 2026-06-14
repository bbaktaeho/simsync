import 'auth_models.dart';
import 'auth_provider.dart';
import 'session_policy.dart';
import 'session_store.dart';

abstract class AuthService {
  Future<AuthSession?> restoreSession();
  Future<AuthSession> signIn();
  Future<void> logout();
  Future<bool> validateSession(AuthSession session);
}

class DefaultAuthService implements AuthService {
  DefaultAuthService({
    required AuthProvider provider,
    required SessionStore store,
    required SessionPolicy policy,
    required DateTime Function() nowProvider,
  })  : _provider = provider,
        _store = store,
        _policy = policy,
        _nowProvider = nowProvider;

  final AuthProvider _provider;
  final SessionStore _store;
  final SessionPolicy _policy;
  final DateTime Function() _nowProvider;

  @override
  Future<void> logout() {
    return _store.clear();
  }

  @override
  Future<AuthSession?> restoreSession() async {
    final session = await _store.read();
    if (session == null) {
      return null;
    }

    final isValid = await validateSession(session);
    if (!isValid) {
      return null;
    }

    return session;
  }

  @override
  Future<AuthSession> signIn() async {
    final grant = await _provider.signIn();
    final issuedAt = _nowProvider();
    final session = AuthSession(
      provider: grant.provider,
      accessToken: grant.accessToken,
      tokenType: grant.tokenType,
      scope: grant.scope,
      issuedAt: issuedAt,
      expiresAt: _policy.calculateExpiry(issuedAt),
      user: grant.user,
    );
    await _store.write(session);
    return session;
  }

  @override
  Future<bool> validateSession(AuthSession session) async {
    if (_policy.isExpired(expiresAt: session.expiresAt, now: _nowProvider())) {
      await _store.clear();
      return false;
    }

    final result = await _provider.validateAccessToken(session.accessToken);
    if (result == SessionValidationResult.invalid) {
      await _store.clear();
      return false;
    }

    return true;
  }
}
