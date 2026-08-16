import 'package:flutter_test/flutter_test.dart';
import 'package:simsync_mobile/auth/auth_models.dart';

void main() {
  test('AuthSession serializes and deserializes nested auth data', () {
    final session = AuthSession(
      provider: 'github',
      accessToken: 'token-123',
      tokenType: 'bearer',
      scope: 'read:user user:email',
      issuedAt: DateTime.utc(2026, 3, 10, 1),
      expiresAt: DateTime.utc(2026, 3, 11, 1),
      user: const AuthUser(
        id: '42',
        login: 'octocat',
        name: 'The Octocat',
        avatarUrl: 'https://avatars.githubusercontent.com/u/42',
      ),
    );

    final json = session.toJson();
    final restored = AuthSession.fromJson(json);

    expect(restored.provider, 'github');
    expect(restored.accessToken, 'token-123');
    expect(restored.tokenType, 'bearer');
    expect(restored.scope, 'read:user user:email');
    expect(restored.issuedAt, DateTime.utc(2026, 3, 10, 1));
    expect(restored.expiresAt, DateTime.utc(2026, 3, 11, 1));
    expect(restored.user.login, 'octocat');
    expect(restored.user.name, 'The Octocat');
  });

  test('AuthGrant serializes provider and user payload', () {
    const grant = AuthGrant(
      provider: 'github',
      accessToken: 'grant-token',
      tokenType: 'bearer',
      scope: 'read:user',
      user: AuthUser(
        id: '7',
        login: 'hubber',
        name: null,
        avatarUrl: 'https://example.com/avatar.png',
      ),
    );

    final restored = AuthGrant.fromJson(grant.toJson());

    expect(restored.provider, 'github');
    expect(restored.user.id, '7');
    expect(restored.user.name, isNull);
  });
}
