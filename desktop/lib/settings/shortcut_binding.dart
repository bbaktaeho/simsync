import 'package:flutter/services.dart';

/// Identifiers for every bindable keyboard shortcut in the app.
enum ShortcutAction {
  openSettings('설정 열기'),
  zoomIn('확대'),
  zoomOut('축소'),
  search('검색'),
  closeTab('탭 닫기'),
  formatBold('굵게'),
  formatItalic('기울임'),
  formatStrikethrough('취소선'),
  formatInlineCode('인라인 코드'),
  formatLink('링크'),
  formatCheckbox('체크박스'),
  formatHighlight('하이라이트');

  const ShortcutAction(this.label);
  final String label;
}

/// A single keyboard shortcut definition.
class ShortcutBinding {
  final ShortcutAction action;
  final LogicalKeyboardKey key;
  final bool meta;
  final bool shift;
  final bool isFixed;

  const ShortcutBinding({
    required this.action,
    required this.key,
    this.meta = false,
    this.shift = false,
    this.isFixed = false,
  });

  /// Check whether [event] matches this binding given the current modifier
  /// state. Accepting modifier state as parameters keeps the method testable
  /// without depending on HardwareKeyboard.instance.
  bool matches(
    KeyEvent event, {
    required bool isMetaPressed,
    required bool isShiftPressed,
  }) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != key) return false;
    if (meta && !isMetaPressed) return false;
    if (shift && !isShiftPressed) return false;
    return true;
  }

  /// Human-readable label such as "Cmd+=" or "Cmd+Shift+F".
  String get displayLabel {
    final parts = <String>[];
    if (meta) parts.add('Cmd');
    if (shift) parts.add('Shift');
    parts.add(_keyLabel(key));
    return parts.join('+');
  }

  ShortcutBinding copyWith({LogicalKeyboardKey? key, bool? shift}) {
    return ShortcutBinding(
      action: action,
      key: key ?? this.key,
      meta: meta,
      shift: shift ?? this.shift,
      isFixed: isFixed,
    );
  }

  /// Serialize to a storable string: "meta+shift+keyId".
  String serialize() {
    final parts = <String>[];
    if (meta) parts.add('meta');
    if (shift) parts.add('shift');
    parts.add(key.keyId.toString());
    return parts.join('+');
  }

  /// Deserialize from the format produced by [serialize].
  /// Returns null if [raw] is malformed.
  static ShortcutBinding? deserialize(String raw, ShortcutAction action,
      {required bool isFixed}) {
    final parts = raw.split('+');
    if (parts.isEmpty) return null;

    final hasMeta = parts.contains('meta');
    final hasShift = parts.contains('shift');
    final keyIdStr = parts.last;
    final keyId = int.tryParse(keyIdStr);
    if (keyId == null) return null;

    return ShortcutBinding(
      action: action,
      key: LogicalKeyboardKey(keyId),
      meta: hasMeta,
      shift: hasShift,
      isFixed: isFixed,
    );
  }

  static String _keyLabel(LogicalKeyboardKey key) {
    final label = key.keyLabel;
    if (label.length == 1) return label.toUpperCase();
    return label;
  }
}

/// Default shortcut bindings for the app.
const List<ShortcutBinding> defaultShortcutBindings = [
  ShortcutBinding(
    action: ShortcutAction.openSettings,
    key: LogicalKeyboardKey.comma,
    meta: true,
    isFixed: true,
  ),
  ShortcutBinding(
    action: ShortcutAction.zoomIn,
    key: LogicalKeyboardKey.equal,
    meta: true,
  ),
  ShortcutBinding(
    action: ShortcutAction.zoomOut,
    key: LogicalKeyboardKey.minus,
    meta: true,
  ),
  ShortcutBinding(
    action: ShortcutAction.search,
    key: LogicalKeyboardKey.keyF,
    meta: true,
    shift: true,
  ),
  ShortcutBinding(
    action: ShortcutAction.closeTab,
    key: LogicalKeyboardKey.keyW,
    meta: true,
  ),
  // Formatting shortcuts. We require shift for strikethrough, checkbox, and
  // highlight to avoid conflicts with system shortcuts like cmd+X (cut),
  // cmd+C (copy), and cmd+H (hide app on macOS).
  ShortcutBinding(
    action: ShortcutAction.formatBold,
    key: LogicalKeyboardKey.keyB,
    meta: true,
  ),
  ShortcutBinding(
    action: ShortcutAction.formatItalic,
    key: LogicalKeyboardKey.keyI,
    meta: true,
  ),
  ShortcutBinding(
    action: ShortcutAction.formatStrikethrough,
    key: LogicalKeyboardKey.keyX,
    meta: true,
    shift: true,
  ),
  ShortcutBinding(
    action: ShortcutAction.formatInlineCode,
    key: LogicalKeyboardKey.keyE,
    meta: true,
  ),
  ShortcutBinding(
    action: ShortcutAction.formatLink,
    key: LogicalKeyboardKey.keyK,
    meta: true,
  ),
  ShortcutBinding(
    action: ShortcutAction.formatCheckbox,
    key: LogicalKeyboardKey.keyC,
    meta: true,
    shift: true,
  ),
  ShortcutBinding(
    action: ShortcutAction.formatHighlight,
    key: LogicalKeyboardKey.keyH,
    meta: true,
    shift: true,
  ),
];
