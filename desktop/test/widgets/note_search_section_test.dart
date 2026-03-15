import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/theme/app_colors.dart';
import 'package:simsync/widgets/note_search_section.dart';

void main() {
  testWidgets('renders query and active filters and triggers callbacks', (
    WidgetTester tester,
  ) async {
    String? changedQuery;
    var clearCalls = 0;
    var filterCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColorsExtension.light]),
        home: Scaffold(
          body: NoteSearchSection(
            query: 'release',
            tag: 'work',
            startDate: DateTime(2026, 3, 1),
            endDate: DateTime(2026, 3, 10),
            onQueryChanged: (value) => changedQuery = value,
            onClear: () => clearCalls++,
            onOpenFilters: () => filterCalls++,
          ),
        ),
      ),
    );

    expect(find.text('release'), findsOneWidget);
    // Filter hint text changes when filters are active.
    expect(find.text('Search (filters active)'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'mobile');
    expect(changedQuery, 'mobile');

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pump();
    expect(filterCalls, 1);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(clearCalls, 1);
  });
}
