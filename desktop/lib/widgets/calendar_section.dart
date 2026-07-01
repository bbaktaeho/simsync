import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';

class CalendarSection extends StatelessWidget {
  final DateTime displayedMonth;
  final DateTime? selectedDate;
  final Set<DateTime> datesWithNotes;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final ValueChanged<DateTime> onDateSelected;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;

  /// Optional right-click (secondary tap) handler on a day cell, with the tap's
  /// global position. Used by the menu bar popover to offer "add note / memo";
  /// null in the main sidebar, where it stays a no-op.
  final void Function(DateTime date, Offset globalPosition)? onDateSecondaryTap;

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
    this.onDateSecondaryTap,
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final showMonthLabel = constraints.maxWidth > 250;
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
                        style: AppTextStyles.microSemibold.copyWith(color: c.textSecondary, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (isExpanded) ...[
                _MonthNavButton(icon: Icons.chevron_left_rounded, onTap: onPreviousMonth),
                const SizedBox(width: AppDimensions.spacingXs),
                if (showMonthLabel) ...[
                  Text(
                    monthLabel,
                    style: Theme.of(context).textTheme.labelMedium!.copyWith(color: c.textPrimary),
                  ),
                  const SizedBox(width: AppDimensions.spacingXs),
                ],
                _MonthNavButton(icon: Icons.chevron_right_rounded, onTap: onNextMonth),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCalendarGrid(BuildContext context) {
    final year = displayedMonth.year;
    final month = displayedMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    // Days from the previous month shown to complete the first week (Mon-based:
    // weekday 1 => 0 leading days).
    final leadingDays = DateTime(year, month, 1).weekday - 1;
    // Enough rows to cover the leading fill plus the whole month; the final
    // week's remaining cells spill into the next month. Weeks stay 7-wide with
    // no empty gaps.
    final weekCount = ((leadingDays + daysInMonth) / 7).ceil();

    final today = DateTime.now();
    final todayNormalized = DateTime(today.year, today.month, today.day);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingMd),
      child: Column(
        children: [
          _buildWeekdayHeader(context),
          const SizedBox(height: AppDimensions.spacingXs),
          ..._buildWeeks(context, year, month, leadingDays, weekCount, todayNormalized),
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
                    style: AppTextStyles.nanoSemibold.copyWith(color: c.textMuted),
                  ),
                ),
              ))
          .toList(),
    );
  }

  List<Widget> _buildWeeks(
    BuildContext context,
    int year,
    int month,
    int leadingDays,
    int weekCount,
    DateTime todayNormalized,
  ) {
    final weeks = <Widget>[];

    for (var week = 0; week < weekCount; week++) {
      final cells = <Widget>[];
      for (var col = 0; col < 7; col++) {
        // Day-of-month offset from the 1st: negative spills into the previous
        // month, > daysInMonth into the next. DateTime normalizes the
        // under/overflow, so this is DST-safe (unlike Duration arithmetic).
        final dayOffset = week * 7 + col - leadingDays;
        final date = DateTime(year, month, 1 + dayOffset);
        final isCurrentMonth = date.month == month && date.year == year;
        final isToday = date == todayNormalized;
        final isSelected = selectedDate != null &&
            date.year == selectedDate!.year &&
            date.month == selectedDate!.month &&
            date.day == selectedDate!.day;
        final hasNotes = datesWithNotes.contains(date);

        cells.add(Expanded(
          child: _CalendarCell(
            day: date.day,
            isCurrentMonth: isCurrentMonth,
            isToday: isToday,
            isSelected: isSelected,
            hasNotes: hasNotes,
            onTap: () => onDateSelected(date),
            onSecondaryTap: onDateSecondaryTap == null
                ? null
                : (pos) => onDateSecondaryTap!(date, pos),
          ),
        ));
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
  final bool isCurrentMonth;
  final bool isToday;
  final bool isSelected;
  final bool hasNotes;
  final VoidCallback onTap;
  final void Function(Offset globalPosition)? onSecondaryTap;

  const _CalendarCell({
    required this.day,
    required this.isCurrentMonth,
    required this.isToday,
    required this.isSelected,
    required this.hasNotes,
    required this.onTap,
    this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final bgColor = isSelected
        ? c.calendarSelected
        : isToday
            ? c.accentSubtle
            : Colors.transparent;

    // Adjacent-month days are subdued so the current month stays dominant.
    final textColor = isToday
        ? c.calendarToday
        : isSelected
            ? c.textPrimary
            : isCurrentMonth
                ? c.textSecondary
                : c.textMuted;

    return GestureDetector(
      onTap: onTap,
      onSecondaryTapDown: onSecondaryTap == null
          ? null
          : (details) => onSecondaryTap!(details.globalPosition),
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
              style: (isToday || isSelected
                      ? AppTextStyles.microBold
                      : AppTextStyles.microMedium)
                  .copyWith(color: textColor),
            ),
            if (hasNotes)
              Container(
                width: AppDimensions.calendarDotSize,
                height: AppDimensions.calendarDotSize,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: isCurrentMonth
                      ? c.calendarDot
                      : c.calendarDot.withValues(alpha: 0.4),
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
