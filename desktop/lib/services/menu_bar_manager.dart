import 'dart:async';
import 'dart:io' show Platform, exit;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/widgets.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Adds the macOS menu bar (status bar) presence for the MAIN app window.
///
/// The main window is a normal, persistent window and is never reshaped — a
/// left click on the tray opens the calendar popover as a *separate* window
/// ([runPopoverWindow], via desktop_multi_window) so the main window stays put.
/// A right click shows a native menu (앱 열기 / 설정 / 앱 종료). Closing the main
/// window hides it to the menu bar; only "앱 종료" ends the process (the app is a
/// menu bar resident — AppDelegate returns false for terminate-after-last-close).
///
/// macOS-only: on every other platform / under `flutter test` this is a no-op.
class MenuBarManager with TrayListener, WindowListener {
  MenuBarManager({
    required this.onOpenSettings,
    required this.onToggleTheme,
    required this.isDark,
  });

  /// Opens the in-app settings dialog in the main window (after it is surfaced).
  final VoidCallback onOpenSettings;

  /// Toggles the app theme between light and dark (from the tray checkbox).
  final VoidCallback onToggleTheme;

  /// Whether the app is currently in dark mode — drives the tray checkbox state.
  final bool Function() isDark;

  static const String _iconPath = 'assets/tray/menu_bar_icon.png';
  // The popover's browse-size width (it widens itself for the editor overlay).
  static const Size popoverSize = Size(332, 500);
  // The macOS menu bar is at the very top, so a fixed top inset places the
  // popover just beneath it.
  static const double _menuBarInset = 26;

  static final bool _underTest =
      Platform.environment.containsKey('FLUTTER_TEST');

  bool get isSupported => Platform.isMacOS && !_underTest;

  /// Controller for the separate popover window, created lazily on first click.
  WindowController? _popover;
  bool _creatingPopover = false;

  Future<void> setUp() async {
    if (!isSupported) return;
    trayManager.addListener(this);
    windowManager.addListener(this);

    // The main window's red close button hides to the menu bar, not quits.
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
        MenuItem(
          key: 'open_app',
          label: '앱 열기',
          onClick: (_) => unawaited(_showMainWindow()),
        ),
        MenuItem(
          key: 'settings',
          label: '설정',
          onClick: (_) =>
              unawaited(_showMainWindow().then((_) => onOpenSettings())),
        ),
        MenuItem.separator(),
        MenuItem.checkbox(
          key: 'dark_mode',
          label: '다크 모드',
          checked: isDark(),
          onClick: (_) => onToggleTheme(),
        ),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: '앱 종료', onClick: (_) => unawaited(_quit())),
      ],
    );
  }

  /// Rebuilds the tray context menu so the "다크 모드" checkbox reflects the
  /// current theme (e.g. after it was toggled from the app's title bar button).
  Future<void> refreshMenu() async {
    if (!isSupported) return;
    await trayManager.setContextMenu(_buildMenu());
  }

  // ── Tray events ──

  @override
  void onTrayIconMouseDown() => unawaited(_openPopover());

  @override
  void onTrayIconRightMouseDown() => unawaited(trayManager.popUpContextMenu());

  // ── Main window events ──

  @override
  void onWindowClose() {
    // preventClose is on: hide the main window to the menu bar instead of
    // quitting. The app stays resident (tray + popover remain available).
    unawaited(windowManager.hide());
  }

  // ── Actions ──

  Future<void> _showMainWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  /// Left-click: open (or re-show) the separate popover window under the tray
  /// icon. The main window is untouched.
  Future<void> _openPopover() async {
    if (!isSupported) return;

    final bounds = await trayManager.getBounds();
    double dx = 8;
    if (bounds != null) {
      // Right-align the popover to the icon so it stays on-screen.
      dx = bounds.left + bounds.width - popoverSize.width;
      if (dx < 8) dx = 8;
    }
    final Offset position = Offset(dx, _menuBarInset);

    if (_popover == null) {
      if (_creatingPopover) return;
      _creatingPopover = true;
      try {
        // The popover window configures + shows itself on boot from these args.
        _popover = await WindowController.create(
          WindowConfiguration(
            arguments: 'popover:${position.dx}:${position.dy}',
            hiddenAtLaunch: true,
          ),
        );
      } finally {
        _creatingPopover = false;
      }
      return;
    }

    // Ask the existing popover window to reposition + show. If it's gone,
    // recreate it.
    try {
      await _popover!.invokeMethod('show', {
        'dx': position.dx,
        'dy': position.dy,
      });
    } catch (_) {
      _popover = null;
      await _openPopover();
    }
  }

  Future<void> _quit() async {
    // Menu bar resident: the app doesn't auto-terminate on window close, so
    // "앱 종료" ends the whole process explicitly.
    await trayManager.destroy();
    exit(0);
  }
}
