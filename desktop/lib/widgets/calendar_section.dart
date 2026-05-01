import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

class CalendarSection extends StatelessWidget {
  final DateTime displayedMonth;
  final DateTime? selectedDate;
  final Set<DateTime> datesWithNotes;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final ValueChanged<DateTime> onDateSelected;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;

  const CalendarSection({
    super.key,
    required this.displayedMonth,
    required this.selectedDate,
    required this.datesWithNotes,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onDateSelected,
    required this.onPreviousMonth,
    required this.onNextMonth,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(context),
        AnimatedCrossFade(
          firstChild: _buildCalendarGrid(context),
          secondChild: const SizedBox.shrink(),
          crossFadeState:
              isExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          duration: AppDimensions.animFast,
          sizeCurve: Curves.easeInOut,
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final c = context.colors;
    final monthLabel = DateFormat('MMM yyyy').format(displayedMonth);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingMd,
        vertical: AppDimensions.spacingSm,
      ),
      child: Row(
        children: [
          InkWell(
            onTap: onToggleExpand,
            borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
            child: Padding(
              padding: const EdgeInsets.all(AppDimensions.spacingXs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 18,
                    color: c.textSecondary,
                  ),
                  const SizedBox(width: AppDimensions.spacingXs),
                  Text(
                    'Calendar',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: c.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          if (isExpanded) ...[
            _MonthNavButton(icon: Icons.chevron_left_rounded, onTap: onPreviousMonth),
            const SizedBox(width: AppDimensions.spacingXs),
            Text(
              monthLabel,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(width: AppDimensions.spacingXs),
            _MonthNavButton(icon: Icons.chevron_right_rounded, onTap: onNextMonth),
          ],
        ],
      ),
    );
  }

  Widget _buildCalendarGrid(BuildContext context) {
    final year = displayedMonth.year;
    final month = displayedMonth.month;
    final firstDayOfMonth = DateTime(year, month, 1);
    final lastDayOfMonth = DateTime(year, month + 1, 0);
    final startWeekday = firstDayOfMonth.weekday;
    final daysInMonth = lastDayOfMonth.day;

    final today = DateTime.now();
    final todayNormalized = DateTime(today.year, today.month, today.day);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingMd),
      child: Column(
        children: [
          _buildWeekdayHeader(context),
          const SizedBox(height: AppDimensions.spacingXs),
          ..._buildWeeks(context, startWeekday, daysInMonth, year, month, todayNormalized),
          const SizedBox(height: AppDimensions.spacingSm),
        ],
      ),
    );
  }

  Widget _buildWeekdayHeader(BuildContext context) {
    final c = context.colors;
    const days = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
    return Row(
      children: days
          .map((d) => Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: c.textMuted,
                    ),
                  ),
                ),
              ))
          .toList(),
    );
  }

  List<Widget> _buildWeeks(
    BuildContext context,
    int startWeekday,
    int daysInMonth,
    int year,
    int month,
    DateTime todayNormalized,
  ) {
    final weeks = <Widget>[];
    var dayCounter = 1;
    final blanks = startWeekday - 1;

    for (var week = 0; dayCounter <= daysInMonth; week++) {
      final cells = <Widget>[];
      for (var col = 0; col < 7; col++) {
        if (week == 0 && col < blanks || dayCounter > daysInMonth) {
          cells.add(const Expanded(child: SizedBox.shrink()));
        } else {
          final day = dayCounter;
          final date = DateTime(year, month, day);
          final isToday = date == todayNormalized;
          final isSelected = selectedDate != null &&
              date.year == selectedDate!.year &&
              date.month == selectedDate!.month &&
              date.day == selectedDate!.day;
          final hasNotes = datesWithNotes.contains(date);

          cells.add(Expanded(
            child: _CalendarCell(
              day: day,
              isToday: isToday,
              isSelected: isSelected,
              hasNotes: hasNotes,
              onTap: () => onDateSelected(date),
            ),
          ));
          dayCounter++;
        }
      }
      weeks.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(children: cells),
        ),
      );
    }
    return weeks;
  }
}

class _CalendarCell extends StatelessWidget {
  final int day;
  final bool isToday;
  final bool isSelected;
  final bool hasNotes;
  final VoidCallback onTap;

  const _CalendarCell({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.hasNotes,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final bgColor = isSelected
        ? c.calendarSelected
        : isToday
            ? c.accentSubtle
            : Colors.transparent;

    final textColor = isToday
        ? c.calendarToday
        : isSelected
            ? c.textPrimary
            : c.textSecondary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: AppDimensions.calendarCellSize,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
          border: isToday
              ? Border.all(color: c.accent.withValues(alpha: 0.4))
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: isToday || isSelected ? FontWeight.w700 : FontWeight.w500,
                color: textColor,
              ),
            ),
            if (hasNotes)
              Container(
                width: AppDimensions.calendarDotSize,
                height: AppDimensions.calendarDotSize,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: c.calendarDot,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MonthNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MonthNavButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(icon, size: 18, color: c.textSecondary),
      ),
    );
  }
}
