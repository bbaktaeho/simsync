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
  // 주 시작은 일요일. July 2026: 1일이 수요일이라 첫 주는 6월 28·29·30을
  // 선행으로 채운다. 7월은 31일이라 마지막 주는 8월 1일 하나만 끌어온다.
  // 그리드는 항상 7칸 폭이고 빈칸이 없다.

  testWidgets('fills the first/last weeks with adjacent-month days', (
    tester,
  ) async {
    await _pumpCalendar(tester, displayedMonth: DateTime(2026, 7));

    // 6월 30(선행) + 7월 30.
    expect(find.text('30'), findsNWidgets(2));
    // 7월 1 + 8월 1(후행).
    expect(find.text('1'), findsNWidgets(2));
    // 7월 2만 (8월 2는 그리드 밖).
    expect(find.text('2'), findsOneWidget);
    // 첫 칸은 일요일인 6월 28.
    expect(find.text('28'), findsNWidgets(2));
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

    // 일요일 시작이므로 첫 칸은 6월 28(일). 29는 그 다음 칸(월).
    await tester.tap(find.text('29').first);
    await tester.pump();

    expect(picked, isNotNull);
    expect(picked!.year, 2026);
    expect(picked!.month, 6);
    expect(picked!.day, 29);
  });

  testWidgets('월요일 시작 달은 선행 한 칸(전월 말일)을 가져온다', (tester) async {
    // 2026-06-01은 월요일. 일요일 시작이므로 5월 31 한 칸이 앞에 붙는다.
    // 5월 30은 그리드 밖이라 30은 6월 것 하나만 나온다.
    await _pumpCalendar(tester, displayedMonth: DateTime(2026, 6));

    expect(find.text('31'), findsOneWidget); // 5월 31 (선행)
    expect(find.text('30'), findsOneWidget); // 6월 30
  });

  testWidgets('요일 헤더는 일요일부터 시작하고 주말은 다른 색이다', (tester) async {
    await _pumpCalendar(tester, displayedMonth: DateTime(2026, 7));

    final header = tester.widgetList<Text>(find.byType(Text)).toList();
    final su = header.firstWhere((t) => t.data == 'Su');
    final mo = header.firstWhere((t) => t.data == 'Mo');
    final sa = header.firstWhere((t) => t.data == 'Sa');
    expect(su.style!.color, isNot(mo.style!.color), reason: '일요일은 주말 색');
    expect(sa.style!.color, su.style!.color, reason: '토요일도 같은 주말 색');
  });
}
