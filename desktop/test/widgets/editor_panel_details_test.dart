import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/theme/app_theme.dart';
import 'package:simsync/widgets/editor_panel.dart';

void main() {
  Note note(String content) {
    final now = DateTime(2026, 7, 19);
    return Note(
      id: 'n1', noteDate: now, title: 't', content: content,
      isDefault: true, tags: [], createdAt: now, updatedAt: now,
    );
  }

  testWidgets('chevron 토글이 open 속성을 파일 텍스트에 쓴다', (tester) async {
    Note? saved;
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: EditorPanel(
          note: note('<details>\n<summary>t</summary>\nbody\n</details>'),
          onNoteChanged: (n) => saved = n,
        ),
      ),
    ));
    await tester.pump();
    // chevron 아이콘(접힘 상태 = 오른쪽 화살표)을 찾아 탭
    final chevron = find.byIcon(Icons.chevron_right_rounded);
    expect(chevron, findsOneWidget);
    await tester.tap(chevron);
    // 자동 저장 디바운스(1초) 경과
    await tester.pump(const Duration(seconds: 2));
    expect(saved, isNotNull);
    expect(saved!.content, contains('<details open>'));
  });

  testWidgets('chevron 토글 시 태그 줄 뒤 캐럿이 delta만큼 보정된다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: EditorPanel(
          note: note('<details>\n<summary>t</summary>\nbody\n</details>'),
          onNoteChanged: (_) {},
        ),
      ),
    ));
    await tester.pump();
    final controller =
        tester.widget<TextField>(find.byType(TextField).last).controller!;
    // "<details>\n<summary>t</summary>\nbody\n</details>" 에서 body 줄의
    // "bo|dy" 위치(오프셋 33) — 태그 줄(`<details>`, 0..9) 뒤에 있으므로
    // 토글 시 ' open' 5글자만큼 밀려야 같은 글자를 계속 가리킨다.
    controller.selection = const TextSelection.collapsed(offset: 33);
    final chevron = find.byIcon(Icons.chevron_right_rounded);
    expect(chevron, findsOneWidget);
    await tester.tap(chevron);
    await tester.pump();
    expect(controller.selection, const TextSelection.collapsed(offset: 38));
  });

  Finder contentField() => find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText == 'Start writing in markdown...',
      );

  testWidgets('닫힌 details 본문은 에디터에서 실제로 접힌다 (높이 0)', (tester) async {
    // 같은 내용의 닫힘/펼침 노트에서 본문 문자 범위의 렌더 높이를 비교한다.
    const body = 'body one\nbody two\nbody three';
    const closed = '<details>\n<summary>t</summary>\n$body\n</details>\nafter';
    const opened =
        '<details open>\n<summary>t</summary>\n$body\n</details>\nafter';

    Future<double> bodyBandHeight(String content) async {
      // 같은 위치에 다시 pump해도 EditorPanel이 노트 교체로 인식하도록
      // 내용별로 다른 id를 준다.
      final now = DateTime(2026, 7, 19);
      final n = Note(
        id: 'n-${content.hashCode}',
        noteDate: now,
        title: 't',
        content: content,
        isDefault: true,
        tags: [],
        createdAt: now,
        updatedAt: now,
      );
      await tester.pumpWidget(MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: EditorPanel(
            note: n,
            onNoteChanged: (_) {},
          ),
        ),
      ));
      await tester.pump();
      final etFinder = find.descendant(
          of: contentField(), matching: find.byType(EditableText));
      final re =
          tester.state<EditableTextState>(etFinder).renderEditable;
      final start = content.indexOf('body one');
      final end = content.indexOf('body three') + 'body three'.length;
      final boxes = re.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end));
      if (boxes.isEmpty) return 0;
      var top = double.infinity;
      var bottom = double.negativeInfinity;
      for (final b in boxes) {
        top = top < b.top ? top : b.top;
        bottom = bottom > b.bottom ? bottom : b.bottom;
      }
      return bottom - top;
    }

    final openedHeight = await bodyBandHeight(opened);
    final closedHeight = await bodyBandHeight(closed);

    expect(openedHeight, greaterThan(40), reason: '펼침: 본문 3줄이 보인다');
    expect(closedHeight, lessThan(1.5), reason: '닫힘: 본문이 실제로 접힌다');
  });

  testWidgets('chevron은 summary 제목의 왼쪽에 있다', (tester) async {
    const content = '<details>\n<summary>Fold title</summary>\nb\n</details>';
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: EditorPanel(note: note(content), onNoteChanged: (_) {}),
      ),
    ));
    await tester.pump();

    final chevron = find.byIcon(Icons.chevron_right_rounded);
    expect(chevron, findsOneWidget);
    final chevronRight = tester.getTopRight(chevron).dx;

    // summary 제목 텍스트의 시작 x = '<summary>' 투명 인덴트 폭.
    final etFinder = find.descendant(
        of: contentField(), matching: find.byType(EditableText));
    final re = tester.state<EditableTextState>(etFinder).renderEditable;
    final titleStart = content.indexOf('Fold');
    final boxes = re.getBoxesForSelection(
        TextSelection(baseOffset: titleStart, extentOffset: titleStart + 4));
    expect(boxes, isNotEmpty);
    final fieldLeft = tester.getTopLeft(etFinder).dx;
    final titleLeft = fieldLeft + boxes.first.left;

    // chevron 전체가 제목 시작점보다 왼쪽에 있어야 한다.
    expect(chevronRight, lessThanOrEqualTo(titleLeft + 0.5));
  });
}
