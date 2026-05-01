import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

/// Reusable monthly calendar grid for mobile.
///
/// Shows a 7-column grid (Sun-Sat), highlights today and the selected date,
/// and places a small dot below dates that have notes.
class CalendarWidget extends StatelessWidget {
  final DateTime selectedDate;
  final Set<DateTime> datesWithNotes;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<DateTime> onMonthChanged;

  const CalendarWidget({
    super.key,
    required this.selectedDate,
    required this.datesWithNotes,
    required this.onDateSelected,
    required this.onMonthChanged,
  });

  DateTime get _displayedMonth =>
      DateTime(selectedDate.year, selectedDate.month, 1);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(context),
        const SizedBox(height: AppDimensions.spacingSm),
        _buildWeekdayHeader(context),
        const SizedBox(height: AppDimensions.spacingXs),
        _buildGrid(context),
      ],
    );
  }

  // ── Header with month label and prev/next arrows ──

  Widget _buildHeader(BuildContext context) {
    final c = context.colors;
    final monthLabel = DateFormat('yyyy MMMM').format(_displayedMonth);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingMd,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _MonthNavButton(
            icon: Icons.chevron_left_rounded,
            onTap: () => onMonthChanged(
              DateTime(_displayedMonth.year, _displayedMonth.month - 1, 1),
            ),
          ),
          Text(
            monthLabel,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          _MonthNavButton(
            icon: Icons.chevron_right_rounded,
            onTap: () => onMonthChanged(
              DateTime(_displayedMonth.year, _displayedMonth.month + 1, 1),
            ),
          ),
        ],
      ),
    );
  }

  // ── Weekday row (일 ~ 토) ──

  Widget _buildWeekdayHeader(BuildContext context) {
    final c = context.colors;
    // Sunday-first layout matching Korean convention.
    final weekdays = List.generate(7, (i) {
      // DateFormat uses Monday=1 ... Sunday=7.
      // We want Sun(7), Mon(1), Tue(2), ... Sat(6).
      final date = DateTime(2024, 1, 7 + i); // 2024-01-07 is a Sunday
      return DateFormat.E().format(date);
    });

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingMd,
      ),
      child: Row(
        children: weekdays
            .map(
              (day) => Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: c.textMuted,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  // ── Monthly day grid ──

  Widget _buildGrid(BuildContext context) {
    final year = _displayedMonth.year;
    final month = _displayedMonth.month;
    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0);
    final daysInMonth = lastDay.day;

    // Sunday = 0 offset for first column.
    final startOffset = firstDay.weekday % 7; // DateTime.sunday == 7 -> 0

    final today = DateTime.now();
    final todayNormalized = DateTime(today.year, today.month, today.day);

    // Calculate previous month trailing days.
    final prevMonthLastDay = DateTime(year, month, 0);
    final prevMonthDays = prevMonthLastDay.day;

    final cells = <Widget>[];

    // Previous month trailing days (dimmed).
    for (var i = startOffset - 1; i >= 0; i--) {
      final day = prevMonthDays - i;
      final date = DateTime(prevMonthLastDay.year, prevMonthLastDay.month, day);
      cells.add(
        _CalendarCell(
          day: day,
          isToday: false,
          isSelected: false,
          hasNotes: false,
          isDimmed: true,
          onTap: () => onDateSelected(date),
        ),
      );
    }

    // Current month days.
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(year, month, day);
      final isToday = date == todayNormalized;
      final isSelected = date.year == selectedDate.year &&
          date.month == selectedDate.month &&
          date.day == selectedDate.day;
      final hasNotes = datesWithNotes.contains(date);

      cells.add(
        _CalendarCell(
          day: day,
          isToday: isToday,
          isSelected: isSelected,
          hasNotes: hasNotes,
          isDimmed: false,
          onTap: () => onDateSelected(date),
        ),
      );
    }

    // Next month leading days (dimmed).
    final remaining = (7 - (cells.length % 7)) % 7;
    for (var day = 1; day <= remaining; day++) {
      final date = DateTime(year, month + 1, day);
      cells.add(
        _CalendarCell(
          day: day,
          isToday: false,
          isSelected: false,
          hasNotes: false,
          isDimmed: true,
          onTap: () => onDateSelected(date),
        ),
      );
    }

    // Build rows of 7.
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            children: cells.sublist(i, i + 7).map((c) => Expanded(child: c)).toList(),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingMd,
      ),
      child: Column(children: rows),
    );
  }
}

// ── Individual calendar cell ──

class _CalendarCell extends StatelessWidget {
  final int day;
  final bool isToday;
  final bool isSelected;
  final bool hasNotes;
  final bool isDimmed;
  final VoidCallback onTap;

  const _CalendarCell({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.hasNotes,
    required this.isDimmed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    Color bgColor;
    if (isSelected) {
      bgColor = c.accent;
    } else if (isToday) {
      bgColor = c.accentSubtle;
    } else {
      bgColor = Colors.transparent;
    }

    Color textColor;
    if (isDimmed) {
      textColor = c.textMuted;
    } else if (isSelected) {
      textColor = c.textOnAccent;
    } else if (isToday) {
      textColor = c.calendarToday;
    } else {
      textColor = c.textPrimary;
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: AppDimensions.calendarCellSize + 8,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: AppDimensions.calendarCellSize,
              height: AppDimensions.calendarCellSize,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
                border: isToday && !isSelected
                    ? Border.all(
                        color: c.calendarToday.withValues(alpha: 0.5),
                        width: 1,
                      )
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                '$day',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight:
                      isToday || isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: textColor,
                ),
              ),
            ),
            SizedBox(
              height: 6,
              child: hasNotes && !isDimmed
                  ? Container(
                      width: AppDimensions.calendarDotSize,
                      height: AppDimensions.calendarDotSize,
                      margin: const EdgeInsets.only(top: 1),
                      decoration: BoxDecoration(
                        color: isSelected ? c.textOnAccent : c.calendarDot,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Month navigation button ──

class _MonthNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MonthNavButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: c.surfaceLight,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: c.textSecondary),
      ),
    );
  }
}
