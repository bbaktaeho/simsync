import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/auth/github_oauth_provider.dart';

void main() {
  test('GitHubOAuthConfig reports missing credentials', () {
    const config = GitHubOAuthConfig(
      clientId: '',
      clientSecret: '',
    );

    expect(config.isConfigured, isFalse);
  });

  test('buildAuthorizationUri includes PKCE and redirect data', () {
    const config = GitHubOAuthConfig(
      clientId: 'client-id',
      clientSecret: 'client-secret',
    );
    final provider = GitHubOAuthProvider(config: config);
    final uri = provider.buildAuthorizationUri(
      redirectUri: Uri.parse('http://127.0.0.1:8080/callback'),
      state: 'state-123',
      codeChallenge: 'challenge-456',
    );

    expect(uri.toString(), startsWith('https://github.com/login/oauth/authorize'));
    expect(uri.queryParameters['client_id'], 'client-id');
    expect(uri.queryParameters['redirect_uri'], 'http://127.0.0.1:8080/callback');
    expect(uri.queryParameters['state'], 'state-123');
    expect(uri.queryParameters['code_challenge'], 'challenge-456');
    expect(uri.queryParameters['code_challenge_method'], 'S256');
  });

  test('createCodeChallenge returns RFC 7636 compatible base64url value', () {
    const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';

    final challenge = GitHubOAuthProvider.createCodeChallenge(verifier);

    expect(challenge, 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
  });
}
