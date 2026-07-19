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
}
