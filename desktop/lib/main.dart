import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app_bootstrap.dart';
import 'auth/auth_models.dart';
import 'auth/auth_provider.dart';
import 'auth/auth_service.dart';
import 'settings/app_settings.dart';
import 'settings/app_settings_controller.dart';
import 'popover_window.dart';
import 'screens/document_screen.dart';
import 'screens/login_screen.dart';
import 'screens/repo_selection_screen.dart';
import 'services/menu_bar_manager.dart';
import 'storage/github/github_api_client.dart';
import 'storage/github/github_note_storage.dart';
import 'storage/github/repo_cache.dart';
import 'theme/app_theme.dart';

// Bootstrap types/helpers (StorageBundle, defaultStorageFactory, ...) moved to
// app_bootstrap.dart so the popover engine can boot without importing the app
// widget tree; re-exported here so existing imports keep working.
export 'app_bootstrap.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize native window management (per-engine: controls this window). The
  // main window is created at its final size natively in MainFlutterWindow.swift,
  // so we don't resize it here — a Dart resize caused a first-run resize flash.
  await windowManager.ensureInitialized();

  // desktop_multi_window launches sub-windows with args
  // ["multi_window", windowId, <configArgs>]. The menu bar calendar popover runs
  // as its own window so opening it never touches the main app window.
  if (args.isNotEmpty && args.first == 'multi_window') {
    await runPopoverWindow(args);
    return;
  }

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
  /// Drives `MaterialApp.themeMode`. Kept above the MaterialApp so the whole app
  /// — including the macOS menu bar popover — re-themes when the setting
  /// changes. Synced from the settings controller by [_AppShell].
  final ValueNotifier<ThemeMode> _themeMode = ValueNotifier(ThemeMode.system);

  @override
  void dispose() {
    _themeMode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'SimSync',
        debugShowCheckedModeBanner: false,
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: mode,
        home: _AppShell(
          authService: widget.authService,
          storageFactory: widget.storageFactory ?? defaultStorageFactory,
          repoCache: widget.repoCache ?? RepoCache(),
          sessionCheckInterval: widget.sessionCheckInterval,
          themeModeNotifier: _themeMode,
        ),
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
    required this.themeModeNotifier,
  });

  final AuthService authService;
  final StorageFactory storageFactory;
  final RepoCache repoCache;
  final Duration sessionCheckInterval;

  /// Root-level notifier the shell keeps in sync with the theme setting.
  final ValueNotifier<ThemeMode> themeModeNotifier;

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

  /// Adds the macOS menu bar tray icon and opens the separate popover window on
  /// a left click. No-op off macOS.
  late final MenuBarManager _menuBar;

  /// Bumped when the tray "설정" item is chosen, so DocumentScreen opens the
  /// settings dialog.
  final ValueNotifier<int> _openSettingsSignal = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _settingsController = AppSettingsController(
      defaultLocalNotePath: defaultLocalNotePath(),
    );
    _menuBar = MenuBarManager(
      onOpenSettings: () => _openSettingsSignal.value++,
      onToggleTheme: _toggleTheme,
      isDark: _effectiveDark,
      // Popover edits ping back over the multi-window channel. The popover
      // already committed through its own storage instance, so drop this
      // engine's cached tree first — otherwise the reload serves the stale
      // snapshot and the edit stays invisible until the next sync poll.
      onNotesChanged: () {
        final storage = _bundle?.storage;
        if (storage is GitHubNoteStorage) storage.invalidateTreeCache();
        _refreshSignal.value++;
      },
    );
    _settingsController.addListener(_syncThemeMode);
    unawaited(_menuBar.setUp());
    _initialize();
  }

  @override
  void dispose() {
    _stopSessionMonitor();
    _bundle?.syncEngine?.dispose();
    _settingsController.removeListener(_syncThemeMode);
    _settingsController.dispose();
    _refreshSignal.dispose();
    unawaited(_menuBar.dispose());
    _openSettingsSignal.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _settingsController.load();
    _syncThemeMode();
    await _restoreSession();
  }

  /// Last dark/light state pushed to the tray menu, so the native menu is only
  /// rebuilt when the checkbox would actually change (this listener fires for
  /// EVERY settings notification, e.g. each content-scale step).
  bool? _trayMenuDark;

  /// Pushes the persisted theme preference up to the MaterialApp-level notifier
  /// so light/dark/system applies across the whole app and the menu bar popover.
  void _syncThemeMode() {
    widget.themeModeNotifier.value =
        flutterThemeMode(_settingsController.value.themeMode);
    // Keep the tray "다크 모드" checkbox in sync when the theme changes.
    final dark = _effectiveDark();
    if (dark == _trayMenuDark) return;
    _trayMenuDark = dark;
    unawaited(_menuBar.refreshMenu());
  }

  /// Whether the app currently renders dark (accounting for System mode).
  bool _effectiveDark() {
    switch (_settingsController.value.themeMode) {
      case AppThemeMode.dark:
        return true;
      case AppThemeMode.light:
        return false;
      case AppThemeMode.system:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    }
  }

  /// Flips between light and dark based on what's currently rendered. Used by the
  /// tray checkbox and the title-bar toggle button.
  void _toggleTheme() {
    unawaited(_settingsController.setThemeMode(
      _effectiveDark() ? AppThemeMode.light : AppThemeMode.dark,
    ));
  }

  Future<void> _handleLogin({
    DeviceAuthorizationPrompt? onAuthorizationPrompt,
  }) async {
    final session = await widget.authService
        .signIn(onAuthorizationPrompt: onAuthorizationPrompt);
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
    // Forward the remote change to an open popover: it deliberately runs no
    // poll loop of its own (this engine already polls), so this push is how it
    // refreshes live while visible.
    unawaited(_menuBar.notifyPopoverRemoteChanged());
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
        openSettingsSignal: _openSettingsSignal,
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
    return LoginScreen(
      onGitHubLogin: _handleLogin,
      onCancelLogin: widget.authService.cancelSignIn,
    );
  }
}

enum _AuthStatus { restoring, unauthenticated, repoSelection, authenticated }
