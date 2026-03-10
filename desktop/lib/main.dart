import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'auth/auth_service.dart';
import 'auth/github_oauth_provider.dart';
import 'auth/session_policy.dart';
import 'auth/session_store.dart';
import 'screens/document_screen.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(SimSyncApp(authService: createDefaultAuthService()));
}

class SimSyncApp extends StatefulWidget {
  const SimSyncApp({
    super.key,
    required this.authService,
  });

  final AuthService authService;

  @override
  State<SimSyncApp> createState() => SimSyncAppState();

  /// Allow descendants to toggle theme mode.
  static SimSyncAppState of(BuildContext context) =>
      context.findAncestorStateOfType<SimSyncAppState>()!;
}

class SimSyncAppState extends State<SimSyncApp> {
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  void toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SimSync',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: _themeMode,
      home: _AppShell(authService: widget.authService),
    );
  }
}

/// Root shell that manages auth state (login ↔ document screen).
class _AppShell extends StatefulWidget {
  const _AppShell({required this.authService});

  final AuthService authService;

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  _AuthStatus _status = _AuthStatus.restoring;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _handleLogin() async {
    await widget.authService.signIn();
    if (!mounted) return;
    setState(() => _status = _AuthStatus.authenticated);
  }

  Future<void> _handleLogout() async {
    await widget.authService.logout();
    if (!mounted) return;
    setState(() => _status = _AuthStatus.unauthenticated);
  }

  Future<void> _restoreSession() async {
    final session = await widget.authService.restoreSession();
    if (!mounted) return;
    setState(() {
      _status =
          session == null ? _AuthStatus.unauthenticated : _AuthStatus.authenticated;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_status == _AuthStatus.restoring) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_status == _AuthStatus.authenticated) {
      return DocumentScreen(
        onLogout: _handleLogout,
      );
    }
    return LoginScreen(
      onGitHubLogin: _handleLogin,
    );
  }
}

AuthService createDefaultAuthService() {
  const config = GitHubOAuthConfig(
    clientId: String.fromEnvironment('SIMSYNC_GITHUB_CLIENT_ID'),
    clientSecret: String.fromEnvironment('SIMSYNC_GITHUB_CLIENT_SECRET'),
  );

  return DefaultAuthService(
    provider: GitHubOAuthProvider(
      config: config,
      httpClient: http.Client(),
    ),
    store: FileSessionStore(
      directoryProvider: getApplicationSupportDirectory,
    ),
    policy: const SessionPolicy(maxAge: Duration(hours: 24)),
    nowProvider: DateTime.now,
  );
}

enum _AuthStatus {
  restoring,
  authenticated,
  unauthenticated,
}
