import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/theme/app_theme.dart';
import 'package:simsync/widgets/calendar_section.dart';

Future<void> _pumpCalendar(
  WidgetTester tester, {
  required DateTime displayedMonth,
  DateTime? selectedDate,
  Set<DateTime> datesWithNotes = const {},
  ValueChanged<DateTime>? onDateSelected,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: SizedBox(
          width: 300,
          child: CalendarSection(
            displayedMonth: displayedMonth,
            selectedDate: selectedDate,
            datesWithNotes: datesWithNotes,
            isExpanded: true,
            onToggleExpand: () {},
            onDateSelected: onDateSelected ?? (_) {},
            onPreviousMonth: () {},
            onNextMonth: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // July 2026: the 1st is a Wednesday, so the first week carries 2 leading days
  // from June (29, 30). July has 31 days, so the last week carries 2 trailing
  // days from August (1, 2). The grid is always 7 wide with no empty gaps.

  testWidgets('fills the first/last weeks with adjacent-month days', (
    tester,
  ) async {
    await _pumpCalendar(tester, displayedMonth: DateTime(2026, 7));

    // June 30 (leading) + July 30 both render.
    expect(find.text('30'), findsNWidgets(2));
    // July 1 + August 1 (trailing) both render.
    expect(find.text('1'), findsNWidgets(2));
    // July 2 + August 2 (trailing) both render.
    expect(find.text('2'), findsNWidgets(2));
    // 31 is unique to July (no adjacent month shows it here).
    expect(find.text('31'), findsOneWidget);
  });

  testWidgets('tapping a leading day selects the previous-month date', (
    tester,
  ) async {
    DateTime? picked;
    await _pumpCalendar(
      tester,
      displayedMonth: DateTime(2026, 7),
      onDateSelected: (d) => picked = d,
    );

    // The very first cell of the grid is Monday, June 29, 2026.
    await tester.tap(find.text('29').first);
    await tester.pump();

    expect(picked, isNotNull);
    expect(picked!.year, 2026);
    expect(picked!.month, 6);
    expect(picked!.day, 29);
  });

  testWidgets('a month starting on Monday pulls in no leading days', (
    tester,
  ) async {
    // June 1 2026 is a Monday, so the first week has no leading days. The
    // previous month's 30th (May 30) must therefore NOT appear — only June's
    // own 30th does. (The last week trails into July 1-5, which carries no 30.)
    await _pumpCalendar(tester, displayedMonth: DateTime(2026, 6));

    expect(find.text('30'), findsOneWidget);
  });
}
