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
  0x0B, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x00, 0x02, 0x00,
  0x00, 0x05, 0x00, 0x01, 0x7A, 0x5E, 0xAB, 0x3F, 0x00, 0x00, 0x00, 0x00,
  0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
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
    // 위젯의 외곽 Align은 밴드 전체 폭을 차지하므로 중앙 탭은 이미지를
    // 빗나간다 — 좌상단(이미지 박스 내부)을 정확히 탭해 onActivate를 태운다.
    final imageTopLeft = tester.getTopLeft(find.byType(InlineImageView));
    await tester.tapAt(imageTopLeft + const Offset(10, 10)); // 활성화
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump(const Duration(seconds: 2)); // 자동 저장 디바운스
    expect(saved, isNotNull);
    expect(saved!.content, 'text');
  });

  testWidgets('attachImageForTest는 업로드 후 태그를 삽입한다', (tester) async {
    Note? saved;
    Uint8List? uploaded;
    final key = GlobalKey<EditorPanelState>();
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: EditorPanel(
          key: key,
          note: note(''),
          onNoteChanged: (n) => saved = n,
          onLoadImage: (src) async => _png,
          onAttachImage: (bytes, ext) async {
            uploaded = bytes;
            return 'assets/img-test.$ext';
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // decodeImageFromList는 엔진 스레드 왕복이 필요해 FakeAsync 하에서는
    // 완료되지 않는다 — runAsync로 실제 이벤트 루프에서 실행한다. 삽입 후
    // 시작되는 자동 저장 Timer도 이 real zone에서 생성되므로(가짜 시계가
    // 아닌 실제 시계), pump()로 진행시키는 대신 실제 시간을 흘려보낸다.
    await tester.runAsync(() async {
      await key.currentState!.attachImageBytes(_png, 'png');
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pump();
    expect(uploaded, _png);
    expect(saved!.content,
        '<img src="assets/img-test.png" width="1" height="1">\n');
  });

  testWidgets('onAttachImage 실패 시 태그를 삽입하지 않고 스낵바를 띄운다',
      (tester) async {
    final key = GlobalKey<EditorPanelState>();
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: EditorPanel(
          key: key,
          note: note(''),
          onNoteChanged: (_) {},
          onLoadImage: (src) async => _png,
          onAttachImage: (bytes, ext) async => throw Exception('fail'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.runAsync(
        () => key.currentState!.attachImageBytes(_png, 'png'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.controller!.text, '');
  });
}
