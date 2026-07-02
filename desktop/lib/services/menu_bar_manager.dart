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
    required this.onNotesChanged,
  });

  /// Opens the in-app settings dialog in the main window (after it is surfaced).
  final VoidCallback onOpenSettings;

  /// Toggles the app theme between light and dark (from the tray checkbox).
  final VoidCallback onToggleTheme;

  /// Whether the app is currently in dark mode — drives the tray checkbox state.
  final bool Function() isDark;

  /// Fired when the popover window reports it persisted a note edit
  /// (`notes_changed` over the multi-window channel), so the document screen
  /// reloads immediately instead of waiting for the next sync poll.
  final VoidCallback onNotesChanged;

  static const String _iconPath = 'assets/tray/menu_bar_icon.png';

  /// Single source of truth for the popover geometry — the popover window
  /// sizes itself with these AND this manager anchors it to the tray icon, so
  /// the two sides must never drift.
  static const Size popoverSize = Size(332, 500);

  /// The popover widens to this while its editor overlay is open (the reused
  /// editor toolbar needs ~386px), then shrinks back to [popoverSize].
  static const Size popoverEditSize = Size(420, 520);

  // Fallback top inset when the tray bounds are unavailable; normally the
  // popover hangs from the tray icon's bottom edge (menu bar height varies:
  // ~24pt on plain displays, ~32-38pt on notched/scaled ones).
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

    // Receive the popover's note-change pings on this (main) window's channel.
    final self = await WindowController.fromCurrentEngine();
    await self.setWindowMethodHandler((call) async {
      if (call.method == 'notes_changed') onNotesChanged();
      return null;
    });
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
    double dy = _menuBarInset;
    if (bounds != null) {
      // Right-align the popover to the icon so it stays on-screen, and hang it
      // from the icon's bottom edge (= the actual menu bar height, which
      // differs per display instead of being a fixed inset).
      dx = bounds.left + bounds.width - popoverSize.width;
      if (dx < 8) dx = 8;
      if (bounds.bottom > 0) dy = bounds.bottom;
    }
    final Offset position = Offset(dx, dy);

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

    // Ask the existing popover window to reposition + show.
    try {
      await _popover!.invokeMethod('show', {
        'dx': position.dx,
        'dy': position.dy,
      });
    } on WindowChannelException {
      // The window exists but hasn't registered its handler yet — it is still
      // booting (storage/session restore takes a moment) and will show itself
      // after its first frame. Recreating here would spawn a duplicate popover
      // for every impatient extra click, so just drop this one.
      return;
    } catch (_) {
      // Anything else means the window is actually gone: recreate it.
      _popover = null;
      await _openPopover();
    }
  }

  /// Pushes a remote-change notification to the popover (if it exists) so an
  /// open popover refreshes live. The popover intentionally runs no poll loop
  /// of its own — the main engine already polls this repo.
  Future<void> notifyPopoverRemoteChanged() async {
    final popover = _popover;
    if (popover == null) return;
    try {
      await popover.invokeMethod('remote_changed');
    } catch (_) {
      // Popover still booting or gone; it reloads on its next show anyway.
    }
  }

  Future<void> _quit() async {
    // Give the popover a chance to persist a still-debounced edit before the
    // process dies (its save debounce is 1s; exit(0) would drop the edit).
    final popover = _popover;
    if (popover != null) {
      try {
        await popover
            .invokeMethod('flush')
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        // Booting/gone/timed out — quit anyway.
      }
    }
    // Menu bar resident: the app doesn't auto-terminate on window close, so
    // "앱 종료" ends the whole process explicitly.
    await trayManager.destroy();
    exit(0);
  }
}
