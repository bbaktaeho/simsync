import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simsync/auth/auth_provider.dart';
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

  test('validateAccessToken returns invalid on 401', () async {
    const config = GitHubOAuthConfig(
      clientId: 'client-id',
      clientSecret: 'client-secret',
    );
    final provider = GitHubOAuthProvider(
      config: config,
      httpClient: MockClient((request) async {
        expect(request.url.toString(), 'https://api.github.com/user');
        expect(request.headers['Authorization'], 'Bearer expired-token');
        return http.Response('Unauthorized', 401);
      }),
    );

    final result = await provider.validateAccessToken('expired-token');

    expect(result, SessionValidationResult.invalid);
  });

  test('validateAccessToken returns unknown on non-auth server error', () async {
    const config = GitHubOAuthConfig(
      clientId: 'client-id',
      clientSecret: 'client-secret',
    );
    final provider = GitHubOAuthProvider(
      config: config,
      httpClient: MockClient((_) async => http.Response('Server Error', 500)),
    );

    final result = await provider.validateAccessToken('token');

    expect(result, SessionValidationResult.unknown);
  });
}
