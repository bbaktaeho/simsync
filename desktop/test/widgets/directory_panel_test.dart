import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/theme/app_colors.dart';
import 'package:simsync/theme/app_theme.dart';
import 'package:simsync/widgets/directory_panel.dart';

Note _note({
  required String id,
  required DateTime date,
  String title = 'note',
  bool isMemo = false,
  StorageType storageType = StorageType.synced,
  DateTime? createdAt,
}) {
  final created = createdAt ?? date;
  return Note(
    id: id,
    noteDate: date,
    title: title,
    content: 'body',
    isDefault: false,
    tags: const [],
    createdAt: created,
    updatedAt: created,
    isMemo: isMemo,
    storageType: storageType,
  );
}

Future<void> _pump(
  WidgetTester tester,
  List<Note> notes, {
  DateTime? initialMonth,
  String? selectedNoteId,
  ValueChanged<Note>? onNoteTap,
  VoidCallback? onClose,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildLightTheme(),
    home: Scaffold(
      body: SizedBox(
        width: 260,
        height: 600,
        child: DirectoryPanel(
          notes: notes,
          selectedNoteId: selectedNoteId,
          initialMonth: initialMonth,
          onNoteTap: onNoteTap ?? (_) {},
          onClose: onClose,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('groupNotesByMonth', () {
    test('월은 최신순, 월 안은 날짜·생성순으로 정렬한다', () {
      final groups = groupNotesByMonth([
        _note(id: 'a', date: DateTime(2026, 7, 30)),
        _note(id: 'b', date: DateTime(2026, 8, 2)),
        _note(id: 'c', date: DateTime(2026, 8, 1)),
        _note(id: 'd', date: DateTime(2026, 7, 1)),
      ]);

      expect(groups.map((g) => g.yearMonth), ['2026-08', '2026-07']);
      expect(groups[0].notes.map((n) => n.id), ['c', 'b']);
      expect(groups[1].notes.map((n) => n.id), ['d', 'a']);
    });

    test('같은 날짜의 노트는 생성 시각 순서를 유지한다', () {
      final day = DateTime(2026, 8, 5);
      final groups = groupNotesByMonth([
        _note(id: 'late', date: day, createdAt: DateTime(2026, 8, 5, 15)),
        _note(id: 'early', date: day, createdAt: DateTime(2026, 8, 5, 9)),
      ]);

      expect(groups.single.notes.map((n) => n.id), ['early', 'late']);
    });
  });

  group('directoryEntryLabel', () {
    test('"DD: 제목" 형식으로 만든다', () {
      final note = _note(id: 'a', date: DateTime(2026, 8, 3), title: '회고');
      expect(directoryEntryLabel(note), '03: 회고');
    });

    test('빈 제목은 Untitled로 표기한다', () {
      final note = _note(id: 'a', date: DateTime(2026, 8, 17), title: '  ');
      expect(directoryEntryLabel(note), '17: Untitled');
    });
  });

  testWidgets('초기에는 initialMonth의 월만 펼쳐져 있다', (tester) async {
    await _pump(
      tester,
      [
        _note(id: 'a', date: DateTime(2026, 8, 3), title: 'august'),
        _note(id: 'b', date: DateTime(2026, 7, 9), title: 'july'),
      ],
      initialMonth: DateTime(2026, 8, 17),
    );

    expect(find.text('2026-08'), findsOneWidget);
    expect(find.text('2026-07'), findsOneWidget);
    expect(find.text('03: august'), findsOneWidget);
    expect(find.text('09: july'), findsNothing);
  });

  testWidgets('월 헤더를 탭하면 접고 펼친다', (tester) async {
    await _pump(
      tester,
      [_note(id: 'b', date: DateTime(2026, 7, 9), title: 'july')],
      initialMonth: DateTime(2026, 8, 17),
    );

    expect(find.text('09: july'), findsNothing);

    await tester.tap(find.text('2026-07'));
    await tester.pumpAndSettle();
    expect(find.text('09: july'), findsOneWidget);

    await tester.tap(find.text('2026-07'));
    await tester.pumpAndSettle();
    expect(find.text('09: july'), findsNothing);
  });

  testWidgets('전체 닫기 버튼은 펼친 월을 모두 접는다', (tester) async {
    await _pump(
      tester,
      [
        _note(id: 'a', date: DateTime(2026, 8, 3), title: 'august'),
        _note(id: 'b', date: DateTime(2026, 7, 9), title: 'july'),
      ],
      initialMonth: DateTime(2026, 8, 17),
    );
    await tester.tap(find.text('2026-07'));
    await tester.pumpAndSettle();
    expect(find.text('03: august'), findsOneWidget);
    expect(find.text('09: july'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.unfold_less_rounded));
    await tester.pumpAndSettle();

    expect(find.text('03: august'), findsNothing);
    expect(find.text('09: july'), findsNothing);
  });

  testWidgets('항목을 탭하면 onNoteTap 콜백에 해당 노트가 전달된다', (tester) async {
    Note? tapped;
    await _pump(
      tester,
      [_note(id: 'a', date: DateTime(2026, 8, 3), title: 'august')],
      initialMonth: DateTime(2026, 8, 17),
      onNoteTap: (n) => tapped = n,
    );

    await tester.tap(find.text('03: august'));
    expect(tapped?.id, 'a');
  });

  testWidgets('메모 항목은 memoAccent 색으로 표시된다', (tester) async {
    await _pump(
      tester,
      [
        _note(id: 'a', date: DateTime(2026, 8, 3), title: 'daily'),
        _note(id: 'm', date: DateTime(2026, 8, 3), title: 'quick', isMemo: true),
      ],
      initialMonth: DateTime(2026, 8, 17),
    );

    final memoText = tester.widget<Text>(find.text('03: quick'));
    final dailyText = tester.widget<Text>(find.text('03: daily'));
    expect(memoText.style?.color, AppColorsExtension.light.memoAccent);
    expect(dailyText.style?.color, isNot(AppColorsExtension.light.memoAccent));
    expect(find.byIcon(Icons.sticky_note_2_outlined), findsOneWidget);
  });

  testWidgets('로컬 노트 항목은 localAccent 글자색으로 표시된다', (tester) async {
    await _pump(
      tester,
      [
        _note(id: 's', date: DateTime(2026, 8, 3), title: 'synced'),
        _note(
          id: 'l',
          date: DateTime(2026, 8, 3),
          title: 'local',
          storageType: StorageType.local,
        ),
      ],
      initialMonth: DateTime(2026, 8, 17),
    );

    final localText = tester.widget<Text>(find.text('03: local'));
    final syncedText = tester.widget<Text>(find.text('03: synced'));
    expect(localText.style?.color, AppColorsExtension.light.localAccent);
    expect(
        syncedText.style?.color, isNot(AppColorsExtension.light.localAccent));
  });

  testWidgets('onClose가 있으면 닫기 버튼이 보이고 콜백을 태운다', (tester) async {
    var closed = false;
    await _pump(
      tester,
      const [],
      onClose: () => closed = true,
    );

    final closeButton = find.byIcon(Icons.close_rounded);
    expect(closeButton, findsOneWidget);
    await tester.tap(closeButton);
    expect(closed, isTrue);
  });

  testWidgets('onClose가 없으면 닫기 버튼이 숨는다', (tester) async {
    await _pump(tester, const []);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });
}
