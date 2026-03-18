import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/note.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

class NoteListSection extends StatelessWidget {
  final List<Note> notes;
  final String? selectedNoteId;
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final ValueChanged<Note> onNoteSelected;
  final VoidCallback onCreateSyncNote;
  final VoidCallback? onCreateLocalNote;
  final ValueChanged<int> onPageChanged;
  final Future<void> Function(Note note)? onDeleteNote;
  final bool memoTabActive;
  final ValueChanged<bool> onMemoTabChanged;
  final Future<void> Function(Note note)? onMoveToMemo;
  final Future<void> Function(Note note)? onMoveToDailyNote;

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
    required this.onMemoTabChanged,
    this.onMoveToMemo,
    this.onMoveToDailyNote,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        _buildTabBar(context),
        Divider(height: 1, color: context.colors.border),
        Expanded(
          child: notes.isEmpty ? _buildEmptyState(context) : _buildList(),
        ),
        if (totalPages > 1) _buildPagination(context),
      ],
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
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: c.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: AppDimensions.spacingSm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: c.surfaceHover,
              borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
            ),
            child: Text(
              '$totalCount',
              style: GoogleFonts.manrope(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: c.textMuted,
              ),
            ),
          ),
          const Spacer(),
          _AddNoteButton(
            onCreateSync: onCreateSyncNote,
            onCreateLocal: onCreateLocalNote,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingMd,
      ),
      child: Row(
        children: [
          _TabItem(
            label: 'daily',
            isActive: !memoTabActive,
            onTap: () => onMemoTabChanged(false),
          ),
          const SizedBox(width: AppDimensions.spacingSm),
          _TabItem(
            label: 'memo',
            isActive: memoTabActive,
            onTap: () => onMemoTabChanged(true),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final c = context.colors;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.article_outlined, size: 32, color: c.textMuted),
          const SizedBox(height: AppDimensions.spacingSm),
          Text(
            'No notes yet',
            style: GoogleFonts.manrope(fontSize: 13, color: c.textMuted),
          ),
          const SizedBox(height: AppDimensions.spacingXs),
          Text(
            'Select a date and create one',
            style: GoogleFonts.manrope(fontSize: 11, color: c.textMuted),
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
          onMoveToDailyNote: onMoveToDailyNote != null ? () => onMoveToDailyNote!(note) : null,
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
            style: GoogleFonts.manrope(fontSize: 11, color: c.textMuted),
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

class _NoteListItem extends StatefulWidget {
  final Note note;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onMoveToMemo;
  final VoidCallback? onMoveToDailyNote;

  const _NoteListItem({
    required this.note,
    required this.isSelected,
    required this.onTap,
    this.onDelete,
    this.onMoveToMemo,
    this.onMoveToDailyNote,
  });

  @override
  State<_NoteListItem> createState() => _NoteListItemState();
}

class _NoteListItemState extends State<_NoteListItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final isLocal = widget.note.storageType == StorageType.local;
    final itemAccent = isLocal ? c.localAccent : c.accent;

    final bgColor = widget.isSelected
        ? (isLocal
            ? itemAccent.withValues(alpha: 0.10)
            : c.surfaceHover)
        : _isHovered
            ? (isLocal
                ? itemAccent.withValues(alpha: 0.06)
                : c.surfaceLight)
            : (isLocal
                ? itemAccent.withValues(alpha: 0.03)
                : Colors.transparent);

    final dateStr = DateFormat('HH:mm').format(widget.note.updatedAt);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
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
            borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
            border: widget.isSelected
                ? Border.all(color: itemAccent.withValues(alpha: 0.3))
                : isLocal
                    ? Border.all(color: itemAccent.withValues(alpha: 0.08))
                    : null,
          ),
          child: Row(
            children: [
              if (widget.isSelected)
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
                      widget.note.title.isEmpty ? 'Untitled' : widget.note.title,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: widget.isSelected ? c.textPrimary : c.textSecondary,
                      ),
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
                          style: GoogleFonts.manrope(fontSize: 10, color: c.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (widget.note.tags.isNotEmpty) _buildTags(c, widget.note.tags),
            ],
          ),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final c = context.colors;
    final items = <PopupMenuEntry<String>>[];

    if (!widget.note.isMemo && widget.onMoveToMemo != null) {
      items.add(PopupMenuItem(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        value: 'move_to_memo',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.note_alt_outlined, size: 14, color: c.textSecondary),
            const SizedBox(width: 6),
            Text('메모로 이동', style: TextStyle(color: c.textPrimary, fontSize: 12)),
          ],
        ),
      ));
    }

    if (widget.note.isMemo && widget.onMoveToDailyNote != null) {
      items.add(PopupMenuItem(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        value: 'move_to_daily',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined, size: 14, color: c.textSecondary),
            const SizedBox(width: 6),
            Text('daily로 이동', style: TextStyle(color: c.textPrimary, fontSize: 12)),
          ],
        ),
      ));
    }

    items.add(PopupMenuItem(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      value: 'delete',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline_rounded, size: 14, color: c.error),
          const SizedBox(width: 6),
          Text('삭제', style: TextStyle(color: c.error, fontSize: 12)),
        ],
      ),
    ));

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: c.border),
      ),
      color: c.surface,
      menuPadding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 120),
      items: items,
    ).then((value) {
      if (value == 'delete') widget.onDelete?.call();
      if (value == 'move_to_memo') widget.onMoveToMemo?.call();
      if (value == 'move_to_daily') widget.onMoveToDailyNote?.call();
    });
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
              style: GoogleFonts.manrope(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: c.textMuted,
              ),
            ),
          ),
      ],
    );

    if (overflow <= 0) return tagRow;

    return Tooltip(
      message: tags.join(', '),
      waitDuration: const Duration(milliseconds: 300),
      textStyle: GoogleFonts.manrope(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: c.textPrimary,
      ),
      decoration: BoxDecoration(
        color: c.surfaceHover,
        borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
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
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 9,
          fontWeight: FontWeight.w500,
          color: c.accent,
        ),
      ),
    );
  }
}

class _AddNoteButton extends StatelessWidget {
  final VoidCallback onCreateSync;
  final VoidCallback? onCreateLocal;

  const _AddNoteButton({required this.onCreateSync, this.onCreateLocal});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'sync') onCreateSync();
        if (value == 'local') onCreateLocal?.call();
      },
      offset: const Offset(0, 28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
        side: BorderSide(color: c.border),
      ),
      color: c.surface,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'sync',
          child: Row(
            children: [
              Icon(Icons.cloud_outlined, size: 14, color: c.accent),
              const SizedBox(width: 8),
              Text('동기화 노트',
                  style: GoogleFonts.manrope(
                      fontSize: 12, color: c.textPrimary)),
            ],
          ),
        ),
        if (onCreateLocal != null)
          PopupMenuItem(
            value: 'local',
            child: Row(
              children: [
                Icon(Icons.folder_outlined,
                    size: 14, color: c.localAccent),
                const SizedBox(width: 8),
                Text('로컬 노트',
                    style: GoogleFonts.manrope(
                        fontSize: 12, color: c.textPrimary)),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: c.accentSubtle,
          borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
        ),
        child: Icon(Icons.add_rounded, size: 14, color: c.accent),
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
      borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
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

class _TabItem extends StatefulWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _TabItem({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingSm,
            vertical: AppDimensions.spacingXs,
          ),
          decoration: BoxDecoration(
            color: widget.isActive
                ? c.accentSubtle
                : _isHovered
                    ? c.surfaceHover
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
          ),
          child: Text(
            widget.label,
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: widget.isActive ? c.accent : c.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
