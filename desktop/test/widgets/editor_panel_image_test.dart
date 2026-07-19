import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/theme/app_theme.dart';
import 'package:simsync/widgets/editor_panel.dart';
import 'package:simsync/widgets/inline_image_view.dart';

// 1x1 투명 PNG
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  Note note(String content) {
    final now = DateTime(2026, 7, 19);
    return Note(
      id: 'n1', noteDate: now, title: 't', content: content,
      isDefault: true, tags: [], createdAt: now, updatedAt: now,
    );
  }

  const img = '<img src="assets/a.png" width="120" height="80">';

  Future<void> pump(WidgetTester tester, Note n, {ValueChanged<Note>? onChanged}) {
    return tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: EditorPanel(
          note: n,
          onNoteChanged: onChanged ?? (_) {},
          onLoadImage: (src) async => _png,
        ),
      ),
    ));
  }

  testWidgets('img 태그 노트는 InlineImageView 오버레이를 그린다', (tester) async {
    await pump(tester, note('$img\ntext'));
    await tester.pumpAndSettle();
    expect(find.byType(InlineImageView), findsOneWidget);
  });

  testWidgets('onLoadImage가 없으면 오버레이를 만들지 않는다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(body: EditorPanel(note: note(img), onNoteChanged: (_) {})),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(InlineImageView), findsNothing);
  });

  testWidgets('활성 이미지의 X 버튼은 태그 줄을 삭제한다', (tester) async {
    Note? saved;
    await pump(tester, note('$img\ntext'), onChanged: (n) => saved = n);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(InlineImageView)); // 활성화
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump(const Duration(seconds: 2)); // 자동 저장 디바운스
    expect(saved, isNotNull);
    expect(saved!.content, 'text');
  });
}
