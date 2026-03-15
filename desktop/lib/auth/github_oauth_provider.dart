import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'auth_models.dart';
import 'auth_provider.dart';

typedef BrowserLauncher = Future<bool> Function(Uri uri);
typedef LoopbackServerFactory = Future<HttpServer> Function();

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthConfigurationException extends AuthException {
  const AuthConfigurationException(super.message);
}

class AuthCancelledException extends AuthException {
  const AuthCancelledException(super.message);
}

class GitHubOAuthConfig {
  const GitHubOAuthConfig({
    required this.clientId,
    required this.clientSecret,
  });

  final String clientId;
  final String clientSecret;

  bool get isConfigured {
    return clientId.trim().isNotEmpty && clientSecret.trim().isNotEmpty;
  }
}

class GitHubOAuthProvider implements AuthProvider {
  GitHubOAuthProvider({
    required GitHubOAuthConfig config,
    http.Client? httpClient,
    BrowserLauncher? browserLauncher,
    LoopbackServerFactory? loopbackServerFactory,
    Duration? callbackTimeout,
    String Function(int length)? randomStringGenerator,
  })  : _config = config,
        _httpClient = httpClient ?? http.Client(),
        _browserLauncher = browserLauncher ?? _defaultBrowserLauncher,
        _loopbackServerFactory = loopbackServerFactory ?? _defaultLoopbackServer,
        _callbackTimeout = callbackTimeout ?? const Duration(minutes: 2),
        _randomStringGenerator =
            randomStringGenerator ?? _defaultRandomStringGenerator;

  final GitHubOAuthConfig _config;
  final http.Client _httpClient;
  final BrowserLauncher _browserLauncher;
  final LoopbackServerFactory _loopbackServerFactory;
  final Duration _callbackTimeout;
  final String Function(int length) _randomStringGenerator;

  @override
  Future<AuthGrant> signIn() async {
    if (!_config.isConfigured) {
      throw const AuthConfigurationException(
        'GitHub OAuth is not configured. Set SIMSYNC_GITHUB_CLIENT_ID and SIMSYNC_GITHUB_CLIENT_SECRET.',
      );
    }

    final state = _randomStringGenerator(32);
    final codeVerifier = _randomStringGenerator(64);
    final codeChallenge = createCodeChallenge(codeVerifier);
    final server = await _loopbackServerFactory();
    final redirectUri = Uri.parse(
      'http://127.0.0.1:${server.port}/callback',
    );

    try {
      final authorizationUri = buildAuthorizationUri(
        redirectUri: redirectUri,
        state: state,
        codeChallenge: codeChallenge,
      );
      final launched = await _browserLauncher(authorizationUri);
      if (!launched) {
        throw const AuthException('Could not open the browser for GitHub login.');
      }

      final callback = await _waitForCallback(
        server: server,
        expectedState: state,
      );
      final token = await _exchangeCodeForToken(
        code: callback.code,
        redirectUri: redirectUri,
        codeVerifier: codeVerifier,
      );
      final user = await _fetchUser(token);

      return AuthGrant(
        provider: 'github',
        accessToken: token.accessToken,
        tokenType: token.tokenType,
        scope: token.scope,
        user: user,
      );
    } finally {
      await server.close(force: true);
    }
  }

  Uri buildAuthorizationUri({
    required Uri redirectUri,
    required String state,
    required String codeChallenge,
  }) {
    return Uri.https(
      'github.com',
      '/login/oauth/authorize',
      {
        'client_id': _config.clientId,
        'redirect_uri': redirectUri.toString(),
        'scope': 'read:user user:email repo',
        'state': state,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
      },
    );
  }

  static String createCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes).bytes;
    return base64UrlEncode(digest).replaceAll('=', '');
  }

  Future<_GitHubTokenResponse> _exchangeCodeForToken({
    required String code,
    required Uri redirectUri,
    required String codeVerifier,
  }) async {
    final response = await _httpClient.post(
      Uri.https('github.com', '/login/oauth/access_token'),
      headers: const {
        'Accept': 'application/json',
      },
      body: {
        'client_id': _config.clientId,
        'client_secret': _config.clientSecret,
        'code': code,
        'redirect_uri': redirectUri.toString(),
        'code_verifier': codeVerifier,
      },
    );

    if (response.statusCode != HttpStatus.ok) {
      throw AuthException(
        'GitHub token exchange failed with status ${response.statusCode}.',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['error'] case final String error) {
      throw AuthException('GitHub token exchange failed: $error');
    }

    return _GitHubTokenResponse(
      accessToken: json['access_token'] as String,
      tokenType: (json['token_type'] as String?) ?? 'bearer',
      scope: (json['scope'] as String?) ?? '',
    );
  }

  Future<AuthUser> _fetchUser(_GitHubTokenResponse token) async {
    final response = await _httpClient.get(
      Uri.https('api.github.com', '/user'),
      headers: {
        'Accept': 'application/vnd.github+json',
        'Authorization': 'Bearer ${token.accessToken}',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );

    if (response.statusCode != HttpStatus.ok) {
      throw AuthException(
        'GitHub user profile request failed with status ${response.statusCode}.',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return AuthUser(
      id: (json['id'] as num).toString(),
      login: json['login'] as String,
      name: json['name'] as String?,
      avatarUrl: json['avatar_url'] as String,
    );
  }

  Future<_OAuthCallback> _waitForCallback({
    required HttpServer server,
    required String expectedState,
  }) async {
    final completer = Completer<_OAuthCallback>();
    late final StreamSubscription<HttpRequest> subscription;

    subscription = server.listen((request) async {
      if (request.uri.path != '/callback') {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not found');
        await request.response.close();
        return;
      }

      try {
        final error = request.uri.queryParameters['error'];
        if (error != null) {
          request.response
            ..statusCode = HttpStatus.badRequest
            ..headers.contentType = ContentType.html
            ..write(_htmlResponse('GitHub login failed. You can close this window.'));
          await request.response.close();
          if (!completer.isCompleted) {
            completer.completeError(AuthException('GitHub returned error: $error'));
          }
          return;
        }

        final state = request.uri.queryParameters['state'];
        if (state != expectedState) {
          request.response
            ..statusCode = HttpStatus.badRequest
            ..headers.contentType = ContentType.html
            ..write(_htmlResponse('State mismatch. You can close this window.'));
          await request.response.close();
          if (!completer.isCompleted) {
            completer.completeError(
              const AuthException('GitHub OAuth state validation failed.'),
            );
          }
          return;
        }

        final code = request.uri.queryParameters['code'];
        if (code == null || code.isEmpty) {
          request.response
            ..statusCode = HttpStatus.badRequest
            ..headers.contentType = ContentType.html
            ..write(_htmlResponse('Authorization code missing. You can close this window.'));
          await request.response.close();
          if (!completer.isCompleted) {
            completer.completeError(
              const AuthException('GitHub OAuth callback did not include a code.'),
            );
          }
          return;
        }

        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(_htmlResponse('GitHub login complete. Return to SimSync.'));
        await request.response.close();

        if (!completer.isCompleted) {
          completer.complete(_OAuthCallback(code: code));
        }
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    });

    try {
      return await completer.future.timeout(
        _callbackTimeout,
        onTimeout: () {
          throw const AuthCancelledException(
            'GitHub login timed out before the callback was received.',
          );
        },
      );
    } finally {
      await subscription.cancel();
    }
  }

  String _htmlResponse(String message) {
    return '''
<!DOCTYPE html>
<html>
  <body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 24px;">
    <h2>$message</h2>
  </body>
</html>
''';
  }

  static Future<bool> _defaultBrowserLauncher(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<HttpServer> _defaultLoopbackServer() {
    return HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  }

  static String _defaultRandomStringGenerator(int length) {
    const characters =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => characters[random.nextInt(characters.length)],
    ).join();
  }
}

class _OAuthCallback {
  const _OAuthCallback({required this.code});

  final String code;
}

class _GitHubTokenResponse {
  const _GitHubTokenResponse({
    required this.accessToken,
    required this.tokenType,
    required this.scope,
  });

  final String accessToken;
  final String tokenType;
  final String scope;
}
