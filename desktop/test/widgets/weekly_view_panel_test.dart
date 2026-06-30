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
  VoidCallback? onGenerateOutline,
  VoidCallback? onGenerateReview,
  ValueChanged<int>? onToggleOutlineItem,
  ValueChanged<bool>? onToggleAllOutlineItems,
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
            onGenerateOutline: onGenerateOutline,
            onGenerateReview: onGenerateReview,
            onToggleOutlineItem: onToggleOutlineItem,
            onToggleAllOutlineItems: onToggleAllOutlineItems,
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
  testWidgets('stage cards appear only when the integration is enabled',
      (tester) async {
    await _pump(tester,
        claudeEnabled: false,
        controller: ReviewController(),
        onGenerateOutline: () {});
    expect(find.text('핵심 정리'), findsNothing);
    expect(find.text('Generate'), findsNothing);

    await _pump(tester,
        claudeEnabled: true,
        controller: ReviewController(),
        onGenerateOutline: () {});
    expect(find.text('핵심 정리'), findsOneWidget);
    expect(find.text('최종 리뷰'), findsOneWidget);
    // Stage 1 has a Generate button; stage 2 has none until an item is checked.
    expect(find.text('Generate'), findsOneWidget);
  });

  testWidgets('pressing stage-1 Generate invokes onGenerateOutline',
      (tester) async {
    var calls = 0;
    await _pump(tester,
        claudeEnabled: true,
        controller: ReviewController(),
        onGenerateOutline: () => calls++);

    await tester.tap(find.text('Generate'));
    await tester.pump();

    expect(calls, 1);
  });

  testWidgets('renders the outline checklist held by the controller',
      (tester) async {
    final controller = ReviewController()
      ..setLoadedWeeklyOutline(_weekStart, '- [x] 첫째 항목\n- [ ] 둘째 항목');

    await _pump(tester,
        claudeEnabled: true,
        controller: controller,
        onGenerateOutline: () {},
        onGenerateReview: () {},
        onToggleOutlineItem: (_) {});

    expect(find.textContaining('첫째 항목'), findsOneWidget);
    expect(find.textContaining('둘째 항목'), findsOneWidget);
    expect(find.textContaining('선택됨'), findsOneWidget);
    // Outline done → stage-1 button flips to Regenerate.
    expect(find.text('Regenerate'), findsOneWidget);
  });

  testWidgets('tapping an outline item invokes onToggleOutlineItem with its line',
      (tester) async {
    int? toggled;
    final controller = ReviewController()
      ..setLoadedWeeklyOutline(_weekStart, '- [ ] 첫째\n- [ ] 둘째');

    await _pump(tester,
        claudeEnabled: true,
        controller: controller,
        onGenerateOutline: () {},
        onToggleOutlineItem: (i) => toggled = i);

    await tester.tap(find.textContaining('둘째'));
    await tester.pump();

    expect(toggled, 1);
  });

  testWidgets('"전체 선택" requests checking all when some are unchecked',
      (tester) async {
    bool? requested;
    final controller = ReviewController()
      ..setLoadedWeeklyOutline(_weekStart, '- [x] 첫째\n- [ ] 둘째');

    await _pump(tester,
        claudeEnabled: true,
        controller: controller,
        onGenerateOutline: () {},
        onToggleAllOutlineItems: (v) => requested = v);

    expect(find.text('전체 선택'), findsOneWidget);
    await tester.tap(find.text('전체 선택'));
    await tester.pump();

    expect(requested, isTrue);
  });

  testWidgets('the control reads "전체 해제" and clears when all are checked',
      (tester) async {
    bool? requested;
    final controller = ReviewController()
      ..setLoadedWeeklyOutline(_weekStart, '- [x] 첫째\n- [x] 둘째');

    await _pump(tester,
        claudeEnabled: true,
        controller: controller,
        onGenerateOutline: () {},
        onToggleAllOutlineItems: (v) => requested = v);

    expect(find.text('전체 해제'), findsOneWidget);
    await tester.tap(find.text('전체 해제'));
    await tester.pump();

    expect(requested, isFalse);
  });

  testWidgets('the select-all control is hidden when no handler is wired',
      (tester) async {
    final controller = ReviewController()
      ..setLoadedWeeklyOutline(_weekStart, '- [ ] 첫째');

    await _pump(tester,
        claudeEnabled: true,
        controller: controller,
        onGenerateOutline: () {});

    expect(find.text('전체 선택'), findsNothing);
    expect(find.text('전체 해제'), findsNothing);
  });

  testWidgets('stage-2 Generate appears once an item is checked',
      (tester) async {
    final controller = ReviewController()
      ..setLoadedWeeklyOutline(_weekStart, '- [x] 선택됨');

    await _pump(tester,
        claudeEnabled: true,
        controller: controller,
        onGenerateOutline: () {},
        onGenerateReview: () {});

    expect(find.text('Regenerate'), findsOneWidget); // stage 1 (has a result)
    expect(find.text('Generate'), findsOneWidget); // stage 2 (item is checked)
  });

  testWidgets('shows outline progress while stage 1 is running', (tester) async {
    final controller = ReviewController();
    final gen = Completer<String>();
    unawaited(controller.generateWeeklyOutline(_weekStart,
        generate: () => gen.future, persist: (_) async {}));

    await _pump(tester,
        claudeEnabled: true,
        controller: controller,
        onGenerateOutline: () {},
        settle: false);

    expect(find.textContaining('정리하는 중'), findsOneWidget);

    gen.complete('- [ ] x');
    await tester.pump();
  });

  testWidgets('surfaces an outline error held by the controller',
      (tester) async {
    final controller = ReviewController();
    await controller.generateWeeklyOutline(_weekStart,
        generate: () async => throw Exception('API 키가 없습니다'),
        persist: (_) async {});

    await _pump(tester,
        claudeEnabled: true,
        controller: controller,
        onGenerateOutline: () {});

    expect(find.textContaining('API 키가 없습니다'), findsOneWidget);
  });

  testWidgets('a review finished before the panel mounts is shown when it mounts',
      (tester) async {
    // Background-survival property: the controller holds the result, so a panel
    // built later (e.g. after navigating away and back) still shows it.
    final controller = ReviewController()
      ..setLoadedWeeklyOutline(_weekStart, '- [x] a');
    await controller.generateWeeklyReview(_weekStart,
        generate: () async => 'done in the background', persist: (_) async {});

    await _pump(tester,
        claudeEnabled: true,
        controller: controller,
        onGenerateOutline: () {},
        onGenerateReview: () {});

    expect(find.textContaining('done in the background'), findsWidgets);
  });

  group('MonthlyViewPanel', () {
    final month = DateTime(2026, 6, 1);

    Future<void> pumpMonthly(
      WidgetTester tester, {
      required ReviewController controller,
      VoidCallback? onGenerateOutline,
      VoidCallback? onGenerateReview,
      ValueChanged<int>? onToggleOutlineItem,
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
                onGenerateOutline: onGenerateOutline,
                onGenerateReview: onGenerateReview,
                onToggleOutlineItem: onToggleOutlineItem,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders both monthly stages and a done review', (tester) async {
      final controller = ReviewController()
        ..setLoadedMonthlyOutline(month, '- [x] a')
        ..setLoadedMonthlyReview(month, 'June was **productive**.');

      await pumpMonthly(tester,
          controller: controller,
          onGenerateOutline: () {},
          onGenerateReview: () {});

      expect(find.text('Monthly View'), findsOneWidget);
      expect(find.text('Monthly Summary'), findsOneWidget);
      expect(find.text('핵심 정리'), findsOneWidget);
      expect(find.text('최종 리뷰'), findsOneWidget);
      expect(find.textContaining('productive'), findsWidgets);
    });

    testWidgets('pressing stage-1 Generate invokes onGenerateOutline',
        (tester) async {
      var calls = 0;
      await pumpMonthly(tester,
          controller: ReviewController(), onGenerateOutline: () => calls++);

      await tester.tap(find.text('Generate'));
      await tester.pump();

      expect(calls, 1);
    });
  });
}
