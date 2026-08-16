import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../search/note_search_query.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_theme.dart';
import '../theme/app_text_styles.dart';
import 'mini_calendar.dart';

/// The search filter popover: multi-select tag chips and a from/to date range
/// edited either by typing `YYYY-MM-DD` or by tapping the inline mini-calendar.
/// Every change is applied live via [onChanged]; [onClear] resets the filters.
class SearchFilterPanel extends StatefulWidget {
  const SearchFilterPanel({
    super.key,
    required this.query,
    required this.availableTags,
    required this.onChanged,
  });

  final NoteSearchQuery query;
  final List<String> availableTags;
  final ValueChanged<NoteSearchQuery> onChanged;

  @override
  State<SearchFilterPanel> createState() => _SearchFilterPanelState();
}

enum _Field { from, to }

class _SearchFilterPanelState extends State<SearchFilterPanel> {
  late NoteSearchQuery _query;
  late DateTime _month;
  _Field _active = _Field.from;
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _query = widget.query;
    _month = _firstOfMonth(
        widget.query.startDate ?? widget.query.endDate ?? DateTime.now());
    _syncControllers();
  }

  @override
  void didUpdateWidget(SearchFilterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The text query is owned by the search field; keep it fresh so emitting a
    // filter change doesn't clobber what the user just typed there.
    if (oldWidget.query.text != widget.query.text) {
      _query = _query.copyWith(text: widget.query.text);
    }
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  static DateTime _firstOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
  static String _fmt(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  void _syncControllers() {
    _fromCtrl.text = _query.startDate == null ? '' : _fmt(_query.startDate!);
    _toCtrl.text = _query.endDate == null ? '' : _fmt(_query.endDate!);
  }

  void _commit(NoteSearchQuery next, {bool syncText = false}) {
    setState(() {
      _query = next;
      if (syncText) _syncControllers();
    });
    widget.onChanged(_query);
  }

  void _setRange(DateTime? start, DateTime? end) {
    if (start != null) {
      _month = _firstOfMonth(start);
    } else if (end != null) {
      _month = _firstOfMonth(end);
    }
    _commit(_query.copyWith(startDate: start, endDate: end), syncText: true);
  }

  void _onDayTap(DateTime date) {
    var start = _query.startDate;
    var end = _query.endDate;
    if (_active == _Field.from) {
      start = date;
      if (end != null && start.isAfter(end)) end = start;
      _active = _Field.to;
    } else {
      end = date;
      if (start != null && end.isBefore(start)) start = end;
      _active = _Field.from;
    }
    _commit(_query.copyWith(startDate: start, endDate: end), syncText: true);
  }

  void _onTyped(_Field field, String text) {
    if (text.trim().isEmpty) {
      _commit(field == _Field.from
          ? _query.copyWith(startDate: null)
          : _query.copyWith(endDate: null));
      return;
    }
    final parsed = _parseDate(text);
    if (parsed == null) return; // wait for a complete, valid date
    _month = _firstOfMonth(parsed);

    // Keep start <= end (mirrors the calendar). Only the OTHER field's
    // controller is rewritten, so the one being typed isn't disrupted.
    var start = _query.startDate;
    var end = _query.endDate;
    if (field == _Field.from) {
      start = parsed;
      if (end != null && start.isAfter(end)) {
        end = start;
        _toCtrl.text = _fmt(end);
      }
    } else {
      end = parsed;
      if (start != null && end.isBefore(start)) {
        start = end;
        _fromCtrl.text = _fmt(start);
      }
    }
    _commit(_query.copyWith(startDate: start, endDate: end));
  }

  void _clearAll() {
    _active = _Field.from;
    _month = _firstOfMonth(DateTime.now());
    _commit(NoteSearchQuery(text: _query.text), syncText: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      elevation: 10,
      shadowColor: c.shadowTint,
      borderRadius: BorderRadius.circular(AppDimensions.radiusComfortable),
      child: Container(
        width: 332,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppDimensions.radiusComfortable),
          border: Border.all(color: c.border),
        ),
        padding: const EdgeInsets.all(AppDimensions.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('필터',
                    style: AppTextStyles.captionSemibold
                        .copyWith(color: c.textPrimary)),
                const Spacer(),
                if (_query.hasFilters)
                  _TextButton(label: '초기화', onTap: _clearAll),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingMd),
            _label(c, '태그'),
            const SizedBox(height: AppDimensions.spacingSm),
            if (widget.availableTags.isEmpty)
              Text('사용 가능한 태그가 없습니다',
                  style: AppTextStyles.micro.copyWith(color: c.textMuted))
            else
              Wrap(
                spacing: AppDimensions.spacingXs + 2,
                runSpacing: AppDimensions.spacingXs + 2,
                children: [
                  for (final tag in widget.availableTags)
                    _TagChip(
                      label: tag,
                      selected: _query.hasTag(tag),
                      onTap: () => _commit(_query.toggleTag(tag)),
                    ),
                ],
              ),
            const SizedBox(height: AppDimensions.spacingLg),
            _label(c, '기간'),
            const SizedBox(height: AppDimensions.spacingSm),
            Row(
              children: [
                _PresetChip(label: '오늘', onTap: () {
                  final t = _dateOnly(DateTime.now());
                  _setRange(t, t);
                }),
                const SizedBox(width: AppDimensions.spacingXs + 2),
                _PresetChip(label: '최근 7일', onTap: () {
                  final t = _dateOnly(DateTime.now());
                  _setRange(t.subtract(const Duration(days: 6)), t);
                }),
                const SizedBox(width: AppDimensions.spacingXs + 2),
                _PresetChip(label: '이번 달', onTap: () {
                  final now = DateTime.now();
                  _setRange(DateTime(now.year, now.month, 1),
                      DateTime(now.year, now.month + 1, 0));
                }),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingMd),
            Row(
              children: [
                Expanded(
                  child: _DateInput(
                    hint: '시작일',
                    controller: _fromCtrl,
                    active: _active == _Field.from,
                    onFocus: () => setState(() => _active = _Field.from),
                    onChanged: (v) => _onTyped(_Field.from, v),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppDimensions.spacingSm),
                  child: Icon(Icons.arrow_forward_rounded,
                      size: 14, color: c.textMuted),
                ),
                Expanded(
                  child: _DateInput(
                    hint: '종료일',
                    controller: _toCtrl,
                    active: _active == _Field.to,
                    onFocus: () => setState(() => _active = _Field.to),
                    onChanged: (v) => _onTyped(_Field.to, v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingMd),
            MiniCalendar(
              month: _month,
              start: _query.startDate,
              end: _query.endDate,
              onPrevMonth: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1, 1)),
              onNextMonth: () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1, 1)),
              onDayTap: _onDayTap,
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(AppColorsExtension c, String text) => Text(
        text,
        style: AppTextStyles.microSemibold.copyWith(
          color: c.textMuted,
          letterSpacing: 0.4,
        ),
      );

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime? _parseDate(String text) {
    final m = RegExp(r'^\s*(\d{4})[-./](\d{1,2})[-./](\d{1,2})\s*$')
        .firstMatch(text);
    if (m == null) return null;
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    final date = DateTime(y, mo, d);
    if (date.month != mo || date.day != d) return null; // e.g. Feb 30
    return date;
  }
}

class _DateInput extends StatelessWidget {
  const _DateInput({
    required this.hint,
    required this.controller,
    required this.active,
    required this.onFocus,
    required this.onChanged,
  });

  final String hint;
  final TextEditingController controller;
  final bool active;
  final VoidCallback onFocus;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingSm),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
        border: Border.all(color: active ? c.accent : c.border),
      ),
      child: Row(
        children: [
          Icon(Icons.event_rounded,
              size: 13, color: active ? c.accent : c.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: controller,
              onTap: onFocus,
              onChanged: onChanged,
              textAlignVertical: TextAlignVertical.center,
              keyboardType: TextInputType.datetime,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9\-./]')),
                LengthLimitingTextInputFormatter(10),
              ],
              style: AppTextStyles.micro.copyWith(color: c.textPrimary),
              decoration: bareInputDecoration.copyWith(
                hintText: hint,
                hintStyle: AppTextStyles.micro.copyWith(color: c.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: selected ? c.accent : c.surfaceLight,
      borderRadius: BorderRadius.circular(AppDimensions.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimensions.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimensions.radiusPill),
            border: Border.all(color: selected ? c.accent : c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check_rounded, size: 12, color: c.textOnAccent),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: AppTextStyles.micro.copyWith(
                  color: selected ? c.textOnAccent : c.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: c.accentSubtle,
            borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
          ),
          child: Text(
            label,
            style: AppTextStyles.micro.copyWith(
                color: c.accentMuted, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}

class _TextButton extends StatelessWidget {
  const _TextButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimensions.radiusSubtle),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(label,
            style: AppTextStyles.micro
                .copyWith(color: c.accent, fontWeight: FontWeight.w500)),
      ),
    );
  }
}
