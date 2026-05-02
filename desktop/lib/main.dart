import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/auth_models.dart';
import 'auth/auth_service.dart';
import 'auth/github_oauth_provider.dart';
import 'auth/session_policy.dart';
import 'auth/session_store.dart';
import 'settings/app_settings.dart';
import 'settings/app_settings_controller.dart';
import 'screens/document_screen.dart';
import 'screens/login_screen.dart';
import 'screens/repo_selection_screen.dart';
import 'services/note_service.dart';
import 'storage/github/github_api_client.dart';
import 'storage/github/github_note_storage.dart';
import 'storage/github/github_sync_engine.dart';
import 'storage/github/repo_cache.dart';
import 'storage/local/local_note_storage.dart';
import 'storage/note_storage.dart';
import 'theme/app_theme.dart';

/// Resolved storage layer after authentication.
class StorageBundle {
  final NoteStorage storage; // GitHub (remote)
  final NoteStorage? localStorage; // Local file system
  final NoteService noteService;
  final GitHubSyncEngine? syncEngine;

  const StorageBundle({
    required this.storage,
    required this.noteService,
    this.localStorage,
    this.syncEngine,
  });
}

/// Signature for a function that creates a [StorageBundle] from a token and
/// repo info.
///
/// The optional [onRemoteChanged] callback is invoked by the sync engine
/// when a new remote commit is detected, allowing the caller to refresh the UI.
typedef StorageFactory =
    Future<StorageBundle> Function(
      String accessToken, {
      required String owner,
      required String repo,
      required String branch,
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
    this.repoCache,
    this.sessionCheckInterval = const Duration(minutes: 1),
  });

  final AuthService authService;

  /// Optional override for storage initialization (useful for testing).
  /// When null, the default factory uses repo info from [RepoCache].
  final StorageFactory? storageFactory;

  /// Optional override for repo cache (useful for testing).
  /// When null, uses the default [RepoCache] backed by `~/.simsync/repos.json`.
  final RepoCache? repoCache;

  /// Periodic interval used to validate the stored session in the background.
  final Duration sessionCheckInterval;

  @override
  State<SimSyncApp> createState() => SimSyncAppState();
}

class SimSyncAppState extends State<SimSyncApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SimSync',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      home: _AppShell(
        authService: widget.authService,
        storageFactory: widget.storageFactory ?? _defaultStorageFactory,
        repoCache: widget.repoCache ?? RepoCache(),
        sessionCheckInterval: widget.sessionCheckInterval,
      ),
    );
  }
}

/// Root shell that manages auth state (login <-> document screen).
class _AppShell extends StatefulWidget {
  const _AppShell({
    required this.authService,
    required this.storageFactory,
    required this.repoCache,
    required this.sessionCheckInterval,
  });

  final AuthService authService;
  final StorageFactory storageFactory;
  final RepoCache repoCache;
  final Duration sessionCheckInterval;

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  _AuthStatus _status = _AuthStatus.restoring;
  late final AppSettingsController _settingsController;

  // Session stored after login, needed for repo selection screen.
  AuthSession? _session;
  RepoEntry? _activeRepo;

  // Storage layer (resolved after auth succeeds).
  StorageBundle? _bundle;
  Timer? _sessionCheckTimer;
  bool _isValidatingSession = false;

  /// Notifier incremented when the sync engine detects remote changes.
  /// DocumentScreen listens to this to reload notes.
  final ValueNotifier<int> _refreshSignal = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _settingsController = AppSettingsController(
      defaultLocalNotePath: _defaultLocalNotePath(),
    );
    _initialize();
  }

  @override
  void dispose() {
    _stopSessionMonitor();
    _bundle?.syncEngine?.dispose();
    _settingsController.dispose();
    _refreshSignal.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _settingsController.load();
    await _restoreSession();
  }

  Future<void> _handleLogin() async {
    final session = await widget.authService.signIn();
    if (!mounted) return;
    _session = session;
    _startSessionMonitor();
    setState(() => _status = _AuthStatus.repoSelection);
  }

  Future<void> _handleLogout() async {
    _stopSessionMonitor();
    _bundle?.syncEngine?.dispose();
    _bundle = null;
    _session = null;
    _activeRepo = null;
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

    // Check if a cached repo entry exists on disk.
    final entries = await widget.repoCache.load();

    if (!mounted) return;

    if (entries.isNotEmpty) {
      // Use the most recently connected repo.
      final entry = entries.first;
      _session = session;
      _activeRepo = entry;
      _startSessionMonitor();
      _bundle = await widget.storageFactory(
        session.accessToken,
        owner: entry.owner,
        repo: entry.repo,
        branch: entry.branch,
        onRemoteChanged: _onRemoteChanged,
      );
      _applySyncPreference(_bundle);
      if (!mounted) return;
      setState(() => _status = _AuthStatus.authenticated);
    } else {
      // No cached repo — let user pick one.
      _session = session;
      _startSessionMonitor();
      setState(() => _status = _AuthStatus.repoSelection);
    }
  }

  Future<void> _handleRepoSelected(RepoEntry entry) async {
    // Persist the selected repo to the cache.
    await widget.repoCache.add(entry);

    _bundle?.syncEngine?.dispose();

    // Create storage bundle directly from the repo entry.
    _activeRepo = entry;
    _bundle = await widget.storageFactory(
      _session!.accessToken,
      owner: entry.owner,
      repo: entry.repo,
      branch: entry.branch,
      onRemoteChanged: _onRemoteChanged,
    );
    _applySyncPreference(_bundle);
    if (!mounted) return;
    setState(() => _status = _AuthStatus.authenticated);
  }

  Future<List<RepoEntry>> _loadCachedRepos() {
    return widget.repoCache.load();
  }

  Future<void> _handleLocalNotePathChanged(String path) async {
    await _settingsController.setLocalNotePath(path);
    if (_session == null || _activeRepo == null) return;

    _bundle?.syncEngine?.dispose();
    final nextBundle = await widget.storageFactory(
      _session!.accessToken,
      owner: _activeRepo!.owner,
      repo: _activeRepo!.repo,
      branch: _activeRepo!.branch,
      onRemoteChanged: _onRemoteChanged,
    );
    _applySyncPreference(nextBundle);
    if (!mounted) return;

    setState(() => _bundle = nextBundle);
  }

  void _handleSyncEnabledChanged(bool enabled) {
    _applySyncPreference(_bundle, enabled: enabled);
  }

  void _applySyncPreference(StorageBundle? bundle, {bool? enabled}) {
    final syncEnabled = enabled ?? _settingsController.value.syncEnabled;
    final engine = bundle?.syncEngine;
    if (engine == null) return;

    if (syncEnabled) {
      engine.start();
    } else {
      engine.stop();
    }
  }

  Future<RepoEntry> _handleCreateRepo(String name) async {
    final session = _session;
    if (session == null) {
      throw StateError('No authenticated session');
    }

    final client = GitHubApiClient(
      token: session.accessToken,
      owner: session.user.login,
      repo: '_',
    );
    try {
      await client.createRepo(name: name);
      return RepoEntry(owner: session.user.login, repo: name);
    } finally {
      client.dispose();
    }
  }

  Future<RepoEntry> _handleConnectRepo(String owner, String repo) async {
    final session = _session;
    if (session == null) {
      throw StateError('No authenticated session');
    }

    final client = GitHubApiClient(
      token: session.accessToken,
      owner: session.user.login,
      repo: '_',
    );
    try {
      final exists = await client.repoExists(owner: owner, repo: repo);
      if (!exists) {
        throw StateError('Repository not found');
      }
      return RepoEntry(owner: owner, repo: repo);
    } finally {
      client.dispose();
    }
  }

  void _startSessionMonitor() {
    _stopSessionMonitor();
    if (_session == null) return;
    _scheduleNextSessionCheck();
  }

  void _stopSessionMonitor() {
    _sessionCheckTimer?.cancel();
    _sessionCheckTimer = null;
  }

  void _scheduleNextSessionCheck() {
    _sessionCheckTimer = Timer(
      widget.sessionCheckInterval,
      () => unawaited(_runSessionCheckCycle()),
    );
  }

  Future<void> _runSessionCheckCycle() async {
    await _checkSessionValidity();
    if (!mounted ||
        _session == null ||
        _status == _AuthStatus.unauthenticated) {
      return;
    }
    _scheduleNextSessionCheck();
  }

  Future<void> _checkSessionValidity() async {
    final session = _session;
    if (session == null ||
        _status == _AuthStatus.restoring ||
        _status == _AuthStatus.unauthenticated ||
        _isValidatingSession) {
      return;
    }

    _isValidatingSession = true;
    try {
      final isValid = await widget.authService.validateSession(session);
      if (!mounted || isValid) {
        return;
      }
      await _handleLogout();
    } finally {
      _isValidatingSession = false;
    }
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
        repoCache: widget.repoCache,
        settingsController: _settingsController,
      );
    }

    if (_status == _AuthStatus.authenticated) {
      return DocumentScreen(
        onLogout: _handleLogout,
        storage: _bundle!.storage,
        localStorage: _bundle!.localStorage,
        noteService: _bundle!.noteService,
        refreshSignal: _refreshSignal,
        avatarUrl: _session?.user.avatarUrl,
        activeRepo: _activeRepo,
        settingsController: _settingsController,
        syncEngine: _bundle!.syncEngine,
        loadCachedRepos: _loadCachedRepos,
        onLocalNotePathChanged: _handleLocalNotePathChanged,
        onSyncEnabledChanged: _handleSyncEnabledChanged,
        onRepoSelected: _handleRepoSelected,
        onCreateRepo: _handleCreateRepo,
        onConnectRepo: _handleConnectRepo,
      );
    }
    return LoginScreen(onGitHubLogin: _handleLogin);
  }
}

/// Default storage factory: creates GitHub storage from provided repo info.
Future<StorageBundle> _defaultStorageFactory(
  String accessToken, {
  required String owner,
  required String repo,
  required String branch,
  Future<void> Function()? onRemoteChanged,
}) async {
  final localService = NoteService();
  final apiClient = GitHubApiClient(
    token: accessToken,
    owner: owner,
    repo: repo,
  );

  // Load local note path from SharedPreferences.
  final prefs = await SharedPreferences.getInstance();
  final localPath =
      prefs.getString(AppSettingsController.localNotePathKey) ??
      _defaultLocalNotePath();
  final syncIntervalSeconds =
      prefs.getInt(AppSettingsController.syncIntervalSecondsKey) ?? 5;

  final githubStorage = GitHubNoteStorage(apiClient, branch: branch);

  return StorageBundle(
    storage: githubStorage,
    localStorage: LocalNoteStorage(basePath: localPath),
    noteService: localService,
    syncEngine: GitHubSyncEngine(
      token: accessToken,
      owner: owner,
      repo: repo,
      branch: branch,
      interval: Duration(
        seconds: syncIntervalSeconds.clamp(
          AppSettings.minSyncIntervalSeconds,
          AppSettings.maxSyncIntervalSeconds,
        ),
      ),
      onRemoteChanged: () async {
        // A new commit on the tracked branch invalidates the cached tree
        // snapshot; the next listing call will refetch it.
        githubStorage.invalidateTreeCache();
        if (onRemoteChanged != null) {
          await onRemoteChanged();
        }
      },
    ),
  );
}

String _defaultLocalNotePath() {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  return '$home/Documents/SimSync';
}

AuthService createDefaultAuthService() {
  const config = GitHubOAuthConfig(
    clientId: String.fromEnvironment('SIMSYNC_GITHUB_CLIENT_ID'),
    clientSecret: String.fromEnvironment('SIMSYNC_GITHUB_CLIENT_SECRET'),
  );

  return DefaultAuthService(
    provider: GitHubOAuthProvider(config: config, httpClient: http.Client()),
    store: FileSessionStore(directoryProvider: getApplicationSupportDirectory),
    policy: const SessionPolicy(maxAge: Duration(hours: 24)),
    nowProvider: DateTime.now,
  );
}

enum _AuthStatus { restoring, unauthenticated, repoSelection, authenticated }
