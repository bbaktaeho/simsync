import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'auth/auth_models.dart';
import 'auth/auth_service.dart';
import 'auth/github_oauth_provider.dart';
import 'auth/session_policy.dart';
import 'auth/session_store.dart';
import 'screens/document_screen.dart';
import 'screens/login_screen.dart';
import 'screens/repo_selection_screen.dart';
import 'services/note_service.dart';
import 'storage/github/github_api_client.dart';
import 'storage/github/github_note_storage.dart';
import 'storage/github/github_storage_config.dart';
import 'storage/github/github_sync_engine.dart';
import 'storage/github/repo_cache.dart';
import 'storage/note_storage.dart';
import 'theme/app_theme.dart';

/// Resolved storage layer after authentication.
class StorageBundle {
  final NoteStorage storage;
  final NoteService noteService;
  final GitHubSyncEngine? syncEngine;

  const StorageBundle({
    required this.storage,
    required this.noteService,
    this.syncEngine,
  });
}

/// Signature for a function that creates a [StorageBundle] from a token.
///
/// The optional [onRemoteChanged] callback is invoked by the sync engine
/// when a new remote commit is detected, allowing the caller to refresh the UI.
typedef StorageFactory = Future<StorageBundle> Function(
  String accessToken, {
  Future<void> Function()? onRemoteChanged,
});

void main() {
  runApp(SimSyncApp(authService: createDefaultAuthService()));
}

class SimSyncApp extends StatefulWidget {
  const SimSyncApp({
    super.key,
    required this.authService,
    this.storageFactory,
  });

  final AuthService authService;

  /// Optional override for storage initialization (useful for testing).
  /// When null, the default factory reads [GitHubStorageConfig] from disk.
  final StorageFactory? storageFactory;

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
      home: _AppShell(
        authService: widget.authService,
        storageFactory: widget.storageFactory ?? _defaultStorageFactory,
      ),
    );
  }
}

/// Root shell that manages auth state (login <-> document screen).
class _AppShell extends StatefulWidget {
  const _AppShell({
    required this.authService,
    required this.storageFactory,
  });

  final AuthService authService;
  final StorageFactory storageFactory;

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  _AuthStatus _status = _AuthStatus.restoring;

  // Session stored after login, needed for repo selection screen.
  AuthSession? _session;

  // Storage layer (resolved after auth succeeds).
  StorageBundle? _bundle;

  /// Notifier incremented when the sync engine detects remote changes.
  /// DocumentScreen listens to this to reload notes.
  final ValueNotifier<int> _refreshSignal = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  @override
  void dispose() {
    _bundle?.syncEngine?.dispose();
    _refreshSignal.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final session = await widget.authService.signIn();
    if (!mounted) return;
    _session = session;
    setState(() => _status = _AuthStatus.repoSelection);
  }

  Future<void> _handleLogout() async {
    _bundle?.syncEngine?.dispose();
    _bundle = null;
    await widget.authService.logout();
    if (!mounted) return;
    setState(() => _status = _AuthStatus.unauthenticated);
  }

  Future<void> _restoreSession() async {
    final session = await widget.authService.restoreSession();
    if (!mounted) return;
    if (session == null) {
      setState(() => _status = _AuthStatus.unauthenticated);
      return;
    }

    // Check if a GitHub storage config already exists on disk.
    GitHubStorageConfig? config;
    try {
      config = await GitHubStorageConfig.load();
    } catch (_) {
      // Config missing or unreadable.
    }

    if (!mounted) return;

    if (config != null) {
      // Config exists — go straight to authenticated.
      _session = session;
      _bundle = await widget.storageFactory(
        session.accessToken,
        onRemoteChanged: _onRemoteChanged,
      );
      _bundle?.syncEngine?.start();
      if (!mounted) return;
      setState(() => _status = _AuthStatus.authenticated);
    } else {
      // No config — let user pick a repo.
      _session = session;
      setState(() => _status = _AuthStatus.repoSelection);
    }
  }

  Future<void> _handleRepoSelected(RepoEntry entry) async {
    // Persist the selected repo as the active GitHub storage config.
    final config = GitHubStorageConfig(
      owner: entry.owner,
      repo: entry.repo,
      branch: entry.branch,
    );
    await config.save();

    // Create storage bundle using the stored session token.
    _bundle = await widget.storageFactory(
      _session!.accessToken,
      onRemoteChanged: _onRemoteChanged,
    );
    _bundle?.syncEngine?.start();
    if (!mounted) return;
    setState(() => _status = _AuthStatus.authenticated);
  }

  Future<void> _onRemoteChanged() async {
    _refreshSignal.value++;
  }

  @override
  Widget build(BuildContext context) {
    if (_status == _AuthStatus.restoring) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_status == _AuthStatus.repoSelection) {
      return RepoSelectionScreen(
        accessToken: _session!.accessToken,
        userLogin: _session!.user.login,
        avatarUrl: _session!.user.avatarUrl,
        onRepoSelected: _handleRepoSelected,
        repoCache: RepoCache(),
      );
    }

    if (_status == _AuthStatus.authenticated) {
      return DocumentScreen(
        onLogout: _handleLogout,
        storage: _bundle!.storage,
        noteService: _bundle!.noteService,
        refreshSignal: _refreshSignal,
        avatarUrl: _session?.user.avatarUrl,
      );
    }
    return LoginScreen(
      onGitHubLogin: _handleLogin,
    );
  }
}

/// Default storage factory: reads GitHub config from disk, falls back to local.
Future<StorageBundle> _defaultStorageFactory(
  String accessToken, {
  Future<void> Function()? onRemoteChanged,
}) async {
  final localService = NoteService();

  GitHubStorageConfig? config;
  try {
    config = await GitHubStorageConfig.load();
  } catch (_) {
    // Config file missing or unreadable — fall back to local storage.
  }

  if (config != null) {
    final apiClient = GitHubApiClient(
      token: accessToken,
      owner: config.owner,
      repo: config.repo,
    );
    return StorageBundle(
      storage: GitHubNoteStorage(apiClient),
      noteService: localService,
      syncEngine: GitHubSyncEngine(
        token: accessToken,
        owner: config.owner,
        repo: config.repo,
        branch: config.branch,
        interval: config.syncInterval,
        onRemoteChanged: onRemoteChanged,
      ),
    );
  }

  return StorageBundle(
    storage: localService,
    noteService: localService,
  );
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
  unauthenticated,
  repoSelection,
  authenticated,
}
