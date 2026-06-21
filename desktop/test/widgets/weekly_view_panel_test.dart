import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/theme/app_theme.dart';
import 'package:simsync/widgets/weekly_view_panel.dart';

Future<void> _pump(
  WidgetTester tester, {
  required bool claudeEnabled,
  Future<String> Function()? onGenerate,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: SizedBox(
          width: 820,
          height: 640,
          child: WeeklyViewPanel(
            weekStart: DateTime(2026, 6, 15),
            weekNotes: const [],
            claudeEnabled: claudeEnabled,
            onGenerateSummary: onGenerate,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Generate button appears only when the summary is enabled', (
    tester,
  ) async {
    await _pump(tester, claudeEnabled: false, onGenerate: () async => 'x');
    expect(find.text('Generate'), findsNothing);

    await _pump(tester, claudeEnabled: true, onGenerate: () async => 'x');
    expect(find.text('Generate'), findsOneWidget);
  });

  testWidgets('pressing Generate shows the returned summary', (tester) async {
    await _pump(
      tester,
      claudeEnabled: true,
      onGenerate: () async => 'This week was productive.',
    );

    await tester.tap(find.text('Generate'));
    await tester.pump(); // enter loading
    await tester.pumpAndSettle(); // resolve the future

    expect(find.textContaining('productive'), findsWidgets);
    // The button flips to Regenerate once there's a result.
    expect(find.text('Regenerate'), findsOneWidget);
  });

  testWidgets('pressing Generate surfaces an error message', (tester) async {
    await _pump(
      tester,
      claudeEnabled: true,
      onGenerate: () async => throw Exception('API 키가 없습니다'),
    );

    await tester.tap(find.text('Generate'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.textContaining('API 키가 없습니다'), findsOneWidget);
  });
}
