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
    Duration? callbackTimeout,
    String Function(int length)? randomStringGenerator,
  })  : _config = config,
        _httpClient = httpClient ?? http.Client(),
        _browserLauncher = browserLauncher ?? _defaultBrowserLauncher,
        _callbackTimeout = callbackTimeout ?? const Duration(minutes: 2),
        _randomStringGenerator =
            randomStringGenerator ?? _defaultRandomStringGenerator;

  static const String _redirectUri = 'simsync://callback';

  final GitHubOAuthConfig _config;
  final http.Client _httpClient;
  final BrowserLauncher _browserLauncher;
  final Duration _callbackTimeout;
  final String Function(int length) _randomStringGenerator;

  Completer<Uri>? _callbackCompleter;

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
    final redirectUri = Uri.parse(_redirectUri);

    _callbackCompleter = Completer<Uri>();

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

      final callbackUri = await _callbackCompleter!.future.timeout(
        _callbackTimeout,
        onTimeout: () {
          throw const AuthCancelledException(
            'GitHub login timed out before the callback was received.',
          );
        },
      );

      final error = callbackUri.queryParameters['error'];
      if (error != null) {
        throw AuthException('GitHub returned error: $error');
      }

      final callbackState = callbackUri.queryParameters['state'];
      if (callbackState != state) {
        throw const AuthException('GitHub OAuth state validation failed.');
      }

      final code = callbackUri.queryParameters['code'];
      if (code == null || code.isEmpty) {
        throw const AuthException('GitHub OAuth callback did not include a code.');
      }

      final token = await _exchangeCodeForToken(
        code: code,
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
      _callbackCompleter = null;
    }
  }

  /// Called by the app when the custom URL scheme redirect is received.
  /// Pass the full callback URI (e.g. simsync://callback?code=...&state=...).
  void handleRedirectUri(Uri uri) {
    final completer = _callbackCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(uri);
    }
  }

  /// Cancel any pending sign-in flow.
  void cancelPendingSignIn() {
    final completer = _callbackCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(
        const AuthCancelledException('Sign-in was cancelled.'),
      );
    }
  }

  @override
  Future<SessionValidationResult> validateAccessToken(String accessToken) async {
    try {
      final response = await _getUserProfileResponse(accessToken);
      if (response.statusCode == HttpStatus.ok) {
        return SessionValidationResult.valid;
      }
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        return SessionValidationResult.invalid;
      }
      return SessionValidationResult.unknown;
    } on http.ClientException {
      return SessionValidationResult.unknown;
    } on SocketException {
      return SessionValidationResult.unknown;
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
    final response = await _getUserProfileResponse(token.accessToken);

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

  Future<http.Response> _getUserProfileResponse(String accessToken) {
    return _httpClient.get(
      Uri.https('api.github.com', '/user'),
      headers: {
        'Accept': 'application/vnd.github+json',
        'Authorization': 'Bearer $accessToken',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );
  }

  static Future<bool> _defaultBrowserLauncher(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
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
