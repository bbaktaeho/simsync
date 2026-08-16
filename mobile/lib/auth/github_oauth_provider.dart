import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'auth_models.dart';
import 'auth_provider.dart';

/// Waits [duration]; injectable so tests can skip real delays.
typedef DelayFunction = Future<void> Function(Duration duration);

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
  const GitHubOAuthConfig({required this.clientId});

  /// The OAuth App's client id. Public by design (it ships in released
  /// binaries), unlike a client secret — which the device flow never needs.
  final String clientId;

  bool get isConfigured => clientId.trim().isNotEmpty;
}

/// GitHub sign-in via the OAuth device flow.
///
/// The device flow is the no-secret path GitHub provides for apps that are
/// distributed to users (CLI/desktop): only the public client id is used, so
/// nothing sensitive ships in the binary. GitHub does not support PKCE as a
/// secret replacement, which rules out the redirect (web) flow for releases.
///
/// Flow: request a device/user code pair → surface the user code to the UI
/// ([DeviceAuthorizationPrompt]) → poll the token endpoint at the
/// server-mandated interval until the user approves on github.com/login/device
/// (or denies / the code expires / [cancelSignIn] is called).
class GitHubOAuthProvider implements AuthProvider {
  GitHubOAuthProvider({
    required GitHubOAuthConfig config,
    http.Client? httpClient,
    DelayFunction? delay,
  })  : _config = config,
        _httpClient = httpClient ?? http.Client(),
        _delay = delay ?? _defaultDelay;

  static const String _scope = 'read:user repo';
  static const String _deviceGrantType =
      'urn:ietf:params:oauth:grant-type:device_code';

  final GitHubOAuthConfig _config;
  final http.Client _httpClient;
  final DelayFunction _delay;

  /// Completes when [cancelSignIn] is called, waking the poll loop early.
  Completer<void>? _cancelRequested;

  @override
  Future<AuthGrant> signIn({
    DeviceAuthorizationPrompt? onAuthorizationPrompt,
  }) async {
    if (!_config.isConfigured) {
      throw const AuthConfigurationException(
        'GitHub OAuth is not configured. Set SIMSYNC_GITHUB_CLIENT_ID.',
      );
    }

    final cancel = Completer<void>();
    _cancelRequested = cancel;
    try {
      final device = await _requestDeviceCode();
      onAuthorizationPrompt?.call(
        DeviceAuthorization(
          userCode: device.userCode,
          verificationUri: device.verificationUri,
          expiresAt: device.expiresAt,
        ),
      );
      final token = await _pollForToken(device, cancel);
      final user = await _fetchUser(token.accessToken);
      return AuthGrant(
        provider: 'github',
        accessToken: token.accessToken,
        tokenType: token.tokenType,
        scope: token.scope,
        user: user,
      );
    } finally {
      _cancelRequested = null;
    }
  }

  @override
  void cancelSignIn() {
    final cancel = _cancelRequested;
    if (cancel != null && !cancel.isCompleted) {
      cancel.complete();
    }
  }

  @override
  Future<SessionValidationResult> validateAccessToken(
      String accessToken) async {
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

  Future<_DeviceCodeResponse> _requestDeviceCode() async {
    final response = await _httpClient.post(
      Uri.https('github.com', '/login/device/code'),
      headers: const {'Accept': 'application/json'},
      body: {
        'client_id': _config.clientId,
        'scope': _scope,
      },
    );

    if (response.statusCode != HttpStatus.ok) {
      throw AuthException(
        'GitHub device code request failed with status ${response.statusCode}.',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['error'] case final String error) {
      throw AuthException('GitHub device code request failed: $error');
    }

    return _DeviceCodeResponse(
      deviceCode: json['device_code'] as String,
      userCode: json['user_code'] as String,
      verificationUri: Uri.parse(json['verification_uri'] as String),
      expiresAt: DateTime.now()
          .add(Duration(seconds: (json['expires_in'] as num).toInt())),
      interval: Duration(
        // GitHub's documented minimum is 5s; never poll faster even if the
        // response says otherwise.
        seconds: ((json['interval'] as num?)?.toInt() ?? 5).clamp(5, 60),
      ),
    );
  }

  Future<_GitHubTokenResponse> _pollForToken(
    _DeviceCodeResponse device,
    Completer<void> cancel,
  ) async {
    var interval = device.interval;

    while (true) {
      // Wait one interval, but wake immediately on cancelSignIn().
      await Future.any<void>([_delay(interval), cancel.future]);
      if (cancel.isCompleted) {
        throw const AuthCancelledException('GitHub login was cancelled.');
      }
      if (DateTime.now().isAfter(device.expiresAt)) {
        throw const AuthException(
          'The GitHub device code expired before authorization. Try again.',
        );
      }

      // The device code stays valid for ~15 min, so a single failed poll —
      // a transient network drop or a GitHub 5xx/gateway hiccup — must not
      // kill the whole sign-in. Skip this attempt and poll again next
      // interval (until the code actually expires above). Only definitive
      // OAuth errors in the JSON body (below) end the flow.
      final http.Response response;
      try {
        response = await _httpClient.post(
          Uri.https('github.com', '/login/oauth/access_token'),
          headers: const {'Accept': 'application/json'},
          body: {
            'client_id': _config.clientId,
            'device_code': device.deviceCode,
            'grant_type': _deviceGrantType,
          },
        );
      } on http.ClientException {
        continue;
      } on SocketException {
        continue;
      }

      if (response.statusCode != HttpStatus.ok) {
        continue;
      }

      final Map<String, dynamic> json;
      try {
        json = jsonDecode(response.body) as Map<String, dynamic>;
      } on FormatException {
        // A proxy/error page instead of JSON: transient, keep polling.
        continue;
      }
      switch (json['error']) {
        case 'authorization_pending':
          continue;
        case 'slow_down':
          // Server-mandated backoff: +5s (or its explicit new interval).
          final next = (json['interval'] as num?)?.toInt();
          interval = next != null
              ? Duration(seconds: next.clamp(5, 60))
              : interval + const Duration(seconds: 5);
          continue;
        case 'expired_token':
          throw const AuthException(
            'The GitHub device code expired before authorization. Try again.',
          );
        case 'access_denied':
          throw const AuthCancelledException(
            'GitHub login was denied on github.com.',
          );
        case final String error:
          throw AuthException('GitHub token polling failed: $error');
      }

      return _GitHubTokenResponse(
        accessToken: json['access_token'] as String,
        tokenType: (json['token_type'] as String?) ?? 'bearer',
        scope: (json['scope'] as String?) ?? '',
      );
    }
  }

  Future<AuthUser> _fetchUser(String accessToken) async {
    final response = await _getUserProfileResponse(accessToken);

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

  static Future<void> _defaultDelay(Duration duration) {
    return Future<void>.delayed(duration);
  }
}

class _DeviceCodeResponse {
  const _DeviceCodeResponse({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresAt,
    required this.interval,
  });

  final String deviceCode;
  final String userCode;
  final Uri verificationUri;
  final DateTime expiresAt;
  final Duration interval;
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
