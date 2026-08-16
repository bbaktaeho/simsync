import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';

/// A compact, range-aware month grid for picking dates in the search filter.
///
/// Stateless — the parent owns the displayed [month] and the selected
/// [start]/[end] and drives navigation via [onPrevMonth]/[onNextMonth].
class MiniCalendar extends StatelessWidget {
  const MiniCalendar({
    super.key,
    required this.month,
    required this.start,
    required this.end,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onDayTap,
  });

  final DateTime month; // any day within the month to display
  final DateTime? start;
  final DateTime? end;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<DateTime> onDayTap;

  static const _weekdays = ['일', '월', '화', '수', '목', '금', '토'];

  static DateTime _d(DateTime v) => DateTime(v.year, v.month, v.day);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final first = DateTime(month.year, month.month, 1);
    final leading = first.weekday % 7; // Sun=0 .. Sat=6
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final today = _d(DateTime.now());
    final s = start == null ? null : _d(start!);
    final e = end == null ? null : _d(end!);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _NavButton(icon: Icons.chevron_left_rounded, onTap: onPrevMonth),
            Expanded(
              child: Text(
                DateFormat('yyyy년 M월').format(first),
                textAlign: TextAlign.center,
                style: AppTextStyles.captionSemibold.copyWith(
                  color: c.textPrimary,
                ),
              ),
            ),
            _NavButton(icon: Icons.chevron_right_rounded, onTap: onNextMonth),
          ],
        ),
        const SizedBox(height: AppDimensions.spacingXs),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    _weekdays[i],
                    style: AppTextStyles.micro.copyWith(
                      color: i == 0 ? c.error : c.textMuted,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        for (var row = 0; row < 6; row++)
          if (row * 7 - leading < daysInMonth)
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: _buildCell(
                      c,
                      row * 7 + col - leading + 1,
                      daysInMonth,
                      today,
                      s,
                      e,
                    ),
                  ),
              ],
            ),
      ],
    );
  }

  Widget _buildCell(
    AppColorsExtension c,
    int day,
    int daysInMonth,
    DateTime today,
    DateTime? s,
    DateTime? e,
  ) {
    if (day < 1 || day > daysInMonth) {
      return const SizedBox(height: 30);
    }
    final date = DateTime(month.year, month.month, day);
    final isStart = s != null && date == s;
    final isEnd = e != null && date == e;
    final isEndpoint = isStart || isEnd;
    final inRange = s != null && e != null && date.isAfter(s) && date.isBefore(e);
    final isToday = date == today;

    Color? bg;
    Color fg = c.textPrimary;
    if (isEndpoint) {
      bg = c.accent;
      fg = c.textOnAccent;
    } else if (inRange) {
      bg = c.accentSubtle;
      fg = c.accentMuted;
    } else if (isToday) {
      fg = c.accent;
    }

    return Padding(
      padding: const EdgeInsets.all(1.5),
      child: InkWell(
        onTap: () => onDayTap(date),
        borderRadius: BorderRadius.circular(AppDimensions.radiusSubtle),
        child: Container(
          height: 27,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppDimensions.radiusSubtle),
            border: isToday && !isEndpoint
                ? Border.all(color: c.accent.withValues(alpha: 0.5))
                : null,
          ),
          child: Text(
            '$day',
            style: AppTextStyles.micro.copyWith(
              color: fg,
              fontWeight: isEndpoint ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimensions.radiusSubtle),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 18, color: c.textSecondary),
      ),
    );
  }
}
