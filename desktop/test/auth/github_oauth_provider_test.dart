import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simsync/auth/auth_provider.dart';
import 'package:simsync/auth/github_oauth_provider.dart';

const _config = GitHubOAuthConfig(clientId: 'client-id');

http.Response _json(Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), 200);

Map<String, dynamic> _deviceCodeBody({int expiresIn = 900, int interval = 5}) {
  return {
    'device_code': 'device-code-123',
    'user_code': 'ABCD-1234',
    'verification_uri': 'https://github.com/login/device',
    'expires_in': expiresIn,
    'interval': interval,
  };
}

Map<String, dynamic> _tokenSuccessBody() {
  return {
    'access_token': 'gho_token',
    'token_type': 'bearer',
    'scope': 'read:user,repo',
  };
}

Map<String, dynamic> _userBody() {
  return {
    'id': 42,
    'login': 'octocat',
    'name': 'Octo Cat',
    'avatar_url': 'https://example.com/a.png',
  };
}

/// Provider with instant delays and a scripted sequence of token-poll bodies.
/// Records every request so tests can assert on what was sent.
({GitHubOAuthProvider provider, List<http.Request> requests, List<Duration> delays})
    _buildProvider(List<Map<String, dynamic>> tokenPollBodies) {
  final requests = <http.Request>[];
  final delays = <Duration>[];
  var polls = 0;
  final provider = GitHubOAuthProvider(
    config: _config,
    delay: (duration) async => delays.add(duration),
    httpClient: MockClient((request) async {
      requests.add(request);
      switch (request.url.path) {
        case '/login/device/code':
          return _json(_deviceCodeBody());
        case '/login/oauth/access_token':
          return _json(tokenPollBodies[polls++]);
        case '/user':
          return _json(_userBody());
      }
      fail('Unexpected request: ${request.url}');
    }),
  );
  return (provider: provider, requests: requests, delays: delays);
}

void main() {
  test('GitHubOAuthConfig requires only a client id', () {
    expect(const GitHubOAuthConfig(clientId: '').isConfigured, isFalse);
    expect(const GitHubOAuthConfig(clientId: ' ').isConfigured, isFalse);
    expect(const GitHubOAuthConfig(clientId: 'id').isConfigured, isTrue);
  });

  test('signIn throws AuthConfigurationException without a client id', () {
    final provider = GitHubOAuthProvider(
      config: const GitHubOAuthConfig(clientId: ''),
      httpClient: MockClient((_) async => fail('must not hit the network')),
    );

    expect(provider.signIn(), throwsA(isA<AuthConfigurationException>()));
  });

  test('signIn completes the device flow and never sends a client secret',
      () async {
    final t = _buildProvider([
      {'error': 'authorization_pending'},
      _tokenSuccessBody(),
    ]);

    DeviceAuthorization? prompt;
    final grant =
        await t.provider.signIn(onAuthorizationPrompt: (a) => prompt = a);

    // The UI prompt carries the code the user must enter.
    expect(prompt, isNotNull);
    expect(prompt!.userCode, 'ABCD-1234');
    expect(prompt!.verificationUri.toString(),
        'https://github.com/login/device');
    expect(prompt!.expiresAt.isAfter(DateTime.now()), isTrue);

    expect(grant.provider, 'github');
    expect(grant.accessToken, 'gho_token');
    expect(grant.user.login, 'octocat');

    // Device code request carries the reduced scope.
    final deviceReq =
        t.requests.firstWhere((r) => r.url.path == '/login/device/code');
    expect(deviceReq.bodyFields['scope'], 'read:user repo');

    // Poll uses the device grant; NO request anywhere includes a secret.
    final pollReq =
        t.requests.firstWhere((r) => r.url.path == '/login/oauth/access_token');
    expect(pollReq.bodyFields['grant_type'],
        'urn:ietf:params:oauth:grant-type:device_code');
    expect(pollReq.bodyFields['device_code'], 'device-code-123');
    for (final r in t.requests) {
      expect(r.body.contains('client_secret'), isFalse,
          reason: 'device flow must never send a client secret');
    }

    // One wait per poll attempt, at the server-provided interval.
    expect(t.delays, hasLength(2));
    expect(t.delays.first, const Duration(seconds: 5));
  });

  test('transient poll failures (5xx, network, non-JSON) keep polling',
      () async {
    // The device code is valid for ~15 min; a blip on one poll must not abort
    // the whole sign-in. Scripts a 502, then a network drop, then a garbage
    // body, then success — the flow should ride through all three.
    var attempt = 0;
    final delays = <Duration>[];
    final provider = GitHubOAuthProvider(
      config: _config,
      delay: (d) async => delays.add(d),
      httpClient: MockClient((request) async {
        if (request.url.path == '/login/device/code') {
          return _json(_deviceCodeBody());
        }
        if (request.url.path == '/user') return _json(_userBody());
        // token poll
        switch (attempt++) {
          case 0:
            return http.Response('Bad Gateway', 502);
          case 1:
            throw http.ClientException('Connection reset by peer');
          case 2:
            return http.Response('<html>not json</html>', 200);
          default:
            return _json(_tokenSuccessBody());
        }
      }),
    );

    final grant = await provider.signIn();

    expect(grant.accessToken, 'gho_token');
    expect(attempt, 4, reason: 'three transient failures then success');
    // One wait before each of the four poll attempts.
    expect(delays, hasLength(4));
  });

  test('slow_down increases the polling interval', () async {
    final t = _buildProvider([
      {'error': 'slow_down'},
      {'error': 'authorization_pending'},
      _tokenSuccessBody(),
    ]);

    await t.provider.signIn();

    expect(t.delays, [
      const Duration(seconds: 5),
      const Duration(seconds: 10),
      const Duration(seconds: 10),
    ]);
  });

  test('expired_token surfaces as a retryable AuthException', () {
    final t = _buildProvider([
      {'error': 'expired_token'},
    ]);

    expect(
      t.provider.signIn(),
      throwsA(isA<AuthException>()
          .having((e) => e.message, 'message', contains('expired'))),
    );
  });

  test('access_denied surfaces as AuthCancelledException', () {
    final t = _buildProvider([
      {'error': 'access_denied'},
    ]);

    expect(t.provider.signIn(), throwsA(isA<AuthCancelledException>()));
  });

  test('cancelSignIn aborts a pending poll wait', () async {
    final provider = GitHubOAuthProvider(
      config: _config,
      // Delay never completes on its own: only cancelSignIn can wake it.
      delay: (_) => Completer<void>().future,
      httpClient: MockClient((request) async {
        if (request.url.path == '/login/device/code') {
          return _json(_deviceCodeBody());
        }
        fail('poll must not run after cancellation');
      }),
    );

    final signIn = provider.signIn();
    // Let the device-code request complete and the poll wait begin.
    await Future<void>.delayed(Duration.zero);
    provider.cancelSignIn();

    await expectLater(signIn, throwsA(isA<AuthCancelledException>()));
  });

  test('validateAccessToken returns invalid on 401', () async {
    final provider = GitHubOAuthProvider(
      config: _config,
      httpClient: MockClient((request) async {
        expect(request.url.toString(), 'https://api.github.com/user');
        expect(request.headers['Authorization'], 'Bearer expired-token');
        return http.Response('Unauthorized', 401);
      }),
    );

    final result = await provider.validateAccessToken('expired-token');

    expect(result, SessionValidationResult.invalid);
  });

  test('validateAccessToken returns unknown on non-auth server error',
      () async {
    final provider = GitHubOAuthProvider(
      config: _config,
      httpClient: MockClient((_) async => http.Response('Server Error', 500)),
    );

    final result = await provider.validateAccessToken('token');

    expect(result, SessionValidationResult.unknown);
  });
}
