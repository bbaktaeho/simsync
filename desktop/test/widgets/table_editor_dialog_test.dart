import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/services/markdown_editing.dart';
import 'package:simsync/theme/app_theme.dart';
import 'package:simsync/widgets/table_editor_dialog.dart';

Future<void> _open(
  WidgetTester tester, {
  MarkdownTableData? initial,
  void Function(String?)? onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                final r = await TableEditorDialog.show(context, initial: initial);
                onResult?.call(r);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('edits a cell in the grid and returns the serialized markdown', (
    tester,
  ) async {
    String? captured;
    await _open(
      tester,
      initial: MarkdownTableData(
        [
          ['H1', 'H2'],
          ['a', 'b'],
        ],
        [MarkdownTableAlign.left, MarkdownTableAlign.left],
      ),
      onResult: (r) => captured = r,
    );

    // Existing cells are pre-filled into the grid.
    expect(find.widgetWithText(TextField, 'H1'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'a'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'a'), 'X');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(captured, '| H1 | H2 |\n| --- | --- |\n| X | b |');
  });

  testWidgets('adding a row grows the grid', (tester) async {
    await _open(tester); // blank default = 3 columns × 3 rows (header + 2 body)
    expect(find.byType(TextField), findsNWidgets(9));

    await tester.tap(find.widgetWithText(OutlinedButton, '행'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(12));
  });

  testWidgets('adding a column grows the grid', (tester) async {
    await _open(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, '열'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(12)); // 4 columns × 3 rows
  });

  testWidgets('cancel closes without returning markdown', (tester) async {
    String? captured = 'sentinel';
    await _open(tester, onResult: (r) => captured = r);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.byType(TableEditorDialog), findsNothing);
    expect(captured, isNull);
  });
}
