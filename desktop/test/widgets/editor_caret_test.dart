import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/theme/app_theme.dart';
import 'package:simsync/widgets/editor_panel.dart';

/// 캐럿(작성 포인트) 배치 회귀 테스트.
///
/// 에디터 스트럿은 접힘(닫힌 details 본문)을 위해 완전 비활성이어야 하는데,
/// 스트럿을 "극소값(fontSize 0.1)"으로 흉내 내면 TextPainter가 스트럿을
/// 활성으로 취급해 문서 끝/빈 노트/마지막 줄의 캐럿 전체 높이가 스트럿
/// 박스(~0.1px)로 계산되고, macOS 캐럿 센터링이 캐럿을 ~12px 위로 밀어낸다
/// (v0.2.2에서 실측된 버그). _DisabledStrutStyle이 이를 막는다 — 이 테스트는
/// Flutter 업그레이드로 해당 우회가 깨질 때 즉시 드러나게 하는 안전망이다.
void main() {
  Note note(String content) {
    final now = DateTime(2026, 7, 20);
    return Note(
      id: 'n-${content.hashCode}',
      noteDate: now,
      title: 't',
      content: content,
      isDefault: true,
      tags: [],
      createdAt: now,
      updatedAt: now,
    );
  }

  Finder contentField() => find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText == 'Start writing in markdown...',
      );

  Future<RenderEditable> pumpEditor(
      WidgetTester tester, String content) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: EditorPanel(note: note(content), onNoteChanged: (_) {}),
      ),
    ));
    await tester.pump();
    final etFinder = find.descendant(
        of: contentField(), matching: find.byType(EditableText));
    return tester.state<EditableTextState>(etFinder).renderEditable;
  }

  Rect caretAt(RenderEditable re, int offset) =>
      re.getLocalRectForCaret(TextPosition(offset: offset));

  testWidgets('빈 노트의 캐럿은 필드 안 첫 줄에 있다', (tester) async {
    final re = await pumpEditor(tester, '');
    final rect = caretAt(re, 0);
    expect(rect.top, greaterThanOrEqualTo(-0.5), reason: '필드 위로 뜨면 안 된다');
    expect(rect.top, lessThan(5));
    expect(rect.height, inInclusiveRange(16, 32));
  });

  testWidgets('마지막 줄 끝의 캐럿은 줄 시작 캐럿과 같은 높이다', (tester) async {
    final re = await pumpEditor(tester, 'one\ntwo');
    final lineStart = caretAt(re, 4); // 'two' 시작
    final lineEnd = caretAt(re, 7); // 문서 끝
    expect(lineEnd.top, closeTo(lineStart.top, 1.0),
        reason: '문서 끝 캐럿이 위로 점프하면 안 된다 (v0.2.2 버그)');
  });

  testWidgets('끝 개행 뒤(고스트 줄)의 캐럿은 이전 줄 아래에 있다', (tester) async {
    final re = await pumpEditor(tester, 'hello\n');
    final line1 = caretAt(re, 0);
    final ghost = caretAt(re, 6);
    expect(ghost.top, greaterThanOrEqualTo(line1.top + 18),
        reason: '새 줄 캐럿이 이전 줄과 겹치면 안 된다');
  });

  testWidgets('닫힌 details 다음 줄의 캐럿은 접힌 높이를 반영한다', (tester) async {
    const content =
        '<details>\n<summary>t</summary>\n  hidden\n</details>\nafter';
    final re = await pumpEditor(tester, content);
    final afterStart = content.indexOf('after');
    final rect = caretAt(re, afterStart);
    // summary 한 줄(~24px)만 남고 나머지는 접히므로 'after' 캐럿은 두 번째
    // 줄 높이 근처여야 한다 (본문이 펼쳐져 있으면 3줄 이상 아래로 밀린다).
    expect(rect.top, lessThan(40));
    expect(rect.top, greaterThan(15));
  });
}
