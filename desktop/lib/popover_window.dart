import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

const Size _popoverSize = Size(400, 500);

/// Entry point for the macOS menu bar popover, which runs in its own
/// desktop_multi_window engine (separate from the main app window). It shapes a
/// frameless, always-on-top, hide-on-blur panel; boots its own storage from the
/// persisted session/repo; and renders [MenuBarPanel]. Because it's a separate
/// window, opening it never touches the main app window.
///
/// [args] is `["multi_window", windowId, "popover:dx:dy"]`.
Future<void> runPopoverWindow(List<String> args) async {
  final windowId = args.length > 1 ? args[1] : '';
  final position = _parsePosition(args.length > 2 ? args[2] : '');

  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: _popoverSize,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      alwaysOnTop: true,
      skipTaskbar: true,
    ),
    () async {
      await windowManager.setPosition(position);
      // Appear on every Space AND over other apps' full-screen windows
      // (.canJoinAllSpaces + .fullScreenAuxiliary), not just the desktop Space.
      await windowManager.setVisibleOnAllWorkspaces(
        true,
        visibleOnFullScreen: true,
      );
      await windowManager.setHasShadow(true);
      await windowManager.show();
      await windowManager.focus();
    },
  );

  final settings =
      AppSettingsController(defaultLocalNotePath: defaultLocalNotePath());
  await settings.load();

  // Rebuild the same storage the main app uses from the persisted session/repo.
  StorageBundle? bundle;
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
      );
    }
  }

  runApp(_PopoverApp(windowId: windowId, settings: settings, bundle: bundle));
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
    required this.settings,
    this.bundle,
  });

  final String windowId;
  final AppSettingsController settings;
  final StorageBundle? bundle;

  @override
  State<_PopoverApp> createState() => _PopoverAppState();
}

class _PopoverAppState extends State<_PopoverApp> with WindowListener {
  MenuBarController? _controller;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);

    final bundle = widget.bundle;
    if (bundle != null) {
      _controller = MenuBarController(
        storage: () => bundle.storage,
        localStorage: () => bundle.localStorage,
        syncEnabled: () => widget.settings.value.syncEnabled,
        onChanged: () {},
      );
      unawaited(_controller!.load());
    }

    // The main window's tray click asks us to reposition + re-show.
    WindowController.fromWindowId(widget.windowId)
        .setWindowMethodHandler(_handleWindowMethod);
  }

  Future<dynamic> _handleWindowMethod(MethodCall call) async {
    if (call.method == 'show') {
      final a = call.arguments as Map?;
      final dx = (a?['dx'] as num?)?.toDouble();
      final dy = (a?['dy'] as num?)?.toDouble();
      if (dx != null && dy != null) {
        await windowManager.setPosition(Offset(dx, dy));
      }
      await windowManager.show();
      await windowManager.focus();
      // Re-anchor to today, then refresh notes + settings (theme) each time the
      // popover is surfaced.
      _controller?.resetToToday();
      unawaited(_controller?.load());
      unawaited(widget.settings.load());
    }
    return null;
  }

  @override
  void onWindowBlur() {
    // Dismiss the popover the moment focus leaves it.
    unawaited(windowManager.hide());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
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
