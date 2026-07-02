import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app_bootstrap.dart';
import 'auth/auth_models.dart';
import 'services/menu_bar_controller.dart';
import 'services/menu_bar_manager.dart';
import 'settings/app_settings_controller.dart';
import 'storage/github/github_note_storage.dart';
import 'storage/github/repo_cache.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'widgets/menu_bar_panel.dart';

// Native bridge (see MainFlutterWindow.swift). The popover is a non-activating
// panel, so it's shown via `orderFront` (which doesn't activate the app and so
// floats over other apps' full-screen Spaces) and dismissed by a native
// outside-click monitor that notifies Dart via `dismissed`.
const MethodChannel _popoverChannel = MethodChannel('simsync/popover');

/// Entry point for the macOS menu bar popover, which runs in its own
/// desktop_multi_window engine (separate from the main app window). It boots
/// its own storage from the persisted session/repo and renders [MenuBarPanel].
/// Because it's a separate, non-activating panel window, opening it never
/// touches the main app window and it can appear over full-screen apps.
///
/// [args] is `["multi_window", windowId, "popover:dx:dy"]`.
Future<void> runPopoverWindow(List<String> args) async {
  final windowId = args.length > 1 ? args[1] : '';
  final position = _parsePosition(args.length > 2 ? args[2] : '');

  final settings =
      AppSettingsController(defaultLocalNotePath: defaultLocalNotePath());
  final remoteChanged = _RemoteChangedHook();

  // Window shaping, settings, and session/repo resolution are independent —
  // run them in parallel to cut popover boot latency. NOTE: no `titleBarStyle`
  // /`alwaysOnTop`/`skipTaskbar` in the options — the native side
  // (MainFlutterWindow.swift) fully styles the panel and owns its level +
  // collection behavior; skipTaskbar would flip the whole app to `.accessory`
  // (which disables the MAIN window's native full-screen). Showing is done
  // natively (orderFront), not here.
  _StorageInputs? inputs;
  await Future.wait([
    windowManager.waitUntilReadyToShow(
      const WindowOptions(size: MenuBarManager.popoverSize),
      () async {
        await windowManager.setPosition(position);
        await windowManager.setHasShadow(true);
      },
    ),
    settings.load(),
    () async {
      try {
        inputs = await _resolveStorageInputs();
      } catch (_) {
        // Offline at boot (session validation is a network call): come up in
        // the unavailable state; the next show re-derives via
        // [_syncBundleWithDisk].
        inputs = null;
      }
    }(),
  ]);

  // Rebuild the same storage the main app uses from the persisted session/repo.
  StorageBundle? bundle;
  String? bundleKey;
  final resolved = inputs;
  if (resolved != null) {
    bundleKey = _bundleKeyFor(resolved, settings.value.localNotePath);
    bundle = await _buildBundle(resolved, remoteChanged);
  }

  runApp(_PopoverApp(
    windowId: windowId,
    position: position,
    settings: settings,
    remoteChanged: remoteChanged,
    bundle: bundle,
    bundleKey: bundleKey,
  ));
}

/// Late-bound callback: the storage bundle (and its sync engine) exists before
/// `runApp`, so the engine's remote-change signal is routed through this hook
/// and bound once the popover state is created.
class _RemoteChangedHook {
  VoidCallback? handler;
}

/// The persisted inputs the popover's storage is derived from. Logged out or
/// no repo connected → null (see [_resolveStorageInputs]).
class _StorageInputs {
  const _StorageInputs(this.session, this.repo);

  final AuthSession session;
  final RepoEntry repo;
}

Future<_StorageInputs?> _resolveStorageInputs() async {
  final session = await createDefaultAuthService().restoreSession();
  if (session == null) return null;
  final repos = await RepoCache().load();
  if (repos.isEmpty) return null;
  return _StorageInputs(session, repos.first);
}

/// Fingerprints everything the bundle is built from, so the popover can tell
/// whether the main window logged in/out, switched repo, or moved the local
/// note path since the bundle was created.
String _bundleKeyFor(_StorageInputs inputs, String localNotePath) =>
    '${inputs.session.accessToken}|${inputs.repo.owner}|${inputs.repo.repo}|'
    '${inputs.repo.branch}|$localNotePath';

Future<StorageBundle> _buildBundle(
  _StorageInputs inputs,
  _RemoteChangedHook remoteChanged,
) {
  return defaultStorageFactory(
    inputs.session.accessToken,
    owner: inputs.repo.owner,
    repo: inputs.repo.repo,
    branch: inputs.repo.branch,
    // The factory wires this to the bundle's sync engine: a new remote commit
    // records the SHA + invalidates the storage's tree cache first, then this
    // fires so the popover can re-list fresh data.
    onRemoteChanged: () async => remoteChanged.handler?.call(),
  );
}

Offset _parsePosition(String config) {
  // 'popover:dx:dy'
  final parts = config.split(':');
  if (parts.length >= 3) {
    final dx = double.tryParse(parts[1]);
    final dy = double.tryParse(parts[2]);
    if (dx != null && dy != null) return Offset(dx, dy);
  }
  return const Offset(8, 26);
}

class _PopoverApp extends StatefulWidget {
  const _PopoverApp({
    required this.windowId,
    required this.position,
    required this.settings,
    required this.remoteChanged,
    this.bundle,
    this.bundleKey,
  });

  final String windowId;
  final Offset position;
  final AppSettingsController settings;
  final _RemoteChangedHook remoteChanged;
  final StorageBundle? bundle;
  final String? bundleKey;

  @override
  State<_PopoverApp> createState() => _PopoverAppState();
}

class _PopoverAppState extends State<_PopoverApp> {
  // Theme objects are immutable and settings-independent: build them once
  // instead of on every settings notification.
  static final ThemeData _lightTheme = buildLightTheme();
  static final ThemeData _darkTheme = buildDarkTheme();

  late final MenuBarController _controller;
  StorageBundle? _bundle;
  String? _bundleKey;
  late Offset _anchor; // browse-size top-left, under the tray icon
  bool _editorOpen = false;
  WindowController? _mainWindow;

  @override
  void initState() {
    super.initState();
    _anchor = widget.position;
    _bundle = widget.bundle;
    _bundleKey = widget.bundleKey;
    _popoverChannel.setMethodCallHandler(_handleNativeCall);

    // The controller reads storage through closures so a bundle swap (login,
    // logout, repo switch picked up in [_syncBundleWithDisk]) takes effect
    // without rebuilding it.
    _controller = MenuBarController(
      storage: () => _bundle?.storage,
      localStorage: () => _bundle?.localStorage,
      syncEnabled: () => widget.settings.value.syncEnabled,
      // A popover edit was persisted: reload the document screen right away.
      onChanged: () => unawaited(_notifyMainWindow()),
    );
    // Resize the window between browse/edit as the editor overlay opens/closes.
    _controller.addListener(_onControllerChanged);
    // A remote commit was detected (tree cache already invalidated): re-list
    // so notes committed from the main window / other devices surface live.
    widget.remoteChanged.handler = () => unawaited(_controller.load());

    if (_bundle != null) {
      unawaited(_controller.load());
      // Boot trusted the disk cache; check the branch head once so commits
      // made while the app was closed surface on the first open.
      unawaited(_syncNowIfEnabled());
    }

    // The main window's tray click asks us to reposition + re-show.
    WindowController.fromWindowId(widget.windowId)
        .setWindowMethodHandler(_handleWindowMethod);

    // Show only after the first frame is painted, so the panel never flashes
    // empty before Flutter draws it.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => unawaited(_show(_anchor)));
  }

  /// Position at the browse size and float the non-activating panel in front
  /// (native), so it appears over the current Space — full-screen included.
  Future<void> _show(Offset anchor) async {
    _anchor = anchor;
    await windowManager.setSize(MenuBarManager.popoverSize);
    await windowManager.setPosition(_anchor);
    await _popoverChannel.invokeMethod('orderFront');
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'dismissed') {
      // The native outside-click monitor hid us. Flush + close any open editor
      // so the next open starts clean on today's calendar.
      _controller.closeEditor();
    }
    return null;
  }

  Future<dynamic> _handleWindowMethod(MethodCall call) async {
    if (call.method == 'show') {
      final a = call.arguments as Map?;
      final dx = (a?['dx'] as num?)?.toDouble();
      final dy = (a?['dy'] as num?)?.toDouble();
      final anchor = (dx != null && dy != null) ? Offset(dx, dy) : _anchor;

      // Reopen browsing today's calendar (close any leftover editor overlay).
      _controller.closeEditor();
      _controller.resetToToday();

      await _show(anchor);
      unawaited(_refreshExternalState());
    } else if (call.method == 'remote_changed') {
      // Pushed by the main engine's sync poll. Its storage instance already
      // refetched; ours still holds the old tree snapshot — drop it and
      // re-list. This push is why the popover runs no poll loop of its own.
      final storage = _bundle?.storage;
      if (storage is GitHubNoteStorage) storage.invalidateTreeCache();
      unawaited(_controller.load());
    } else if (call.method == 'flush') {
      // The app is quitting: persist any still-debounced edit before exit(0).
      await _controller.flushPendingSaves();
      final storage = _bundle?.storage;
      if (storage is GitHubNoteStorage) await storage.flushCache();
    }
    return null;
  }

  /// Pulls in state that may have changed outside this engine while the
  /// popover was hidden.
  ///
  /// Settings (theme / sync toggles changed in the main window) live in
  /// SharedPreferences, whose values are cached per engine — reload from disk
  /// first. Then re-derive the storage bundle (login/logout/repo/local-path
  /// changes), revalidate the branch head once, and re-list. No periodic
  /// polling happens in this engine: while the popover is visible, the main
  /// engine's poll pushes 'remote_changed' instead.
  Future<void> _refreshExternalState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    await widget.settings.load();
    await _syncBundleWithDisk();
    unawaited(_syncNowIfEnabled());
    await _controller.load();
  }

  /// One-shot branch-head check (no timer): detects commits made while neither
  /// engine was watching. On change the engine records the SHA, invalidates
  /// the tree cache, and [_RemoteChangedHook] re-lists.
  Future<void> _syncNowIfEnabled() async {
    if (!widget.settings.value.syncEnabled) return;
    await _bundle?.syncEngine?.syncNow();
  }

  /// Re-derives session/repo from disk and swaps the bundle when they drifted,
  /// so this long-lived engine never keeps listing — or worse, committing —
  /// against a stale repo, token, or local path.
  Future<void> _syncBundleWithDisk() async {
    _StorageInputs? inputs;
    try {
      inputs = await _resolveStorageInputs();
    } catch (_) {
      // Offline / API hiccup during session validation: keep the current
      // bundle instead of tearing it down over a transient failure.
      return;
    }
    final key = inputs == null
        ? null
        : _bundleKeyFor(inputs, widget.settings.value.localNotePath);
    if (key == _bundleKey) return;

    _bundle?.syncEngine?.dispose();
    _bundle = null;
    _bundleKey = key;
    if (inputs != null) {
      _bundle = await _buildBundle(inputs, widget.remoteChanged);
    }
    if (mounted) setState(() {});
  }

  /// Pings the main window over the multi-window channel after the popover
  /// persists a note, so the document screen reloads immediately instead of
  /// waiting for its next sync poll. The main window is the engine attached
  /// without launch arguments.
  Future<void> _notifyMainWindow() async {
    try {
      _mainWindow ??= (await WindowController.getAll())
          .firstWhere((w) => w.arguments.isEmpty);
      await _mainWindow!.invokeMethod('notes_changed');
    } catch (_) {
      // Main window not reachable right now; retry on the next change.
      _mainWindow = null;
    }
  }

  void _onControllerChanged() {
    final open = _controller.editingNote != null;
    if (open != _editorOpen) {
      _editorOpen = open;
      unawaited(_applyEditorSize(open));
    }
  }

  /// Widen the window for the editor overlay, shrink back for browsing. The
  /// right edge stays anchored so growing wider never pushes off-screen.
  Future<void> _applyEditorSize(bool editing) async {
    final size =
        editing ? MenuBarManager.popoverEditSize : MenuBarManager.popoverSize;
    final rightEdge = _anchor.dx + MenuBarManager.popoverSize.width;
    final x = editing ? rightEdge - size.width : _anchor.dx;
    await windowManager.setPosition(Offset(x, _anchor.dy));
    await windowManager.setSize(size);
  }

  @override
  void dispose() {
    widget.remoteChanged.handler = null;
    _bundle?.syncEngine?.dispose();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    widget.settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild MaterialApp when settings (theme mode / scale) change.
    return AnimatedBuilder(
      animation: widget.settings,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _lightTheme,
        darkTheme: _darkTheme,
        themeMode: flutterThemeMode(widget.settings.value.themeMode),
        home: Scaffold(
          body: _bundle == null
              ? const _PopoverUnavailable()
              : MenuBarPanel(controller: _controller, settings: widget.settings),
        ),
      ),
    );
  }
}

class _PopoverUnavailable extends StatelessWidget {
  const _PopoverUnavailable();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      color: c.surface,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Text(
        'SimSync 앱에서 먼저 로그인하세요.',
        textAlign: TextAlign.center,
        style: TextStyle(color: c.textSecondary),
      ),
    );
  }
}
