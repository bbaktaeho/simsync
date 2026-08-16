import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/note.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';

/// Displays a list of note cards with swipe-to-delete and empty state.
class NoteListWidget extends StatelessWidget {
  final List<Note> notes;
  final ValueChanged<Note> onNoteTapped;
  final ValueChanged<Note>? onNoteDeleted;

  const NoteListWidget({
    super.key,
    required this.notes,
    required this.onNoteTapped,
    this.onNoteDeleted,
  });

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) {
      return _buildEmptyState(context);
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingMd,
        vertical: AppDimensions.spacingSm,
      ),
      itemCount: notes.length,
      separatorBuilder: (_, _) =>
          const SizedBox(height: AppDimensions.spacingSm),
      itemBuilder: (context, index) {
        final note = notes[index];
        final card = _NoteCard(
          note: note,
          onTap: () => onNoteTapped(note),
        );

        if (onNoteDeleted == null) return card;

        return Dismissible(
          key: ValueKey(note.id),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) => _confirmDelete(context, note),
          background: _buildDismissBackground(context),
          child: card,
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final c = context.colors;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.article_outlined, size: 40, color: c.textMuted),
          const SizedBox(height: AppDimensions.spacingMd),
          Text(
            '노트가 없습니다',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: c.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildDismissBackground(BuildContext context) {
    final c = context.colors;

    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: AppDimensions.spacingLg),
      decoration: BoxDecoration(
        color: c.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppDimensions.radiusComfortable),
      ),
      child: Icon(Icons.delete_outline_rounded, color: c.error, size: 24),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, Note note) async {
    final c = context.colors;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.circular(AppDimensions.radiusComfortable),
          side: BorderSide(color: c.border),
        ),
        title: Text(
          '노트 삭제',
          style: AppTextStyles.noteTitle.copyWith(
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
          ),
        ),
        content: Text(
          '"${note.title.isEmpty ? "Untitled" : note.title}" 노트를 삭제하시겠습니까?',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              '취소',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: c.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              '삭제',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: c.error),
            ),
          ),
        ],
      ),
    );

    final confirmed = result ?? false;
    if (confirmed) {
      onNoteDeleted?.call(note);
    }
    return confirmed;
  }
}

// ── Individual note card ──

class _NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;

  const _NoteCard({required this.note, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLocal = note.storageType == StorageType.local;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppDimensions.spacingMd),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius:
              BorderRadius.circular(AppDimensions.radiusComfortable),
          border: Border.all(color: c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row with storage badge.
            Row(
              children: [
                Expanded(
                  child: Text(
                    note.title.isEmpty ? 'Untitled' : note.title,
                    style: AppTextStyles.noteTitle.copyWith(
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppDimensions.spacingSm),
                _StorageBadge(isLocal: isLocal),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingSm),

            // 2-line content preview.
            if (note.content.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.only(bottom: AppDimensions.spacingSm),
                child: Text(
                  note.content.replaceAll('\n', ' '),
                  style: AppTextStyles.caption.copyWith(
                    color: c.textSecondary,
                    height: 1.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            // Date + tag chips row.
            Row(
              children: [
                Text(
                  DateFormat('yyyy-MM-dd HH:mm').format(note.updatedAt),
                  style: AppTextStyles.micro.copyWith(color: c.textMuted),
                ),
                const Spacer(),
                if (note.tags.isNotEmpty) _buildTags(c, note.tags),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTags(AppColorsExtension c, List<String> tags) {
    final visible = tags.take(AppDimensions.maxVisibleTags).toList();
    final overflow = tags.length - AppDimensions.maxVisibleTags;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...visible.map((tag) => _TagChip(label: tag)),
        if (overflow > 0)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              '+$overflow',
              style: AppTextStyles.nanoSemibold.copyWith(color: c.textMuted),
            ),
          ),
      ],
    );
  }
}

// ── Storage type badge (synced / local) ──

class _StorageBadge extends StatelessWidget {
  final bool isLocal;

  const _StorageBadge({required this.isLocal});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = isLocal ? c.localAccent : c.accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLocal ? Icons.folder_outlined : Icons.cloud_outlined,
            size: 10,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            isLocal ? 'local' : 'synced',
            style: AppTextStyles.nanoSemibold.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

// ── Tag chip ──

class _TagChip extends StatelessWidget {
  final String label;

  const _TagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.accentSubtle,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
      ),
      child: Text(
        label,
        style: AppTextStyles.nanoMedium.copyWith(color: c.accent),
      ),
    );
  }
}
