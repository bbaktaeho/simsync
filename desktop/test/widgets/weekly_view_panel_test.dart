import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/services/review_controller.dart';
import 'package:simsync/theme/app_theme.dart';
import 'package:simsync/widgets/weekly_view_panel.dart';

final _weekStart = DateTime(2026, 6, 15);

Future<void> _pump(
  WidgetTester tester, {
  required bool claudeEnabled,
  required ReviewController controller,
  VoidCallback? onGenerate,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: SizedBox(
          width: 820,
          height: 640,
          child: WeeklyViewPanel(
            weekStart: _weekStart,
            weekNotes: const [],
            reviewController: controller,
            claudeEnabled: claudeEnabled,
            onGenerate: onGenerate,
          ),
        ),
      ),
    ),
  );
  // A spinner animates forever, so callers in the generating state pass
  // settle: false and pump a single frame instead.
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  testWidgets('Generate button appears only when the summary is enabled', (
    tester,
  ) async {
    await _pump(tester,
        claudeEnabled: false, controller: ReviewController(), onGenerate: () {});
    expect(find.text('Generate'), findsNothing);

    await _pump(tester,
        claudeEnabled: true, controller: ReviewController(), onGenerate: () {});
    expect(find.text('Generate'), findsOneWidget);
  });

  testWidgets('pressing Generate invokes onGenerate', (tester) async {
    var calls = 0;
    await _pump(tester,
        claudeEnabled: true,
        controller: ReviewController(),
        onGenerate: () => calls++);

    await tester.tap(find.text('Generate'));
    await tester.pump();

    expect(calls, 1);
  });

  testWidgets('renders a done review held by the controller', (tester) async {
    final controller = ReviewController()
      ..setLoadedWeekly(_weekStart, 'This week was **productive**.');

    await _pump(tester,
        claudeEnabled: true, controller: controller, onGenerate: () {});

    expect(find.textContaining('productive'), findsWidgets);
    // The button flips to Regenerate once there's a result.
    expect(find.text('Regenerate'), findsOneWidget);
  });

  testWidgets('shows progress while a generation is running', (tester) async {
    final controller = ReviewController();
    final gen = Completer<String>();
    // Never-completing generation → stays in the generating phase.
    unawaited(controller.generateWeekly(_weekStart,
        generate: () => gen.future, persist: (_) async {}));

    await _pump(tester,
        claudeEnabled: true,
        controller: controller,
        onGenerate: () {},
        settle: false);

    expect(find.textContaining('정리하는 중'), findsOneWidget);

    // Let it finish so no timer is left pending.
    gen.complete('done');
    await tester.pump();
  });

  testWidgets('surfaces an error held by the controller', (tester) async {
    final controller = ReviewController();
    await controller.generateWeekly(_weekStart,
        generate: () async => throw Exception('API 키가 없습니다'),
        persist: (_) async {});

    await _pump(tester,
        claudeEnabled: true, controller: controller, onGenerate: () {});

    expect(find.textContaining('API 키가 없습니다'), findsOneWidget);
  });

  testWidgets(
      'a generation finished before the panel mounts is shown when it mounts',
      (tester) async {
    // Background-survival property: the controller holds the result, so a panel
    // built later (e.g. after navigating away and back) still shows it.
    final controller = ReviewController();
    await controller.generateWeekly(_weekStart,
        generate: () async => 'done in the background', persist: (_) async {});

    await _pump(tester,
        claudeEnabled: true, controller: controller, onGenerate: () {});

    expect(find.textContaining('done in the background'), findsWidgets);
  });

  group('MonthlyViewPanel', () {
    final month = DateTime(2026, 6, 1);

    Future<void> pumpMonthly(
      WidgetTester tester, {
      required ReviewController controller,
      VoidCallback? onGenerate,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 820,
              height: 640,
              child: MonthlyViewPanel(
                month: month,
                monthNotes: const [],
                reviewController: controller,
                claudeEnabled: true,
                onGenerate: onGenerate,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders a done monthly review held by the controller',
        (tester) async {
      final controller = ReviewController()
        ..setLoadedMonthly(month, 'June was **productive**.');

      await pumpMonthly(tester, controller: controller, onGenerate: () {});

      expect(find.text('Monthly View'), findsOneWidget);
      expect(find.text('Monthly Summary'), findsOneWidget);
      expect(find.textContaining('productive'), findsWidgets);
      expect(find.text('Regenerate'), findsOneWidget);
    });

    testWidgets('pressing Generate invokes onGenerate', (tester) async {
      var calls = 0;
      await pumpMonthly(tester,
          controller: ReviewController(), onGenerate: () => calls++);

      await tester.tap(find.text('Generate'));
      await tester.pump();

      expect(calls, 1);
    });
  });
}
