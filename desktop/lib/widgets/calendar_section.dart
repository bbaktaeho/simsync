import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import 'app_icon_button.dart';
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

  /// When non-null, each day cell is a square of this side length (and the grid
  /// is centered at a fixed width). Used by the compact menu bar popover so
  /// dates aren't wide rectangles and the calendar can be resized; null in the
  /// main sidebar, which keeps the fixed short-height cells.
  final double? squareCellSize;

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
    this.squareCellSize,
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
          crossFadeState: isExpanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
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
              Flexible(
                child: InkWell(
                  onTap: onToggleExpand,
                  borderRadius: BorderRadius.circular(
                    AppDimensions.radiusMicro,
                  ),
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
                        Flexible(
                          child: Text(
                            'Calendar',
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.microSemibold.copyWith(
                              color: c.textSecondary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (isExpanded) ...[
                // 버튼이 자체 여백을 가지므로 라벨 양옆 간격은 따로 두지 않는다.
                AppIconButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: onPreviousMonth,
                ),
                if (showMonthLabel)
                  Text(
                    monthLabel,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium!.copyWith(color: c.textPrimary),
                  ),
                AppIconButton(
                  icon: Icons.chevron_right_rounded,
                  onTap: onNextMonth,
                ),
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
    // Days from the previous month shown to complete the first week.
    // 일요일 시작: DateTime.weekday는 월=1..일=7이므로 %7이 곧 선행 칸 수다
    // (일=0, 월=1, ... 토=6). 미니 캘린더도 같은 식을 쓴다.
    final leadingDays = DateTime(year, month, 1).weekday % 7;
    // Enough rows to cover the leading fill plus the whole month; the final
    // week's remaining cells spill into the next month. Weeks stay 7-wide with
    // no empty gaps.
    final weekCount = ((leadingDays + daysInMonth) / 7).ceil();

    final today = DateTime.now();
    final todayNormalized = DateTime(today.year, today.month, today.day);

    final grid = Column(
      children: [
        _buildWeekdayHeader(context),
        const SizedBox(height: AppDimensions.spacingXs),
        ..._buildWeeks(
          context,
          year,
          month,
          leadingDays,
          weekCount,
          todayNormalized,
        ),
        const SizedBox(height: AppDimensions.spacingSm),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingMd),
      // Square mode: constrain the whole grid to a fixed width (7 square cells)
      // and center it, so both the weekday header and the day cells stay aligned
      // and the dates render as compact squares rather than wide rectangles.
      child: squareCellSize != null
          ? Center(
              child: SizedBox(width: 7 * squareCellSize!, child: grid),
            )
          : grid,
    );
  }

  Widget _buildWeekdayHeader(BuildContext context) {
    final c = context.colors;
    const days = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
    return Row(
      children: [
        for (var i = 0; i < days.length; i++)
          Expanded(
            child: Center(
              child: Text(
                days[i],
                style: AppTextStyles.nanoSemibold.copyWith(
                  // 0=일, 6=토
                  color: i == 0 || i == 6 ? c.calendarWeekend : c.textMuted,
                ),
              ),
            ),
          ),
      ],
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
        final isSelected =
            selectedDate != null &&
            date.year == selectedDate!.year &&
            date.month == selectedDate!.month &&
            date.day == selectedDate!.day;
        final hasNotes = datesWithNotes.contains(date);

        final cell = _CalendarCell(
          day: date.day,
          isWeekend: date.weekday == DateTime.saturday ||
              date.weekday == DateTime.sunday,
          isCurrentMonth: isCurrentMonth,
          isToday: isToday,
          isSelected: isSelected,
          hasNotes: hasNotes,
          onTap: () => onDateSelected(date),
          onSecondaryTap: onDateSecondaryTap == null
              ? null
              : (pos) => onDateSecondaryTap!(date, pos),
        );
        cells.add(
          Expanded(
            // Square (popover) => height tracks the cell width; otherwise the
            // fixed short height used in the sidebar.
            child: squareCellSize != null
                ? AspectRatio(aspectRatio: 1, child: cell)
                : SizedBox(height: AppDimensions.calendarCellSize, child: cell),
          ),
        );
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
  final bool isWeekend;
  final bool isCurrentMonth;
  final bool isToday;
  final bool isSelected;
  final bool hasNotes;
  final VoidCallback onTap;
  final void Function(Offset globalPosition)? onSecondaryTap;

  const _CalendarCell({
    required this.day,
    required this.isWeekend,
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
        : isWeekend
        // 인접 월의 주말은 같은 색을 흐리게 — '이번 달이 주인공' 규칙 유지.
        ? (isCurrentMonth
            ? c.calendarWeekend
            : c.calendarWeekend.withValues(alpha: 0.45))
        : isCurrentMonth
        ? c.textSecondary
        : c.textMuted;

    return GestureDetector(
      onTap: onTap,
      onSecondaryTapDown: onSecondaryTap == null
          ? null
          : (details) => onSecondaryTap!(details.globalPosition),
      child: Container(
        // Height comes from the wrapper (fixed in the sidebar, square in the
        // popover), so the cell fills whatever box it's given.
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
          border: isToday
              ? Border.all(color: c.accent.withValues(alpha: 0.4))
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style:
                  (isToday || isSelected
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
