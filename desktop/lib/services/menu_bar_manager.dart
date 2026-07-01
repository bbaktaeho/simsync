import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Adds a macOS menu bar (status bar) presence and reshapes the single app
/// window between two forms:
///
///  * **app** — the normal titled SimSync window (the default form).
///  * **panel** — a frameless, always-on-top popover anchored under the tray
///    icon that dismisses as soon as it loses focus.
///
/// Left-clicking the tray icon toggles the panel; right-clicking pops a native
/// menu (앱 열기 / 설정 / 앱 종료). Closing the app window hides it back to the
/// menu bar rather than quitting — only "앱 종료" ends the process.
///
/// macOS-only: on every other platform [setUp] is a no-op, so the app keeps its
/// stock single-window behaviour.
class MenuBarManager with TrayListener, WindowListener {
  MenuBarManager({
    required this.onShowPanel,
    required this.onShowApp,
    required this.onOpenSettings,
    required this.canShowPanel,
  });

  /// Switches the visible surface to the popover panel.
  final VoidCallback onShowPanel;

  /// Switches the visible surface back to the document app.
  final VoidCallback onShowApp;

  /// Opens the in-app settings (invoked after the app window is surfaced).
  final VoidCallback onOpenSettings;

  /// Whether the popover may be shown right now (e.g. authenticated with a
  /// storage bundle). When false, a left click surfaces the app instead.
  final bool Function() canShowPanel;

  static const String _iconPath = 'assets/tray/menu_bar_icon.png';
  // Wide enough that the reused EditorPanel toolbar fits without overflow when
  // the editor overlay is open; tall enough for the calendar + a note list.
  static const Size panelSize = Size(460, 580);
  static const Size _appSize = Size(1120, 760);
  // The macOS menu bar is always at the very top, so a fixed top inset places
  // the popover just beneath it — reliable regardless of the icon-bounds y
  // coordinate space (which is bottom-left origin and not directly usable).
  static const double _menuBarInset = 26;

  bool _panelVisible = false;

  // Skip all native tray/window channel calls under `flutter test`, where the
  // plugins are not registered (the host may still be macOS).
  static final bool _underTest =
      Platform.environment.containsKey('FLUTTER_TEST');

  bool get isSupported => Platform.isMacOS && !_underTest;
  bool get panelVisible => _panelVisible;

  /// Registers the tray icon + menu and the window hooks. Call once after the
  /// first frame. No-op off macOS.
  Future<void> setUp() async {
    if (!isSupported) return;
    trayManager.addListener(this);
    windowManager.addListener(this);

    // The red close button should hide to the menu bar, not terminate.
    await windowManager.setPreventClose(true);

    await trayManager.setIcon(_iconPath, isTemplate: true);
    await trayManager.setToolTip('SimSync');
    await trayManager.setContextMenu(_buildMenu());
  }

  Future<void> dispose() async {
    if (!isSupported) return;
    trayManager.removeListener(this);
    windowManager.removeListener(this);
  }

  Menu _buildMenu() {
    return Menu(
      items: [
        MenuItem(key: 'open_app', label: '앱 열기', onClick: (_) => unawaited(showApp())),
        MenuItem(
          key: 'settings',
          label: '설정',
          onClick: (_) => unawaited(showApp().then((_) => onOpenSettings())),
        ),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: '앱 종료', onClick: (_) => unawaited(_quit())),
      ],
    );
  }

  // ── Tray events ──

  @override
  void onTrayIconMouseDown() => unawaited(togglePanel());

  @override
  void onTrayIconRightMouseDown() => unawaited(trayManager.popUpContextMenu());

  // ── Window events ──

  @override
  void onWindowBlur() {
    // Dismiss the popover the instant focus leaves it.
    if (_panelVisible) unawaited(hidePanel());
  }

  @override
  void onWindowClose() {
    // preventClose is on, so the window is still alive: reconcile the Flutter
    // surface back to the app (so the next show isn't a frameless main window)
    // and hide it to the menu bar instead of quitting.
    _panelVisible = false;
    onShowApp();
    unawaited(windowManager.hide());
  }

  // ── Mode transitions ──

  Future<void> togglePanel() async {
    if (_panelVisible) {
      await hidePanel();
    } else {
      await showPanel();
    }
  }

  Future<void> showPanel() async {
    if (!isSupported) return;
    // Nothing to show without data — surface the app (e.g. to log in) instead.
    if (!canShowPanel()) {
      await showApp();
      return;
    }
    onShowPanel();
    // Set intent up-front so a throw mid-transition can't desync the toggle
    // (leaving _panelVisible false while the window is actually shown).
    _panelVisible = true;
    try {
      await _applyPanelWindow();
      await _positionPanel();
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {
      // A native call failed mid-transition: reconcile back to the app surface
      // so the toggle state and the visible window stay consistent.
      _panelVisible = false;
      onShowApp();
    }
  }

  Future<void> hidePanel() async {
    if (!isSupported) return;
    _panelVisible = false;
    await windowManager.hide();
  }

  Future<void> showApp() async {
    if (!isSupported) return;
    _panelVisible = false;
    onShowApp();
    await _applyAppWindow();
    await windowManager.show();
    await windowManager.focus();
  }

  // ── Window shaping ──

  Future<void> _applyPanelWindow() async {
    await windowManager.setResizable(false);
    await windowManager.setMovable(false);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setVisibleOnAllWorkspaces(true);
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.setHasShadow(true);
    await windowManager.setSize(panelSize);
  }

  Future<void> _applyAppWindow() async {
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setVisibleOnAllWorkspaces(false);
    await windowManager.setResizable(true);
    await windowManager.setMovable(true);
    await windowManager.setTitleBarStyle(
      TitleBarStyle.normal,
      windowButtonVisibility: true,
    );
    await windowManager.setSize(_appSize);
    await windowManager.center();
  }

  Future<void> _positionPanel() async {
    final iconBounds = await trayManager.getBounds();
    double dx = 8;
    if (iconBounds != null) {
      // Right-align the panel to the icon (menu bar icons sit toward the top
      // right) so it stays on-screen; clamp the left edge into view.
      dx = iconBounds.left + iconBounds.width - panelSize.width;
      if (dx < 8) dx = 8;
    }
    await windowManager.setPosition(Offset(dx, _menuBarInset));
  }

  Future<void> _quit() async {
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }
}
