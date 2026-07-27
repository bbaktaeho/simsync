import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/theme/app_theme.dart';
import 'package:simsync/widgets/note_list_section.dart';

Note _note({
  required String id,
  required String title,
  required StorageType storageType,
}) {
  final now = DateTime(2026, 7, 21, 9);
  return Note(
    id: id,
    noteDate: DateTime(2026, 7, 21),
    title: title,
    content: 'body',
    isDefault: false,
    tags: const [],
    createdAt: now,
    updatedAt: now,
    storageType: storageType,
  );
}

Future<void> _pump(
  WidgetTester tester,
  List<Note> notes, {
  Future<void> Function(Note)? onConvertToSynced,
  Future<void> Function(Note)? onConvertToLocal,
  void Function({bool memo})? onCreateSyncNote,
  void Function({bool memo})? onCreateLocalNote,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildLightTheme(),
    home: Scaffold(
      body: SizedBox(
        width: 320,
        height: 500,
        child: NoteListSection(
          notes: notes,
          selectedNoteId: null,
          currentPage: 0,
          totalPages: 1,
          totalCount: notes.length,
          onNoteSelected: (_) {},
          onCreateSyncNote: onCreateSyncNote ?? ({bool memo = false}) {},
          onCreateLocalNote: onCreateLocalNote,
          onPageChanged: (_) {},
          onConvertToSynced: onConvertToSynced,
          onConvertToLocal: onConvertToLocal,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('로컬 노트 우클릭 메뉴에 "동기화 노트로 전환"이 있고 콜백을 태운다',
      (tester) async {
    Note? converted;
    await _pump(
      tester,
      [_note(id: 'l1', title: 'local note', storageType: StorageType.local)],
      onConvertToSynced: (n) async => converted = n,
    );

    await tester.tap(find.text('local note'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    final item = find.text('동기화 노트로 전환');
    expect(item, findsOneWidget);
    await tester.tap(item);
    await tester.pumpAndSettle();

    expect(converted, isNotNull);
    expect(converted!.id, 'l1');
  });

  testWidgets('동기화 노트 우클릭 메뉴에는 동기화 전환 항목이 없다', (tester) async {
    await _pump(
      tester,
      [_note(id: 's1', title: 'synced note', storageType: StorageType.synced)],
      onConvertToSynced: (_) async {},
    );

    await tester.tap(find.text('synced note'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text('동기화 노트로 전환'), findsNothing);
  });

  testWidgets('동기화 노트 우클릭 메뉴에 "로컬 노트로 전환"이 있고 콜백을 태운다',
      (tester) async {
    Note? converted;
    await _pump(
      tester,
      [_note(id: 's1', title: 'synced note', storageType: StorageType.synced)],
      onConvertToLocal: (n) async => converted = n,
    );

    await tester.tap(find.text('synced note'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    final item = find.text('로컬 노트로 전환');
    expect(item, findsOneWidget);
    await tester.tap(item);
    await tester.pumpAndSettle();

    expect(converted?.id, 's1');
  });

  testWidgets('로컬 노트 우클릭 메뉴에는 로컬 전환 항목이 없다', (tester) async {
    await _pump(
      tester,
      [_note(id: 'l1', title: 'local note', storageType: StorageType.local)],
      onConvertToLocal: (_) async {},
    );

    await tester.tap(find.text('local note'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text('로컬 노트로 전환'), findsNothing);
  });

  testWidgets('추가 메뉴에서 메모를 곧바로 생성할 수 있다 (동기화/로컬)', (tester) async {
    final created = <String>[];
    await _pump(
      tester,
      const [],
      onCreateSyncNote: ({bool memo = false}) =>
          created.add(memo ? 'sync_memo' : 'sync'),
      onCreateLocalNote: ({bool memo = false}) =>
          created.add(memo ? 'local_memo' : 'local'),
    );

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    expect(find.text('동기화 노트'), findsOneWidget);
    expect(find.text('로컬 노트'), findsOneWidget);
    expect(find.text('로컬 메모'), findsOneWidget);

    await tester.tap(find.text('동기화 메모'));
    await tester.pumpAndSettle();
    expect(created, ['sync_memo']);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('로컬 메모'));
    await tester.pumpAndSettle();
    expect(created, ['sync_memo', 'local_memo']);
  });

  testWidgets('로컬 콜백이 없으면 로컬 항목이 메뉴에서 숨는다', (tester) async {
    await _pump(tester, const []);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    expect(find.text('동기화 노트'), findsOneWidget);
    expect(find.text('동기화 메모'), findsOneWidget);
    expect(find.text('로컬 노트'), findsNothing);
    expect(find.text('로컬 메모'), findsNothing);
  });

  testWidgets('onConvertToSynced가 null이면 전환 항목이 없다', (tester) async {
    await _pump(
      tester,
      [_note(id: 'l1', title: 'local note', storageType: StorageType.local)],
      onConvertToSynced: null,
    );

    await tester.tap(find.text('local note'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text('동기화 노트로 전환'), findsNothing);
  });
}
