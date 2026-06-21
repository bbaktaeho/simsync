import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:simsync/services/markdown_editing.dart';
import 'package:simsync/theme/app_theme.dart';
import 'package:simsync/widgets/table_editor_dialog.dart';

MarkdownTableData _table() => MarkdownTableData(
      [
        ['H1', 'H2'],
        ['a', 'b'],
      ],
      [MarkdownTableAlign.left, MarkdownTableAlign.left],
    );

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
  testWidgets('opens a PlutoGrid and saves the initial table as markdown', (
    tester,
  ) async {
    String? captured;
    await _open(tester, initial: _table(), onResult: (r) => captured = r);

    expect(find.byType(PlutoGrid), findsOneWidget);

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(captured, '| H1 | H2 |\n| --- | --- |\n| a | b |');
  });

  testWidgets('captures an in-progress cell edit on save (no Enter/Tab)', (
    tester,
  ) async {
    String? captured;
    await _open(tester, initial: _table(), onResult: (r) => captured = r);

    // Enter edit mode on the 'a' body cell, type, then Save with the mouse —
    // without committing via Enter/Tab.
    await tester.tap(find.text('a'));
    await tester.tap(find.text('a')); // double-tap → editing mode
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'TYPED');
    await tester.pump();

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(captured, '| H1 | H2 |\n| --- | --- |\n| TYPED | b |');
  });

  testWidgets('adding a row serializes an extra body row', (tester) async {
    String? captured;
    await _open(tester, initial: _table(), onResult: (r) => captured = r);

    await tester.tap(find.widgetWithText(OutlinedButton, '행'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(captured, '| H1 | H2 |\n| --- | --- |\n| a | b |\n|  |  |');
  });

  testWidgets('adding a column serializes an extra column', (tester) async {
    String? captured;
    await _open(tester, initial: _table(), onResult: (r) => captured = r);

    await tester.tap(find.widgetWithText(OutlinedButton, '열'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(captured, '| H1 | H2 |  |\n| --- | --- | --- |\n| a | b |  |');
  });

  testWidgets('a blank table inserts the default skeleton', (tester) async {
    String? captured;
    await _open(tester, onResult: (r) => captured = r); // no initial

    await tester.tap(find.text('삽입'));
    await tester.pumpAndSettle();
    expect(captured, contains('Column 1'));
    expect(captured, contains('| --- |'));
  });

  testWidgets('cancel returns null', (tester) async {
    String? captured = 'sentinel';
    await _open(tester, onResult: (r) => captured = r);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(captured, isNull);
  });
}
