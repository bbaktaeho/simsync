import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/theme/app_colors.dart';
import 'package:simsync/widgets/mini_calendar.dart';

void main() {
  Future<DateTime?> pumpAndReturnTap(
    WidgetTester tester, {
    DateTime? start,
    DateTime? end,
    VoidCallback? onPrev,
    VoidCallback? onNext,
  }) async {
    DateTime? tapped;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColorsExtension.light]),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: MiniCalendar(
                month: DateTime(2026, 3, 1),
                start: start,
                end: end,
                onPrevMonth: onPrev ?? () {},
                onNextMonth: onNext ?? () {},
                onDayTap: (d) => tapped = d,
              ),
            ),
          ),
        ),
      ),
    );
    return tapped;
  }

  testWidgets('renders the month header and weekday labels', (tester) async {
    await pumpAndReturnTap(tester);
    expect(find.text('2026년 3월'), findsOneWidget);
    expect(find.text('일'), findsOneWidget);
    expect(find.text('토'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);
  });

  testWidgets('reports the exact date when a day is tapped', (tester) async {
    DateTime? tapped;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColorsExtension.light]),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: MiniCalendar(
                month: DateTime(2026, 3, 1),
                start: null,
                end: null,
                onPrevMonth: () {},
                onNextMonth: () {},
                onDayTap: (d) => tapped = d,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('15'));
    expect(tapped, DateTime(2026, 3, 15));
  });

  testWidgets('previous and next month buttons fire their callbacks', (
    tester,
  ) async {
    var prev = 0;
    var next = 0;
    await pumpAndReturnTap(tester, onPrev: () => prev++, onNext: () => next++);

    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    expect(prev, 1);
    expect(next, 1);
  });

  testWidgets('renders selected endpoints and an in-range day', (tester) async {
    await pumpAndReturnTap(
      tester,
      start: DateTime(2026, 3, 10),
      end: DateTime(2026, 3, 14),
    );
    expect(find.text('10'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
  });
}
