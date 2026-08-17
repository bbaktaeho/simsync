import 'package:flutter/material.dart';

import '../models/note.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';
import 'app_icon_button.dart';
import 'hover_builder.dart';

/// 월 디렉토리 그룹. 저장 구조 `notes/{YYYY-MM}/{DD}/{title}.md`의 월 폴더를
/// [Note.noteDate] 기준으로 재구성한 것이다.
class MonthGroup {
  final String yearMonth;
  final List<Note> notes;
  const MonthGroup(this.yearMonth, this.notes);
}

/// `YYYY-MM` — 저장소의 월 디렉토리 이름과 같은 형식.
String yearMonthKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}';

/// 노트를 YYYY-MM 디렉토리 단위로 묶는다. 월은 [newestFirst]에 따라
/// 최신순/과거순, 월 안의 노트는 항상 날짜·생성순 오름차순(디렉토리 나열 순서).
List<MonthGroup> groupNotesByMonth(List<Note> notes,
    {bool newestFirst = true}) {
  final byMonth = <String, List<Note>>{};
  for (final note in notes) {
    byMonth.putIfAbsent(yearMonthKey(note.noteDate), () => []).add(note);
  }
  final keys = byMonth.keys.toList()
    ..sort((a, b) => newestFirst ? b.compareTo(a) : a.compareTo(b));
  return [
    for (final key in keys)
      MonthGroup(
        key,
        byMonth[key]!
          ..sort((a, b) {
            final cmp = a.noteDate.compareTo(b.noteDate);
            if (cmp != 0) return cmp;
            return a.createdAt.compareTo(b.createdAt);
          }),
      ),
  ];
}

/// 패널 항목 라벨: "DD: 제목". 월 헤더가 YYYY-MM을 보여주므로 일(day)만으로
/// 날짜를 나타낸다.
String directoryEntryLabel(Note note) {
  final day = note.noteDate.day.toString().padLeft(2, '0');
  final title = note.title.trim().isEmpty ? 'Untitled' : note.title.trim();
  return '$day: $title';
}

/// 우측 월별 디렉토리 패널. 저장소의 월 폴더 구조 그대로 노트(md)를 월 단위로
/// 접고 펼치며 탐색한다. 패널 자체는 타이틀바 버튼, 헤더의 닫기 버튼, 또는
/// cmd+R(기본값)로 여닫는다.
class DirectoryPanel extends StatefulWidget {
  final List<Note> notes;
  final String? selectedNoteId;

  /// 처음 펼쳐 둘 월(보통 선택된 날짜). null이면 오늘의 월.
  final DateTime? initialMonth;
  final ValueChanged<Note> onNoteTap;

  /// 헤더의 닫기 버튼. null이면 버튼을 숨긴다.
  final VoidCallback? onClose;

  const DirectoryPanel({
    super.key,
    required this.notes,
    required this.onNoteTap,
    this.selectedNoteId,
    this.initialMonth,
    this.onClose,
  });

  @override
  State<DirectoryPanel> createState() => _DirectoryPanelState();
}

class _DirectoryPanelState extends State<DirectoryPanel> {
  final Set<String> _expanded = {};
  bool _newestFirst = true;

  @override
  void initState() {
    super.initState();
    _expanded.add(yearMonthKey(widget.initialMonth ?? DateTime.now()));
  }

  void _toggleMonth(String yearMonth) {
    setState(() {
      if (!_expanded.add(yearMonth)) _expanded.remove(yearMonth);
    });
  }

  void _collapseAll() {
    setState(() => _expanded.clear());
  }

  void _toggleSortOrder() {
    setState(() => _newestFirst = !_newestFirst);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final groups = groupNotesByMonth(widget.notes, newestFirst: _newestFirst);

    return Container(
      color: c.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(c),
          Divider(height: 1, color: c.border),
          Expanded(
            child: groups.isEmpty
                ? _buildEmptyState(c)
                : ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimensions.spacingSm,
                      vertical: AppDimensions.spacingSm,
                    ),
                    children: [
                      for (final group in groups) ...[
                        _MonthHeader(
                          yearMonth: group.yearMonth,
                          count: group.notes.length,
                          isExpanded: _expanded.contains(group.yearMonth),
                          onTap: () => _toggleMonth(group.yearMonth),
                        ),
                        if (_expanded.contains(group.yearMonth))
                          for (final note in group.notes)
                            _DirectoryEntry(
                              note: note,
                              isSelected: note.id == widget.selectedNoteId,
                              onTap: () => widget.onNoteTap(note),
                            ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(AppColorsExtension c) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingMd,
        vertical: AppDimensions.spacingSm,
      ),
      child: Row(
        children: [
          Text(
            'Monthly',
            style: AppTextStyles.microSemibold
                .copyWith(color: c.textSecondary, letterSpacing: 0.5),
          ),
          const Spacer(),
          AppIconButton(
            icon: _newestFirst
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded,
            onTap: _toggleSortOrder,
            tooltip: _newestFirst ? '오래된 월부터 정렬' : '최신 월부터 정렬',
          ),
          const SizedBox(width: AppDimensions.spacingXs),
          AppIconButton(
            icon: Icons.unfold_less_rounded,
            onTap: _collapseAll,
            tooltip: '열린 디렉토리 전체 닫기',
          ),
          if (widget.onClose != null) ...[
            const SizedBox(width: AppDimensions.spacingXs),
            AppIconButton(
              icon: Icons.close_rounded,
              onTap: widget.onClose!,
              tooltip: '패널 닫기',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(AppColorsExtension c) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open_outlined, size: 32, color: c.textMuted),
          const SizedBox(height: AppDimensions.spacingSm),
          Text(
            'No notes yet',
            style: AppTextStyles.caption.copyWith(color: c.textMuted),
          ),
        ],
      ),
    );
  }
}

/// 접고 펼칠 수 있는 월 디렉토리 헤더 줄.
class _MonthHeader extends StatelessWidget {
  final String yearMonth;
  final int count;
  final bool isExpanded;
  final VoidCallback onTap;

  const _MonthHeader({
    required this.yearMonth,
    required this.count,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingSm,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: hovered ? c.surfaceHover : Colors.transparent,
            borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
          ),
          child: Row(
            children: [
              Icon(
                isExpanded
                    ? Icons.expand_more_rounded
                    : Icons.chevron_right_rounded,
                size: 14,
                color: c.textMuted,
              ),
              const SizedBox(width: AppDimensions.spacingXs),
              Icon(
                isExpanded ? Icons.folder_open_outlined : Icons.folder_outlined,
                size: 14,
                color: c.textSecondary,
              ),
              const SizedBox(width: AppDimensions.spacingSm),
              Expanded(
                child: Text(
                  yearMonth,
                  style: AppTextStyles.captionMedium
                      .copyWith(color: c.textPrimary),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: c.surfaceHover,
                  borderRadius:
                      BorderRadius.circular(AppDimensions.radiusMicro),
                ),
                child: Text(
                  '$count',
                  style:
                      AppTextStyles.nanoSemibold.copyWith(color: c.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 월 디렉토리 아래의 노트 한 줄("DD: 제목"). 메모는 teal 글자, 로컬 노트는
/// 좌측 리스트와 같은 문법의 주황(localAccent) 배경 틴트로 구분한다 — 두 축이
/// 독립이라 로컬 메모는 주황 틴트 + teal 글자로 함께 표현된다.
class _DirectoryEntry extends StatelessWidget {
  final Note note;
  final bool isSelected;
  final VoidCallback onTap;

  const _DirectoryEntry({
    required this.note,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isMemo = note.isMemo;
    final isLocal = note.storageType == StorageType.local;

    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) {
        final Color bgColor;
        if (isLocal) {
          bgColor = c.localAccent.withValues(
              alpha: isSelected ? 0.10 : (hovered ? 0.06 : 0.03));
        } else if (isSelected) {
          bgColor = isMemo
              ? c.memoAccent.withValues(alpha: 0.10)
              : c.accentSubtle;
        } else {
          bgColor = hovered ? c.surfaceHover : Colors.transparent;
        }
        return GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.spacingSm,
              vertical: AppDimensions.spacingXs,
            ),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
            ),
            child: Row(
              children: [
                // 월 헤더의 chevron+folder 아이콘 폭만큼 들여쓴다.
                const SizedBox(width: 22),
                Icon(
                  isMemo
                      ? Icons.sticky_note_2_outlined
                      : Icons.description_outlined,
                  size: 13,
                  color: isMemo
                      ? c.memoAccent
                      : isLocal
                          ? c.localAccent.withValues(alpha: 0.7)
                          : c.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    directoryEntryLabel(note),
                    style: AppTextStyles.caption.copyWith(
                      color: isMemo
                          ? c.memoAccent
                          : isLocal
                              ? c.localAccent
                              : isSelected
                                  ? c.textPrimary
                                  : c.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
