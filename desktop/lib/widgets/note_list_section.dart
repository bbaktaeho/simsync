import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/note.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';
import 'hover_builder.dart';
import 'note_list_menus.dart';

class NoteListSection extends StatelessWidget {
  final List<Note> notes;
  final String? selectedNoteId;
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final ValueChanged<Note> onNoteSelected;

  /// 동기화 노트/메모 생성. [memo]가 true면 메모로 만든다.
  final void Function({bool memo}) onCreateSyncNote;

  /// 로컬 노트/메모 생성. null이면 로컬 항목이 메뉴에서 숨는다.
  final void Function({bool memo})? onCreateLocalNote;
  final ValueChanged<int> onPageChanged;
  final Future<void> Function(Note note)? onDeleteNote;
  final bool memoTabActive;
  final ValueChanged<bool>? onMemoTabChanged;
  final Future<void> Function(Note note)? onMoveToMemo;
  final Future<void> Function(Note note)? onMoveToDailyNote;

  /// 로컬 노트를 동기화 노트로 전환한다. 로컬 노트에 우클릭할 때만 노출된다.
  final Future<void> Function(Note note)? onConvertToSynced;

  /// 동기화 노트를 로컬 노트로 전환한다. 동기화 노트에 우클릭할 때만 노출된다.
  final Future<void> Function(Note note)? onConvertToLocal;

  const NoteListSection({
    super.key,
    required this.notes,
    required this.selectedNoteId,
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
    required this.onNoteSelected,
    required this.onCreateSyncNote,
    this.onCreateLocalNote,
    required this.onPageChanged,
    this.onDeleteNote,
    this.memoTabActive = false,
    this.onMemoTabChanged,
    this.onMoveToMemo,
    this.onMoveToDailyNote,
    this.onConvertToSynced,
    this.onConvertToLocal,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        if (onMemoTabChanged != null) _buildTabBar(context),
        Divider(height: 1, color: context.colors.border),
        Expanded(
          child: notes.isEmpty ? _buildEmptyState(context) : _buildList(),
        ),
        if (totalPages > 1) _buildPagination(context),
      ],
    );
  }

  Widget _buildTabBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingMd,
        vertical: AppDimensions.spacingXs,
      ),
      child: Row(
        children: [
          _TabItem(
            label: 'daily',
            isActive: !memoTabActive,
            onTap: () => onMemoTabChanged?.call(false),
          ),
          const SizedBox(width: AppDimensions.spacingMd),
          _TabItem(
            label: 'memo',
            isActive: memoTabActive,
            onTap: () => onMemoTabChanged?.call(true),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingMd,
        vertical: AppDimensions.spacingSm,
      ),
      child: Row(
        children: [
          Text(
            'Notes',
            style: AppTextStyles.microSemibold.copyWith(color: c.textSecondary, letterSpacing: 0.5),
          ),
          const SizedBox(width: AppDimensions.spacingSm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: c.surfaceHover,
              borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
            ),
            child: Text(
              '$totalCount',
              style: AppTextStyles.nanoSemibold.copyWith(color: c.textMuted),
            ),
          ),
          const Spacer(),
          AddNoteMenuButton(
            onCreateSync: onCreateSyncNote,
            onCreateLocal: onCreateLocalNote,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final c = context.colors;
    final iconData = memoTabActive
        ? Icons.sticky_note_2_outlined
        : Icons.article_outlined;
    final primary = memoTabActive ? 'No memos yet' : 'No notes yet';
    final secondary = memoTabActive
        ? 'Create one with + or move a daily note here'
        : 'Select a date and create one';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: 32, color: c.textMuted),
          const SizedBox(height: AppDimensions.spacingSm),
          Text(
            primary,
            style: AppTextStyles.caption.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: AppDimensions.spacingXs),
          Text(
            secondary,
            style: AppTextStyles.micro.copyWith(color: c.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingSm),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        final isSelected = note.id == selectedNoteId;
        return _NoteListItem(
          note: note,
          isSelected: isSelected,
          onTap: () => onNoteSelected(note),
          onDelete: onDeleteNote != null ? () => onDeleteNote!(note) : null,
          onMoveToMemo: onMoveToMemo != null ? () => onMoveToMemo!(note) : null,
          onMoveToDailyNote: onMoveToDailyNote != null
              ? () => onMoveToDailyNote!(note)
              : null,
          onConvertToSynced: onConvertToSynced != null
              ? () => onConvertToSynced!(note)
              : null,
          onConvertToLocal: onConvertToLocal != null
              ? () => onConvertToLocal!(note)
              : null,
        );
      },
    );
  }

  Widget _buildPagination(BuildContext context) {
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.all(AppDimensions.spacingSm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PaginationButton(
            icon: Icons.chevron_left_rounded,
            enabled: currentPage > 0,
            onTap: () => onPageChanged(currentPage - 1),
          ),
          const SizedBox(width: AppDimensions.spacingSm),
          Text(
            '${currentPage + 1} / $totalPages',
            style: AppTextStyles.micro.copyWith(color: c.textMuted),
          ),
          const SizedBox(width: AppDimensions.spacingSm),
          _PaginationButton(
            icon: Icons.chevron_right_rounded,
            enabled: currentPage < totalPages - 1,
            onTap: () => onPageChanged(currentPage + 1),
          ),
        ],
      ),
    );
  }
}

class _NoteListItem extends StatelessWidget {
  final Note note;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onMoveToMemo;
  final VoidCallback? onMoveToDailyNote;
  final VoidCallback? onConvertToSynced;
  final VoidCallback? onConvertToLocal;

  const _NoteListItem({
    required this.note,
    required this.isSelected,
    required this.onTap,
    this.onDelete,
    this.onMoveToMemo,
    this.onMoveToDailyNote,
    this.onConvertToSynced,
    this.onConvertToLocal,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final isLocal = note.storageType == StorageType.local;
    final itemAccent = isLocal ? c.localAccent : c.accent;
    final dateStr = DateFormat('HH:mm').format(note.updatedAt);

    return HoverBuilder(
      builder: (context, hovered) {
        final bgColor = isSelected
            ? (isLocal
                ? itemAccent.withValues(alpha: 0.10)
                : c.surfaceHover)
            : hovered
                ? (isLocal
                    ? itemAccent.withValues(alpha: 0.06)
                    : c.surfaceLight)
                : (isLocal
                    ? itemAccent.withValues(alpha: 0.03)
                    : Colors.transparent);
        return GestureDetector(
        onTap: onTap,
        onSecondaryTapUp: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingSm,
            vertical: AppDimensions.spacingSm,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
            border: isSelected
                ? Border.all(color: itemAccent.withValues(alpha: 0.3))
                : isLocal
                    ? Border.all(color: itemAccent.withValues(alpha: 0.08))
                    : null,
          ),
          child: Row(
            children: [
              if (isSelected)
                Container(
                  width: 3,
                  height: 28,
                  margin: const EdgeInsets.only(right: AppDimensions.spacingSm),
                  decoration: BoxDecoration(
                    color: itemAccent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note.title.isEmpty ? 'Untitled' : note.title,
                      style: AppTextStyles.captionMedium.copyWith(color: isSelected ? c.textPrimary : c.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (isLocal) ...[
                          Icon(Icons.folder_outlined,
                              size: 10, color: itemAccent.withValues(alpha: 0.7)),
                          const SizedBox(width: 3),
                        ],
                        Text(
                          dateStr,
                          style: AppTextStyles.nano.copyWith(color: c.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (note.tags.isNotEmpty) _buildTags(c, note.tags),
            ],
          ),
        ),
      );
      },
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    showNoteContextMenu(
      context: context,
      position: position,
      note: note,
      onConvertToSynced: onConvertToSynced,
      onConvertToLocal: onConvertToLocal,
      onMoveToMemo: onMoveToMemo,
      onMoveToDaily: onMoveToDailyNote,
      onDelete: onDelete,
    );
  }

  Widget _buildTags(AppColorsExtension c, List<String> tags) {
    final visible = tags.take(AppDimensions.maxVisibleTags).toList();
    final overflow = tags.length - AppDimensions.maxVisibleTags;

    final tagRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...visible.map((tag) => _TagChip(label: tag)),
        if (overflow > 0)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              '+$overflow',
              style: AppTextStyles.attoBold.copyWith(color: c.textMuted),
            ),
          ),
      ],
    );

    if (overflow <= 0) return tagRow;

    return Tooltip(
      message: tags.join(', '),
      waitDuration: const Duration(milliseconds: 300),
      textStyle: AppTextStyles.microMedium.copyWith(color: c.textPrimary),
      decoration: BoxDecoration(
        color: c.surfaceHover,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
        border: Border.all(color: c.border),
      ),
      child: tagRow,
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;

  const _TagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      margin: const EdgeInsets.only(left: 3),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: c.accentSubtle,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
      ),
      child: Text(
        label,
        style: AppTextStyles.atto.copyWith(fontWeight: FontWeight.w500, color: c.accent),
      ),
    );
  }
}

class _PaginationButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _PaginationButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? c.textSecondary : c.textMuted,
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _TabItem({
    required this.label,
    required this.isActive,
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
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppDimensions.spacingXs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTextStyles.microSemibold.copyWith(
                  color: isActive
                      ? c.accent
                      : hovered
                          ? c.textPrimary
                          : c.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 18,
                height: 2,
                decoration: BoxDecoration(
                  color: isActive ? c.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
