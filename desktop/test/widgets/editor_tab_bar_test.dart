import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/theme/app_theme.dart';
import 'package:simsync/widgets/editor_tab_bar.dart';

Note _note({
  required String id,
  required String title,
  required DateTime date,
  StorageType storageType = StorageType.synced,
}) {
  return Note(
    id: id,
    noteDate: date,
    title: title,
    content: '',
    isDefault: false,
    tags: const [],
    createdAt: date,
    updatedAt: date,
    storageType: storageType,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<Note> tabs,
  required String? activeNoteId,
  required double width,
  ValueChanged<Note>? onSelect,
  ValueChanged<Note>? onClose,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            height: 40,
            child: EditorTabBar(
              tabs: tabs,
              activeNoteId: activeNoteId,
              onSelect: onSelect ?? (_) {},
              onClose: onClose ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders date:title labels and fires select/close callbacks', (
    tester,
  ) async {
    Note? selected;
    Note? closed;
    final tabs = [
      _note(id: 'a', title: 'Alpha', date: DateTime(2026, 6, 20)),
      _note(id: 'b', title: 'Beta', date: DateTime(2026, 5, 1)),
    ];

    await _pump(
      tester,
      tabs: tabs,
      activeNoteId: 'a',
      width: 500,
      onSelect: (n) => selected = n,
      onClose: (n) => closed = n,
    );

    // Wide tabs show the full date:title label.
    expect(find.textContaining('2026-06-20:Alpha'), findsOneWidget);
    expect(find.textContaining('2026-05-01:Beta'), findsOneWidget);

    await tester.tap(find.textContaining('Beta'));
    expect(selected?.id, 'b');

    // Only the active tab exposes a close button.
    final closeButtons = find.descendant(
      of: find.byType(EditorTabBar),
      matching: find.byIcon(Icons.close_rounded),
    );
    expect(closeButtons, findsOneWidget);
    await tester.tap(closeButtons);
    expect(closed?.id, 'a');
  });

  testWidgets('abbreviates the label to the file name when narrow', (
    tester,
  ) async {
    final tabs = [_note(id: 'a', title: 'Alpha', date: DateTime(2026, 6, 20))];

    await _pump(tester, tabs: tabs, activeNoteId: 'a', width: 104);

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.textContaining('2026'), findsNothing);
  });

  testWidgets('uses a short date at medium width', (tester) async {
    final tabs = [
      _note(id: 'a', title: 'Alpha', date: DateTime(2026, 6, 20)),
      _note(id: 'b', title: 'Beta', date: DateTime(2026, 5, 1)),
      _note(id: 'c', title: 'Gamma', date: DateTime(2026, 4, 2)),
    ];

    // 3 tabs in 390px -> 130px each -> short date form `MM-dd:title`.
    await _pump(tester, tabs: tabs, activeNoteId: 'a', width: 390);

    expect(find.textContaining('06-20:Alpha'), findsOneWidget);
    expect(find.textContaining('2026-06-20:Alpha'), findsNothing);
  });
}
