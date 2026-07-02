import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'main.dart'
    show
        StorageBundle,
        createDefaultAuthService,
        defaultLocalNotePath,
        defaultStorageFactory,
        flutterThemeMode;
import 'services/menu_bar_controller.dart';
import 'settings/app_settings_controller.dart';
import 'storage/github/repo_cache.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'widgets/menu_bar_panel.dart';

// Compact size for browsing (snug around the square calendar). The window
// widens for the editor overlay, whose reused toolbar needs ~386px, then
// shrinks back when the editor closes.
const Size _browseSize = Size(332, 500);
const Size _editSize = Size(420, 520);

// Native bridge (see MainFlutterWindow.swift). The popover is a non-activating
// panel, so it's shown via `orderFront` (which doesn't activate the app and so
// floats over other apps' full-screen Spaces) and dismissed by a native
// outside-click monitor that notifies Dart via `dismissed`.
const MethodChannel _popoverChannel = MethodChannel('simsync/popover');

/// Entry point for the macOS menu bar popover, which runs in its own
/// desktop_multi_window engine (separate from the main app window). It boots its
/// own storage from the persisted session/repo and renders [MenuBarPanel].
/// Because it's a separate, non-activating panel window, opening it never
/// touches the main app window and it can appear over full-screen apps.
///
/// [args] is `["multi_window", windowId, "popover:dx:dy"]`.
Future<void> runPopoverWindow(List<String> args) async {
  final windowId = args.length > 1 ? args[1] : '';
  final position = _parsePosition(args.length > 2 ? args[2] : '');

  // Size + place the panel. NOTE: no `titleBarStyle`/`alwaysOnTop`/`skipTaskbar`
  // here — the native side (MainFlutterWindow.swift) fully styles the panel and
  // owns its level + collection behavior; skipTaskbar would flip the whole app
  // to `.accessory` (which disables the MAIN window's native full-screen).
  // Showing is done natively (orderFront), not here.
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(size: _browseSize),
    () async {
      await windowManager.setPosition(position);
      await windowManager.setHasShadow(true);
    },
  );

  final settings =
      AppSettingsController(defaultLocalNotePath: defaultLocalNotePath());
  await settings.load();

  // Rebuild the same storage the main app uses from the persisted session/repo.
  StorageBundle? bundle;
  final remoteChanged = _RemoteChangedHook();
  final session = await createDefaultAuthService().restoreSession();
  if (session != null) {
    final repos = await RepoCache().load();
    if (repos.isNotEmpty) {
      final e = repos.first;
      bundle = await defaultStorageFactory(
        session.accessToken,
        owner: e.owner,
        repo: e.repo,
        branch: e.branch,
        // The factory wires this to the bundle's sync engine: a new remote
        // commit records the SHA + invalidates the storage's tree cache first,
        // then this fires so the popover can re-list fresh data.
        onRemoteChanged: () async => remoteChanged.handler?.call(),
      );
    }
  }

  runApp(_PopoverApp(
    windowId: windowId,
    position: position,
    settings: settings,
    bundle: bundle,
    remoteChanged: remoteChanged,
  ));
}

/// Late-bound callback: the storage bundle (and its sync engine) exists before
/// `runApp`, so the engine's remote-change signal is routed through this hook
/// and bound once the popover state is created.
class _RemoteChangedHook {
  VoidCallback? handler;
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
  });

  final String windowId;
  final Offset position;
  final AppSettingsController settings;
  final _RemoteChangedHook remoteChanged;
  final StorageBundle? bundle;

  @override
  State<_PopoverApp> createState() => _PopoverAppState();
}

class _PopoverAppState extends State<_PopoverApp> {
  MenuBarController? _controller;
  late Offset _anchor; // browse-size top-left, under the tray icon
  bool _editorOpen = false;
  WindowController? _mainWindow;

  @override
  void initState() {
    super.initState();
    _anchor = widget.position;
    _popoverChannel.setMethodCallHandler(_handleNativeCall);

    final bundle = widget.bundle;
    if (bundle != null) {
      _controller = MenuBarController(
        storage: () => bundle.storage,
        localStorage: () => bundle.localStorage,
        syncEnabled: () => widget.settings.value.syncEnabled,
        // A popover edit was persisted: reload the document screen right away.
        onChanged: () => unawaited(_notifyMainWindow()),
      );
      // Resize the window between browse/edit as the editor overlay opens/closes.
      _controller!.addListener(_onControllerChanged);
      unawaited(_controller!.load());
      // A remote commit was detected (tree cache already invalidated): re-list
      // so notes committed from the main window / other devices surface live.
      widget.remoteChanged.handler = () => unawaited(_controller!.load());
    }

    // The main window's tray click asks us to reposition + re-show.
    WindowController.fromWindowId(widget.windowId)
        .setWindowMethodHandler(_handleWindowMethod);

    // Show only after the first frame is painted, so the panel never flashes
    // empty before Flutter draws it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_show(_anchor));
      unawaited(_refreshExternalState());
    });
  }

  /// Position at the browse size and float the non-activating panel in front
  /// (native), so it appears over the current Space — full-screen included.
  Future<void> _show(Offset anchor) async {
    _anchor = anchor;
    await windowManager.setSize(_browseSize);
    await windowManager.setPosition(_anchor);
    await _popoverChannel.invokeMethod('orderFront');
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'dismissed') {
      // The native outside-click monitor hid us. Flush + close any open editor
      // so the next open starts clean on today's calendar, and stop polling —
      // the main window keeps its own sync engine running.
      _controller?.closeEditor();
      _editorOpen = false;
      widget.bundle?.syncEngine?.stop();
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
      _controller?.closeEditor();
      _controller?.resetToToday();
      _editorOpen = false;

      await _show(anchor);
      unawaited(_refreshExternalState());
    }
    return null;
  }

  /// Pulls in state that may have changed outside this engine while the popover
  /// was hidden, then revalidates the remote branch.
  ///
  /// Settings (theme / sync toggles changed in the main window) live in
  /// SharedPreferences, whose values are cached per engine — reload from disk
  /// first. Then restart the sync engine: `start()` runs an immediate poll, so
  /// a commit made elsewhere invalidates the storage's tree cache and re-lists
  /// via [_RemoteChangedHook]; polling continues while the popover is visible
  /// and stops on dismiss.
  Future<void> _refreshExternalState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    await widget.settings.load();

    final engine = widget.bundle?.syncEngine;
    if (engine != null) {
      engine.updateInterval(
        Duration(seconds: widget.settings.value.syncIntervalSeconds),
      );
      if (widget.settings.value.syncEnabled) {
        engine.start();
      } else {
        engine.stop();
      }
    }
    await _controller?.load();
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
    final open = _controller?.editingNote != null;
    if (open != _editorOpen) {
      _editorOpen = open;
      unawaited(_applyEditorSize(open));
    }
  }

  /// Widen the window for the editor overlay, shrink back for browsing. The
  /// right edge stays anchored so growing wider never pushes off-screen.
  Future<void> _applyEditorSize(bool editing) async {
    final size = editing ? _editSize : _browseSize;
    final rightEdge = _anchor.dx + _browseSize.width;
    final x = editing ? rightEdge - _editSize.width : _anchor.dx;
    await windowManager.setPosition(Offset(x, _anchor.dy));
    await windowManager.setSize(size);
  }

  @override
  void dispose() {
    widget.remoteChanged.handler = null;
    widget.bundle?.syncEngine?.dispose();
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    widget.settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild MaterialApp when settings (theme) change.
    return AnimatedBuilder(
      animation: widget.settings,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: flutterThemeMode(widget.settings.value.themeMode),
        home: Scaffold(
          body: _controller == null
              ? const _PopoverUnavailable()
              : MenuBarPanel(controller: _controller!, settings: widget.settings),
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
