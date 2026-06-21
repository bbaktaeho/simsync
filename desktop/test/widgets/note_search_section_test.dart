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
            hasActiveFilters: true,
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

  testWidgets('search field and filter button share the exact same height', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColorsExtension.light]),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: NoteSearchSection(
                query: '',
                onQueryChanged: (_) {},
                onClear: () {},
                onOpenFilters: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final searchBox = find
        .ancestor(
          of: find.byIcon(Icons.search_rounded),
          matching: find.byType(Container),
        )
        .first;
    final filterBox = find
        .ancestor(
          of: find.byIcon(Icons.tune_rounded),
          matching: find.byType(Container),
        )
        .first;

    final searchHeight = tester.getSize(searchBox).height;
    final filterHeight = tester.getSize(filterBox).height;
    expect(searchHeight, 32);
    expect(filterHeight, 32);
    expect(searchHeight, filterHeight);
  });
}
