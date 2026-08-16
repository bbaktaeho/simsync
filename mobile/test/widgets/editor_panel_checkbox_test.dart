import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync_mobile/theme/app_theme.dart';
import 'package:simsync_mobile/widgets/editor_panel.dart';
import 'package:simsync_mobile/widgets/inline_image_view.dart';
import 'package:simsync_mobile/widgets/markdown_editing_controller.dart';

void main() {
  Future<MarkdownEditingController> pump(
    WidgetTester tester,
    String content, {
    void Function()? onChanged,
  }) async {
    final controller = MarkdownEditingController(text: content);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: EditorPanel(
          controller: controller,
          focusNode: focus,
          onChanged: onChanged,
        ),
      ),
    ));
    await tester.pump();
    return controller;
  }

  testWidgets('체크박스를 탭하면 원문의 마크 문자가 토글된다', (tester) async {
    var changed = 0;
    final controller =
        await pump(tester, '- [ ] todo', onChanged: () => changed++);

    // '- [ ] todo' 에서 '[' 오프셋은 2.
    await tester.tap(find.byKey(const ValueKey('checkbox:2')));
    await tester.pump();

    expect(controller.text, '- [x] todo');
    expect(changed, 1);
  });

  testWidgets('체크된 항목을 다시 탭하면 해제된다', (tester) async {
    final controller = await pump(tester, '- [x] done');
    await tester.tap(find.byKey(const ValueKey('checkbox:2')));
    await tester.pump();
    expect(controller.text, '- [ ] done');
  });

  testWidgets('탭해도 캐럿 위치는 그대로다', (tester) async {
    final controller = await pump(tester, '- [ ] todo');
    controller.selection = const TextSelection.collapsed(offset: 8);
    await tester.tap(find.byKey(const ValueKey('checkbox:2')));
    await tester.pump();
    expect(controller.selection, const TextSelection.collapsed(offset: 8));
  });

  testWidgets('읽기 전용이면 탭해도 바뀌지 않는다', (tester) async {
    final controller = MarkdownEditingController(text: '- [ ] todo');
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: EditorPanel(
          controller: controller,
          focusNode: focus,
          readOnly: true,
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('checkbox:2')));
    await tester.pump();
    expect(controller.text, '- [ ] todo');
  });

  testWidgets('체크박스 자리는 줄 머리에서 시작한다 (불릿이 접혀서)', (tester) async {
    await pump(tester, 'plain\n- [ ] todo');
    final et = find.byType(EditableText);
    final re = tester.state<EditableTextState>(et).renderEditable;
    double leftOf(int start, int end) {
      final boxes = re.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end));
      expect(boxes, isNotEmpty);
      return boxes.first.left;
    }

    expect((leftOf(8, 11) - leftOf(0, 5)).abs(), lessThan(1.0));
  });

  testWidgets('그려진 체크박스가 [ 글자 왼쪽 끝에 붙는다 (탭 여백이 밀지 않는다)',
      (tester) async {
    await pump(tester, '- [ ] todo');
    final et = find.byType(EditableText);
    final re = tester.state<EditableTextState>(et).renderEditable;
    final boxes = re.getBoxesForSelection(
        const TextSelection(baseOffset: 2, extentOffset: 3));
    expect(boxes, isNotEmpty);
    final bracketLeft = tester.getTopLeft(et).dx + boxes.first.left;

    // 실제로 칠해지는 사각형의 왼쪽 끝 (탭 영역이 아니라 그림 기준).
    final visual = find.descendant(
      of: find.byKey(const ValueKey('checkbox:2')),
      matching: find.byType(Container),
    );
    final drawnLeft = tester.getTopLeft(visual.first).dx;
    expect((drawnLeft - bracketLeft).abs(), lessThan(1.0));
  });

  testWidgets('표는 인라인 위젯으로 렌더된다 (원문이 사라지지 않는다)', (tester) async {
    await pump(tester, 'before\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n');
    // 표 셀 내용이 실제 위젯으로 보인다.
    expect(find.text('A'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('이미지 로더가 없으면 img 줄을 감추지 않는다 (오버레이가 없으니까)',
      (tester) async {
    const tag = '<img src="assets/a.png" width="10" height="10">';
    final controller = await pump(tester, 'x\n$tag\n');
    expect(controller.renderInlineImages, isFalse);
  });

  testWidgets('이미지 로더가 있으면 인라인 이미지로 그린다', (tester) async {
    const tag = '<img src="assets/a.png" width="10" height="10">';
    final controller = MarkdownEditingController(text: 'x\n$tag\n');
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: EditorPanel(
          controller: controller,
          focusNode: focus,
          onLoadImage: (src) async => null, // 바이트가 없어도 자리는 잡는다
        ),
      ),
    ));
    await tester.pump();

    expect(controller.renderInlineImages, isTrue);
    expect(find.byType(InlineImageView), findsOneWidget);
  });

  testWidgets('[] 입력이 - [ ] 로 펼쳐진다 (포매터 연결 확인)', (tester) async {
    final controller = await pump(tester, '');
    await tester.tap(find.byType(EditableText));
    await tester.pump();
    final state = tester.state<EditableTextState>(find.byType(EditableText));

    state.updateEditingValue(const TextEditingValue(
        text: '[', selection: TextSelection.collapsed(offset: 1)));
    await tester.pump();
    state.updateEditingValue(const TextEditingValue(
        text: '[]', selection: TextSelection.collapsed(offset: 2)));
    await tester.pump();

    expect(controller.text, '- [ ] ');
  });
}
