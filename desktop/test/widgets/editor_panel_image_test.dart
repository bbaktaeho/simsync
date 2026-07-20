import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show PointerDeviceKind;

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

  testWidgets('이미지 위에서 휠 스크롤이 에디터 스크롤로 전달된다', (tester) async {
    // 오버레이가 히트 테스트를 가로채므로 Listener가 휠을 에디터 스크롤로
    // 넘겨야 한다 (v0.2.2에서 이미지 위 스크롤이 죽어 있던 버그).
    final filler = List.generate(60, (i) => 'line $i').join('\n');
    await pump(tester, note('$img\n$filler'));
    await tester.pumpAndSettle();

    final scrollable = find
        .descendant(
            of: find.byWidgetPredicate((w) =>
                w is TextField &&
                w.decoration?.hintText == 'Start writing in markdown...'),
            matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.pixels, 0);

    // 이미지 박스 안쪽에 포인터를 두고 휠을 굴린다.
    final target =
        tester.getTopLeft(find.byType(InlineImageView)) + const Offset(10, 10);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(target);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await tester.pump();

    expect(position.pixels, greaterThan(0),
        reason: '이미지 위에서도 에디터가 스크롤되어야 한다');
  });

  testWidgets('이미지 위 트랙패드 두 손가락 스크롤도 에디터 스크롤로 전달된다',
      (tester) async {
    // macOS 트랙패드는 휠(PointerScrollEvent)이 아니라 팬줌(PointerPanZoom)
    // 이벤트를 보낸다 — v0.2.2 수정이 휠만 다뤄 트랙패드에서 여전히 죽어
    // 있던 버그의 회귀 테스트.
    final filler = List.generate(60, (i) => 'line $i').join('\n');
    await pump(tester, note('$img\n$filler'));
    await tester.pumpAndSettle();

    final scrollable = find
        .descendant(
            of: find.byWidgetPredicate((w) =>
                w is TextField &&
                w.decoration?.hintText == 'Start writing in markdown...'),
            matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.pixels, 0);

    final target =
        tester.getTopLeft(find.byType(InlineImageView)) + const Offset(10, 10);
    final pointer = TestPointer(2, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(pointer.panZoomStart(target));
    await tester.sendEventToBinding(
        pointer.panZoomUpdate(target, pan: const Offset(0, -120)));
    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pump();

    expect(position.pixels, greaterThan(0),
        reason: '트랙패드 스크롤도 이미지 위에서 동작해야 한다');
  });

  testWidgets('이미지 오버레이 레이어는 ClipRect로 감싸여 에디터 밖으로 새지 않는다',
      (tester) async {
    // CustomMultiChildLayout은 자식 페인트를 클리핑하지 않으므로, 스크롤로
    // 밴드가 뷰포트를 벗어나면 ClipRect가 없을 때 이미지가 에디터 영역
    // 밖까지 그려진다 (v0.2.1 버그).
    await pump(tester, note('$img\ntext'));
    await tester.pumpAndSettle();
    expect(
      find.ancestor(
          of: find.byType(InlineImageView), matching: find.byType(ClipRect)),
      findsWidgets,
    );
  });

  testWidgets('큰 이미지도 윗줄을 침범하지 않는다 (상단 고정, 아래로만 확장)',
      (tester) async {
    // 예약 글리프의 잉크가 라인 박스를 위로 넘치면 밴드 top이 윗줄까지
    // 올라가 이미지가 위 텍스트를 덮는다 — 이미지가 클수록 침범이 커진다.
    const bigImg = '<img src="assets/a.png" width="450" height="300">';
    const content = 'above text\n\n$bigImg\n\nbelow';
    await pump(tester, note(content));
    await tester.pumpAndSettle();

    final etFinder = find.descendant(
        of: find.byWidgetPredicate((w) =>
            w is TextField &&
            w.decoration?.hintText == 'Start writing in markdown...'),
        matching: find.byType(EditableText));
    final re = tester.state<EditableTextState>(etFinder).renderEditable;
    final aboveStart = content.indexOf('above');
    final aboveBoxes = re.getBoxesForSelection(TextSelection(
        baseOffset: aboveStart, extentOffset: aboveStart + 'above text'.length));
    final aboveBottom =
        aboveBoxes.map((b) => b.bottom).reduce((a, b) => a > b ? a : b);

    final fieldTop = tester.getTopLeft(etFinder).dy;
    final overlayTop = tester.getTopLeft(find.byType(InlineImageView)).dy;

    expect(overlayTop - fieldTop, greaterThanOrEqualTo(aboveBottom - 1),
        reason: '이미지 상단이 윗줄 텍스트 아래에 있어야 한다');
  });

  testWidgets('큰 이미지도 아랫줄을 침범하지 않는다', (tester) async {
    // 밴드 측정이 잉크 경계(tight)면 큰 예약 줄에서 라인 박스와 어긋나
    // 이미지가 아래 텍스트를 덮을 수 있다 — selectionHeightStyle.max로
    // 밴드를 정확한 라인 박스로 만든 것에 대한 회귀 테스트.
    const bigImg = '<img src="assets/a.png" width="450" height="300">';
    const content = 'above text\n\n$bigImg\n\nbelow text';
    await pump(tester, note(content));
    await tester.pumpAndSettle();

    final etFinder = find.descendant(
        of: find.byWidgetPredicate((w) =>
            w is TextField &&
            w.decoration?.hintText == 'Start writing in markdown...'),
        matching: find.byType(EditableText));
    final re = tester.state<EditableTextState>(etFinder).renderEditable;
    final belowStart = content.indexOf('below');
    final belowBoxes = re.getBoxesForSelection(TextSelection(
        baseOffset: belowStart, extentOffset: belowStart + 'below text'.length));
    final belowTop =
        belowBoxes.map((b) => b.top).reduce((a, b) => a < b ? a : b);

    final fieldTop = tester.getTopLeft(etFinder).dy;
    final overlayBottom =
        tester.getBottomLeft(find.byType(InlineImageView)).dy;

    expect(overlayBottom - fieldTop, lessThanOrEqualTo(belowTop + 1),
        reason: '이미지 하단이 아랫줄 텍스트 위에 있어야 한다');
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

  testWidgets('줄 중간에서 첨부해도 줄을 쪼개지 않고 앞뒤 빈 줄과 함께 삽입된다',
      (tester) async {
    Note? saved;
    final key = GlobalKey<EditorPanelState>();
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: EditorPanel(
          key: key,
          note: note('abc\ndef'),
          onNoteChanged: (n) => saved = n,
          onLoadImage: (src) async => _png,
          onAttachImage: (bytes, ext) async => 'assets/img-test.$ext',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // 캐럿을 'abc' 중간(offset 1)에 둔다.
    final field = tester.widget<TextField>(find.byType(TextField).last);
    field.controller!.selection = const TextSelection.collapsed(offset: 1);
    await tester.runAsync(() async {
      await key.currentState!.attachImageBytes(_png, 'png');
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pump();
    // 'abc'는 쪼개지지 않고, 태그는 줄 끝 뒤에 빈 줄과 함께 들어간다.
    expect(saved!.content,
        'abc\n\n<img src="assets/img-test.png" width="1" height="1">\n\ndef');
  });

  testWidgets('앞뒤에 이미 빈 줄이 있으면 추가하지 않는다', (tester) async {
    Note? saved;
    final key = GlobalKey<EditorPanelState>();
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: EditorPanel(
          key: key,
          note: note('abc\n\n\n\ndef'),
          onNoteChanged: (n) => saved = n,
          onLoadImage: (src) async => _png,
          onAttachImage: (bytes, ext) async => 'assets/img-test.$ext',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // 캐럿을 두 번째 빈 줄(offset 5)에 둔다: 'abc\n' + '' + '\n' + ...
    final field = tester.widget<TextField>(find.byType(TextField).last);
    field.controller!.selection = const TextSelection.collapsed(offset: 5);
    await tester.runAsync(() async {
      await key.currentState!.attachImageBytes(_png, 'png');
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pump();
    // 기존 빈 줄을 재사용하고 이중 빈 줄을 쌓지 않는다.
    expect(saved!.content,
        'abc\n\n<img src="assets/img-test.png" width="1" height="1">\n\ndef');
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

  testWidgets('업로드 중 노트가 바뀌면 새 노트에 태그를 삽입하지 않는다',
      (tester) async {
    final noteA = note('');
    final now = DateTime(2026, 7, 19);
    final noteB = Note(
      id: 'n2', noteDate: now, title: 'other', content: '',
      isDefault: false, tags: [], createdAt: now, updatedAt: now,
    );
    final completer = Completer<String>();
    final key = GlobalKey<EditorPanelState>();

    Widget build(Note n) => MaterialApp(
          theme: buildLightTheme(),
          home: Scaffold(
            body: EditorPanel(
              key: key,
              note: n,
              onNoteChanged: (_) {},
              onLoadImage: (src) async => _png,
              onAttachImage: (bytes, ext) => completer.future,
            ),
          ),
        );

    await tester.pumpWidget(build(noteA));
    await tester.pumpAndSettle();

    // 업로드(onAttachImage)가 완료되기 전 상태로 첨부를 시작한다.
    late Future<void> attach;
    await tester.runAsync(() async {
      attach = key.currentState!.attachImageBytes(_png, 'png');
      // decodeImageFromList가 끝나고 onAttach await에 도달할 시간을 준다.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    // 업로드가 끝나기 전에 다른 노트로 전환한다 (State는 재사용됨).
    await tester.pumpWidget(build(noteB));
    await tester.pumpAndSettle();

    // 이제 업로드가 완료된다 — 태그는 어디에도 삽입되면 안 된다.
    await tester.runAsync(() async {
      completer.complete('assets/img-late.png');
      await attach;
    });
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.controller!.text, isNot(contains('<img')));
  });
}
