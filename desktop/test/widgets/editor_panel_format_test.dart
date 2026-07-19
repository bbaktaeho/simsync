import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/settings/shortcut_binding.dart';
import 'package:simsync/theme/app_theme.dart';
import 'package:simsync/widgets/editor_panel.dart';

Note _note(String content) {
  final now = DateTime(2026, 7, 19);
  return Note(
    id: 'n1',
    noteDate: now,
    title: 't',
    content: content,
    isDefault: true,
    tags: [],
    createdAt: now,
    updatedAt: now,
  );
}

Future<GlobalKey<EditorPanelState>> _pump(WidgetTester tester, Note note) async {
  final key = GlobalKey<EditorPanelState>();
  await tester.pumpWidget(MaterialApp(
    theme: buildLightTheme(),
    home: Scaffold(body: EditorPanel(key: key, note: note, onNoteChanged: (_) {})),
  ));
  return key;
}

TextField _contentField(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).last);

void main() {
  testWidgets('applyFormat(bold)는 선택 영역을 **로 감싼다', (tester) async {
    final key = await _pump(tester, _note('hello world'));
    final controller = _contentField(tester).controller!;
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    key.currentState!.applyFormat(ShortcutAction.formatBold);
    await tester.pump();
    expect(controller.text, '**hello** world');
  });

  testWidgets('applyFormat(strikethrough)는 ~~로 감싼다', (tester) async {
    final key = await _pump(tester, _note('abc'));
    final controller = _contentField(tester).controller!;
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
    key.currentState!.applyFormat(ShortcutAction.formatStrikethrough);
    await tester.pump();
    expect(controller.text, '~~abc~~');
  });

  testWidgets('applyFormat(checkbox)는 줄 프리픽스를 토글한다', (tester) async {
    final key = await _pump(tester, _note('todo item'));
    final controller = _contentField(tester).controller!;
    controller.selection = const TextSelection.collapsed(offset: 2);
    key.currentState!.applyFormat(ShortcutAction.formatCheckbox);
    await tester.pump();
    expect(controller.text, '- [ ] todo item');
  });

  testWidgets('applyFormat(link)는 선택을 [텍스트]()로 감싸고 캐럿을 괄호 안에 둔다',
      (tester) async {
    final key = await _pump(tester, _note('click here'));
    final controller = _contentField(tester).controller!;
    controller.selection = const TextSelection(baseOffset: 6, extentOffset: 10);
    key.currentState!.applyFormat(ShortcutAction.formatLink);
    await tester.pump();
    expect(controller.text, 'click [here]()');
    expect(controller.selection.baseOffset, 'click [here]('.length);
  });

  testWidgets('링크: 선택이 없으면 빈 링크 삽입, 캐럿은 대괄호 안', (tester) async {
    final key = await _pump(tester, _note(''));
    final controller = _contentField(tester).controller!;
    controller.selection = const TextSelection.collapsed(offset: 0);
    key.currentState!.applyFormat(ShortcutAction.formatLink);
    await tester.pump();
    expect(controller.text, '[]()');
    expect(controller.selection.baseOffset, 1);
  });
}
