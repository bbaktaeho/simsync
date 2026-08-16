import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/theme/app_theme.dart';
import 'package:simsync/widgets/editor_panel.dart';

void main() {
  Note note(String content) {
    final now = DateTime(2026, 8, 15);
    return Note(
      id: 'n1', noteDate: now, title: 't', content: content,
      isDefault: true, tags: [], createdAt: now, updatedAt: now,
    );
  }

  Finder contentField() => find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText == 'Start writing in markdown...',
      );

  TextEditingController controllerOf(WidgetTester tester) =>
      tester.widget<TextField>(contentField()).controller!;

  Future<void> pumpEditor(
    WidgetTester tester,
    String content, {
    void Function(Note)? onChanged,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: EditorPanel(
          note: note(content),
          onNoteChanged: onChanged ?? (_) {},
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('체크박스를 클릭하면 원문의 마크 문자가 토글된다', (tester) async {
    Note? saved;
    await pumpEditor(tester, '- [ ] todo', onChanged: (n) => saved = n);

    // '- [ ] todo' 에서 '[' 오프셋은 2.
    await tester.tap(find.byKey(const ValueKey('checkbox:2')));
    await tester.pump(const Duration(seconds: 2)); // 자동 저장 디바운스

    expect(saved, isNotNull);
    expect(saved!.content, '- [x] todo');
  });

  testWidgets('체크된 항목을 다시 클릭하면 해제된다', (tester) async {
    await pumpEditor(tester, '- [x] done');
    await tester.tap(find.byKey(const ValueKey('checkbox:2')));
    await tester.pump();
    expect(controllerOf(tester).text, '- [ ] done');
  });

  testWidgets('클릭해도 캐럿 위치는 그대로다', (tester) async {
    await pumpEditor(tester, '- [ ] todo');
    final controller = controllerOf(tester);
    controller.selection = const TextSelection.collapsed(offset: 8);
    await tester.tap(find.byKey(const ValueKey('checkbox:2')));
    await tester.pump();
    expect(controller.selection, const TextSelection.collapsed(offset: 8));
  });

  testWidgets('체크박스는 여는 대괄호가 시작하는 자리에 그려진다', (tester) async {
    // 왼쪽 정렬이라 폰트 폭과 무관하게 항상 `[` 글자의 왼쪽 끝에 붙는다.
    // (세 글자 박스에 가운데 정렬하면 박스가 넓게 잡힐 때 오른쪽으로 밀린다.)
    await pumpEditor(tester, '- [ ] todo');

    final etFinder =
        find.descendant(of: contentField(), matching: find.byType(EditableText));
    final re = tester.state<EditableTextState>(etFinder).renderEditable;
    final boxes = re.getBoxesForSelection(
        const TextSelection(baseOffset: 2, extentOffset: 3));
    expect(boxes, isNotEmpty);
    final bracketLeft = tester.getTopLeft(etFinder).dx + boxes.first.left;

    final drawnLeft =
        tester.getTopLeft(find.byKey(const ValueKey('checkbox:2'))).dx;
    expect((drawnLeft - bracketLeft).abs(), lessThan(1.0));
  });

  testWidgets('체크박스를 눌러도 에디터 포커스가 유지된다', (tester) async {
    // 데스크톱에서만 "필드 밖 탭 = 포커스 해제"가 돈다. 테스트 기본 플랫폼은
    // android라 오버라이드하지 않으면 이 검증이 무의미해진다. (오버라이드는
    // 테스트 본문 안에서 되돌려야 한다 — 프레임워크가 종료 직후 검사한다.)
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await pumpEditor(tester, '- [ ] todo');
    await tester.tap(contentField());
    await tester.pump();
    final node = tester
        .widget<EditableText>(find.descendant(
            of: contentField(), matching: find.byType(EditableText)))
        .focusNode;
    final before = node.hasFocus;

    await tester.tap(find.byKey(const ValueKey('checkbox:2')));
    await tester.pump();
    final after = node.hasFocus;
    debugDefaultTargetPlatformOverride = null;

    expect(before, isTrue);
    expect(after, isTrue,
        reason: 'TextFieldTapRegion이 빠지면 체크만 눌러도 캐럿이 사라진다');
  });

  testWidgets('닫힌 details 안의 체크박스는 화면 밖으로 치운다', (tester) async {
    await pumpEditor(
      tester,
      '<details>\n<summary>t</summary>\n- [ ] hidden\n</details>',
    );
    final start = '<details>\n<summary>t</summary>\n- '.length;
    final box = find.byKey(ValueKey('checkbox:$start'));
    expect(box, findsOneWidget);
    // 접힌 줄(밴드 높이 ~0)의 오버레이는 델리게이트가 화면 밖으로 보낸다.
    expect(tester.getTopLeft(box).dy, lessThan(-1000));
  });

  testWidgets('체크박스 자리는 줄 머리에서 시작한다 (불릿이 접혀서)', (tester) async {
    // 폭 비교는 테스트 폰트(모든 글자가 정사각형)에 좌우되므로, 체크박스가
    // 그려지는 대괄호 박스의 시작 x를 일반 텍스트 줄의 시작 x와 비교한다.
    await pumpEditor(tester, 'plain\n- [ ] todo');
    final etFinder =
        find.descendant(of: contentField(), matching: find.byType(EditableText));
    final re = tester.state<EditableTextState>(etFinder).renderEditable;
    double leftOf(int start, int end) {
      final boxes = re.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end));
      expect(boxes, isNotEmpty);
      return boxes.first.left;
    }

    // 'plain' 줄의 시작 vs '- [ ] todo' 줄의 `[ ]` 시작.
    expect((leftOf(8, 11) - leftOf(0, 5)).abs(), lessThan(1.0));
    // 불릿 두 글자는 폭이 사실상 0이다.
    expect(leftOf(6, 8), lessThan(leftOf(8, 11) + 0.5));
  });

  testWidgets('읽기 전용이면 클릭해도 바뀌지 않는다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: EditorPanel(
          note: note('- [ ] todo'),
          onNoteChanged: (_) {},
          isReadOnly: true,
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('checkbox:2')));
    await tester.pump();
    expect(controllerOf(tester).text, '- [ ] todo');
  });

  testWidgets('Tab이 리스트 줄을 한 단계 들여쓴다', (tester) async {
    await pumpEditor(tester, '- a\n- ');
    await tester.tap(contentField());
    await tester.pump();
    final controller = controllerOf(tester);
    controller.selection = const TextSelection.collapsed(offset: 6);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(controller.text, '- a\n  - ');
    expect(controller.selection, const TextSelection.collapsed(offset: 8));
  });

  testWidgets('Shift+Tab은 들여쓰기를 되돌린다', (tester) async {
    await pumpEditor(tester, '- a\n  - b');
    await tester.tap(contentField());
    await tester.pump();
    final controller = controllerOf(tester);
    controller.selection = const TextSelection.collapsed(offset: 9);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(controller.text, '- a\n- b');
  });

  testWidgets('리스트가 아닌 줄에서는 Tab이 텍스트를 바꾸지 않는다', (tester) async {
    await pumpEditor(tester, 'plain line');
    await tester.tap(contentField());
    await tester.pump();
    controllerOf(tester).selection =
        const TextSelection.collapsed(offset: 5);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(controllerOf(tester).text, 'plain line');
  });
}
