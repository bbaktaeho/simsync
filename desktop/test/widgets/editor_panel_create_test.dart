import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/theme/app_theme.dart';
import 'package:simsync/widgets/editor_panel.dart';

Future<void> _pumpCreateScreen(
  WidgetTester tester, {
  void Function({bool memo})? onCreateNote,
  void Function({bool memo})? onCreateLocalNote,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildLightTheme(),
    home: Scaffold(
      body: EditorPanel(
        note: null, // note가 없으면 생성 화면이 뜬다
        selectedDate: DateTime(2026, 7, 28),
        onNoteChanged: (_) {},
        onCreateNote: onCreateNote,
        onCreateLocalNote: onCreateLocalNote,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('생성 화면에 노트 2개 + 메모 2개 버튼이 있다', (tester) async {
    await _pumpCreateScreen(
      tester,
      onCreateNote: ({bool memo = false}) {},
      onCreateLocalNote: ({bool memo = false}) {},
    );

    expect(find.text('동기화 노트'), findsOneWidget);
    expect(find.text('로컬 노트'), findsOneWidget);
    expect(find.text('동기화 메모'), findsOneWidget);
    expect(find.text('로컬 메모'), findsOneWidget);
  });

  testWidgets('메모 버튼은 memo:true로, 노트 버튼은 memo:false로 호출한다',
      (tester) async {
    final calls = <String>[];
    await _pumpCreateScreen(
      tester,
      onCreateNote: ({bool memo = false}) =>
          calls.add(memo ? 'sync_memo' : 'sync_note'),
      onCreateLocalNote: ({bool memo = false}) =>
          calls.add(memo ? 'local_memo' : 'local_note'),
    );

    await tester.tap(find.text('동기화 노트'));
    await tester.tap(find.text('로컬 노트'));
    await tester.tap(find.text('동기화 메모'));
    await tester.tap(find.text('로컬 메모'));
    await tester.pump();

    expect(calls, ['sync_note', 'local_note', 'sync_memo', 'local_memo']);
  });

  testWidgets('노트/메모 버튼은 같은 크기다', (tester) async {
    await _pumpCreateScreen(
      tester,
      onCreateNote: ({bool memo = false}) {},
      onCreateLocalNote: ({bool memo = false}) {},
    );

    // 라벨 길이가 같으므로 동기화 노트/메모, 로컬 노트/메모가 각각 같은 폭이어야
    // 한다 (첫 화면에서 두 줄이 어긋나 보이지 않도록).
    Size sizeOf(String label) =>
        tester.getSize(find.ancestor(
          of: find.text(label),
          matching: find.byType(Container),
        ).first);

    expect(sizeOf('동기화 메모'), sizeOf('동기화 노트'));
    expect(sizeOf('로컬 메모'), sizeOf('로컬 노트'));
  });

  testWidgets('로컬 콜백이 없으면 로컬 노트/메모 버튼이 숨는다', (tester) async {
    await _pumpCreateScreen(tester, onCreateNote: ({bool memo = false}) {});

    expect(find.text('동기화 노트'), findsOneWidget);
    expect(find.text('동기화 메모'), findsOneWidget);
    expect(find.text('로컬 노트'), findsNothing);
    expect(find.text('로컬 메모'), findsNothing);
  });
}
