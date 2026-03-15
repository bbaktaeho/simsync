import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/auth_models.dart';
import 'auth/auth_service.dart';
import 'auth/github_oauth_provider.dart';
import 'auth/session_policy.dart';
import 'auth/session_store.dart';
import 'settings/app_settings.dart';
import 'settings/app_settings_controller.dart';
import 'screens/home_screen.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko');
  final dir = await getApplicationSupportDirectory();
  final repoCache = RepoCache.withPath('${dir.path}/repos.json');
  runApp(SimSyncApp(
    authService: createDefaultAuthService(),
    repoCache: repoCache,
  ));
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

  /// Allow descendants to toggle theme mode.
  static SimSyncAppState of(BuildContext context) =>
      context.findAncestorStateOfType<SimSyncAppState>()!;
}

class SimSyncAppState extends State<SimSyncApp> {
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  void toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark
          ? ThemeMode.light
          : ThemeMode.dark;
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
        repoCache: widget.repoCache ?? RepoCache(),
        sessionCheckInterval: widget.sessionCheckInterval,
      ),
    );
  }
}

/// Root shell that manages auth state (login <-> home screen).
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
  late AppSettingsController _settingsController;

  // Session stored after login, needed for repo selection screen.
  AuthSession? _session;
  RepoEntry? _activeRepo;

  // Storage layer (resolved after auth succeeds).
  StorageBundle? _bundle;
  Timer? _sessionCheckTimer;
  bool _isValidatingSession = false;

  /// Notifier incremented when the sync engine detects remote changes.
  /// HomeScreen listens to this to reload notes.
  final ValueNotifier<int> _refreshSignal = ValueNotifier<int>(0);

  /// Deep link stream subscription (app_links).
  StreamSubscription<Uri>? _deepLinkSub;

  /// app_links instance for handling deep links.
  late final AppLinks _appLinks;

  @override
  void initState() {
    super.initState();
    _appLinks = AppLinks();
    _initDeepLinkListener();
    _initialize();
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    _stopSessionMonitor();
    _bundle?.syncEngine?.dispose();
    _settingsController.dispose();
    _refreshSignal.dispose();
    super.dispose();
  }

  void _initDeepLinkListener() {
    // Handle deep link that launched the app (cold start).
    _handleInitialUri();
    // Listen for deep links while the app is running (warm start).
    _deepLinkSub = _appLinks.uriLinkStream.listen((Uri uri) {
      _handleDeepLink(uri);
    });
  }

  Future<void> _handleInitialUri() async {
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    } catch (_) {
      // Ignore - no initial URI
    }
  }

  void _handleDeepLink(Uri uri) {
    if (uri.scheme == 'simsync' && uri.host == 'callback') {
      _oauthProvider.handleRedirectUri(uri);
    }
  }

  Future<void> _initialize() async {
    final dir = await getApplicationDocumentsDirectory();
    final localPath = '${dir.path}/SimSync';
    _settingsController = AppSettingsController(defaultLocalNotePath: localPath);
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
      // No cached repo -- let user pick one.
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
      );
    }

    if (_status == _AuthStatus.authenticated) {
      return HomeScreen(
        onLogout: _handleLogout,
        storage: _bundle!.storage,
        localStorage: _bundle!.localStorage,
        noteService: _bundle!.noteService,
        refreshSignal: _refreshSignal,
        avatarUrl: _session?.user.avatarUrl,
        activeRepo: _activeRepo,
        settingsController: _settingsController,
        syncEngine: _bundle!.syncEngine,
        onSyncEnabledChanged: _handleSyncEnabledChanged,
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

  return StorageBundle(
    storage: GitHubNoteStorage(apiClient),
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
      onRemoteChanged: onRemoteChanged,
    ),
  );
}

String _defaultLocalNotePath() {
  // Fallback; real path resolved async in _initialize
  if (Platform.isAndroid || Platform.isIOS) {
    return ''; // Will be set after async init
  }
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  return '$home/Documents/SimSync';
}

/// Global reference to the OAuth provider so deep links can reach it.
late final GitHubOAuthProvider _oauthProvider;

AuthService createDefaultAuthService() {
  const config = GitHubOAuthConfig(
    clientId: String.fromEnvironment('SIMSYNC_GITHUB_CLIENT_ID'),
    clientSecret: String.fromEnvironment('SIMSYNC_GITHUB_CLIENT_SECRET'),
  );

  _oauthProvider = GitHubOAuthProvider(config: config, httpClient: http.Client());

  return DefaultAuthService(
    provider: _oauthProvider,
    store: FileSessionStore(directoryProvider: getApplicationSupportDirectory),
    policy: const SessionPolicy(maxAge: Duration(hours: 24)),
    nowProvider: DateTime.now,
  );
}

enum _AuthStatus { restoring, unauthenticated, repoSelection, authenticated }
