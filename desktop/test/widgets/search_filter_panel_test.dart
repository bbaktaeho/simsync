import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/search/note_search_query.dart';
import 'package:simsync/theme/app_colors.dart';
import 'package:simsync/widgets/search_filter_panel.dart';

void main() {
  late NoteSearchQuery? emitted;

  Future<void> pump(
    WidgetTester tester, {
    NoteSearchQuery query = const NoteSearchQuery(),
    List<String> tags = const ['work', 'personal'],
  }) async {
    emitted = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColorsExtension.light]),
        home: Scaffold(
          body: Center(
            child: SearchFilterPanel(
              query: query,
              availableTags: tags,
              onChanged: (q) => emitted = q,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('toggling a tag chip emits the tag (multi-select)', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('work'));
    await tester.pump();
    expect(emitted!.tags, ['work']);

    await tester.tap(find.text('personal'));
    await tester.pump();
    expect(emitted!.tags, ['work', 'personal']);
  });

  testWidgets('a preset sets an inclusive date range', (tester) async {
    await pump(tester);
    await tester.tap(find.text('오늘'));
    await tester.pump();
    expect(emitted!.startDate, isNotNull);
    expect(emitted!.endDate, emitted!.startDate);
  });

  testWidgets('typing a date in the start field sets startDate', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField).first, '2026-03-05');
    await tester.pump();
    expect(emitted!.startDate, DateTime(2026, 3, 5));
  });

  testWidgets('typing an end before the start clamps the range', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField).first, '2026-05-10');
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, '2026-05-01');
    await tester.pump();
    expect(emitted!.startDate, DateTime(2026, 5, 1));
    expect(emitted!.endDate, DateTime(2026, 5, 1));
  });

  testWidgets('tapping a calendar day sets the active (start) date', (
    tester,
  ) async {
    await pump(tester);
    // The calendar opens on the current month, which always has a 15th.
    await tester.tap(find.text('15'));
    await tester.pump();
    expect(emitted!.startDate, isNotNull);
    expect(emitted!.startDate!.day, 15);
  });

  testWidgets('초기화 clears filters but keeps the text query', (tester) async {
    await pump(
      tester,
      query: const NoteSearchQuery(text: 'hello', tags: ['work']),
    );
    expect(find.text('초기화'), findsOneWidget);
    await tester.tap(find.text('초기화'));
    await tester.pump();
    expect(emitted!.tags, isEmpty);
    expect(emitted!.startDate, isNull);
    expect(emitted!.text, 'hello');
  });

  testWidgets('shows a placeholder when there are no tags', (tester) async {
    await pump(tester, tags: const []);
    expect(find.text('사용 가능한 태그가 없습니다'), findsOneWidget);
  });
}
