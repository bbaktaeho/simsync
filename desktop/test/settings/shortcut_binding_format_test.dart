import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/settings/shortcut_binding.dart';

ShortcutBinding _bindingFor(ShortcutAction action) =>
    defaultShortcutBindings.firstWhere((b) => b.action == action);

void main() {
  test('포맷 액션 7종의 기본 바인딩이 존재한다', () {
    expect(_bindingFor(ShortcutAction.formatBold).key, LogicalKeyboardKey.keyB);
    expect(_bindingFor(ShortcutAction.formatBold).meta, isTrue);
    expect(_bindingFor(ShortcutAction.formatBold).shift, isFalse);

    expect(_bindingFor(ShortcutAction.formatItalic).key, LogicalKeyboardKey.keyI);

    final strike = _bindingFor(ShortcutAction.formatStrikethrough);
    expect(strike.key, LogicalKeyboardKey.keyX);
    expect(strike.meta, isTrue);
    expect(strike.shift, isTrue, reason: 'cmd+X(잘라내기) 충돌 회피');

    expect(_bindingFor(ShortcutAction.formatInlineCode).key, LogicalKeyboardKey.keyE);
    expect(_bindingFor(ShortcutAction.formatLink).key, LogicalKeyboardKey.keyK);

    final checkbox = _bindingFor(ShortcutAction.formatCheckbox);
    expect(checkbox.key, LogicalKeyboardKey.keyC);
    expect(checkbox.shift, isTrue);

    final highlight = _bindingFor(ShortcutAction.formatHighlight);
    expect(highlight.key, LogicalKeyboardKey.keyH);
    expect(highlight.shift, isTrue);
  });

  test('shift 필수 바인딩은 shift 없이 매칭되지 않는다', () {
    final strike = _bindingFor(ShortcutAction.formatStrikethrough);
    final event = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyX,
      logicalKey: LogicalKeyboardKey.keyX,
      timeStamp: Duration.zero,
    );
    expect(strike.matches(event, isMetaPressed: true, isShiftPressed: true), isTrue);
    expect(strike.matches(event, isMetaPressed: true, isShiftPressed: false), isFalse);
  });
}
