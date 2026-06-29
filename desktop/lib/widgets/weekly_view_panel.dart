import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';

import '../models/note.dart';
import '../services/review_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';
import 'markdown_preview.dart';

/// Displays all notes for a given week (Mon–Sun) in a scrollable journal view,
/// with an optional Claude Code summary at the top.
class WeeklyViewPanel extends StatelessWidget {
  final DateTime weekStart; // Monday
  final List<Note> weekNotes;
  final ValueChanged<Note>? onNoteTap;

  /// Whether the Claude Code weekly-summary integration is enabled in settings.
  final bool claudeEnabled;

  /// Holds weekly review state (idle/generating/done/error) OUTSIDE this widget
  /// so generation continues across panel rebuilds / unmounts.
  final ReviewController reviewController;

  /// Starts a background weekly-review generation for [weekStart]. Null disables
  /// the affordance entirely.
  final VoidCallback? onGenerate;

  /// Opens settings so the user can enable / configure Claude Code.
  final VoidCallback? onOpenSettings;

  const WeeklyViewPanel({
    super.key,
    required this.weekStart,
    required this.weekNotes,
    required this.reviewController,
    this.onNoteTap,
    this.claudeEnabled = false,
    this.onGenerate,
    this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final weekEnd = weekStart.add(const Duration(days: 6));

    return Column(
      children: [
        _buildHeader(context, c, weekEnd),
        Divider(height: 1, color: c.border),
        Expanded(child: _buildBody(context, c)),
      ],
    );
  }

  Widget _buildBody(BuildContext context, AppColorsExtension c) {
    // Group notes by date.
    final grouped = <DateTime, List<Note>>{};
    for (final note in weekNotes) {
      final dateKey = DateTime(
        note.noteDate.year,
        note.noteDate.month,
        note.noteDate.day,
      );
      grouped.putIfAbsent(dateKey, () => []).add(note);
    }
    final sortedDates = grouped.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingXl,
        vertical: AppDimensions.spacingLg,
      ),
      children: [
        _WeeklySummarySection(
          claudeEnabled: claudeEnabled,
          controller: reviewController,
          weekStart: weekStart,
          onGenerate: onGenerate,
          onOpenSettings: onOpenSettings,
        ),
        const SizedBox(height: AppDimensions.spacingXl),
        if (weekNotes.isEmpty)
          _buildInlineEmptyState(context, c)
        else
          for (var i = 0; i < sortedDates.length; i++)
            _DateGroup(
              date: sortedDates[i],
              notes: grouped[sortedDates[i]]!,
              isLast: i == sortedDates.length - 1,
              onNoteTap: onNoteTap,
            ),
      ],
    );
  }

  Widget _buildInlineEmptyState(BuildContext context, AppColorsExtension c) {
    return Padding(
      padding: const EdgeInsets.only(top: AppDimensions.spacingXl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.calendar_view_week_rounded,
            size: 40,
            color: c.textMuted,
          ),
          const SizedBox(height: AppDimensions.spacingMd),
          Text(
            'No notes this week',
            style: Theme.of(context).textTheme.titleSmall!.copyWith(
                  fontWeight: FontWeight.w500,
                  color: c.textMuted,
                ),
          ),
          const SizedBox(height: AppDimensions.spacingXs),
          Text(
            'Select a date and start writing',
            style: AppTextStyles.caption.copyWith(color: c.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppColorsExtension c, DateTime weekEnd) {
    final startStr = DateFormat('MMM d').format(weekStart);
    final endStr = DateFormat('MMM d, yyyy').format(weekEnd);
    final noteCount = weekNotes.length;

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingLg),
      color: c.surface,
      child: Row(
        children: [
          Icon(
            Icons.calendar_view_week_rounded,
            size: 16,
            color: c.accent,
          ),
          const SizedBox(width: AppDimensions.spacingSm),
          Text(
            'Weekly View',
            style: Theme.of(context).textTheme.titleSmall!.copyWith(fontWeight: FontWeight.w600, color: c.textPrimary),
          ),
          const SizedBox(width: AppDimensions.spacingMd),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingSm, vertical: 2),
            decoration: BoxDecoration(
              color: c.accentSubtle,
              borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
            ),
            child: Text(
              '$startStr – $endStr',
              style: AppTextStyles.microMedium.copyWith(color: c.accent),
            ),
          ),
          const Spacer(),
          Text(
            '$noteCount note${noteCount != 1 ? 's' : ''}',
            style: AppTextStyles.micro.copyWith(color: c.textMuted),
          ),
        ],
      ),
    );
  }

}

/// Claude Code weekly summary card shown at the top of the weekly view.
///
/// Generation is requested only on an explicit user action (the Generate
/// button, "explicit consent before AI summary" rule) and runs in the
/// background via [ReviewController], so it survives this panel being closed or
/// another note being opened. The card reflects the controller's state for
/// [weekStart]; the result is persisted separately from the original notes.
class _WeeklySummarySection extends StatefulWidget {
  const _WeeklySummarySection({
    required this.claudeEnabled,
    required this.controller,
    required this.weekStart,
    required this.onGenerate,
    required this.onOpenSettings,
  });

  final bool claudeEnabled;
  final ReviewController controller;
  final DateTime weekStart;
  final VoidCallback? onGenerate;
  final VoidCallback? onOpenSettings;

  @override
  State<_WeeklySummarySection> createState() => _WeeklySummarySectionState();
}

class _WeeklySummarySectionState extends State<_WeeklySummarySection> {
  late final TapGestureRecognizer _settingsTapRecognizer;

  @override
  void initState() {
    super.initState();
    _settingsTapRecognizer = TapGestureRecognizer();
  }

  @override
  void dispose() {
    _settingsTapRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final canGenerate = widget.claudeEnabled && widget.onGenerate != null;

    // Subscribe to the controller so the card updates as the background
    // generation progresses — even if it started before this panel was built.
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final entry = widget.controller.weekly(widget.weekStart);
        return Container(
          decoration: BoxDecoration(
            color: c.surfaceLight,
            borderRadius:
                BorderRadius.circular(AppDimensions.radiusComfortable),
            border: Border.all(color: c.border),
          ),
          padding: const EdgeInsets.all(AppDimensions.spacingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 16, color: c.accent),
                  const SizedBox(width: AppDimensions.spacingSm),
                  Text(
                    'Weekly Summary',
                    style: Theme.of(context).textTheme.titleSmall!.copyWith(
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                  ),
                  const Spacer(),
                  if (canGenerate)
                    _GenerateButton(
                      loading: entry.phase == ReviewPhase.generating,
                      hasResult: entry.phase == ReviewPhase.done,
                      onTap: widget.onGenerate!,
                    ),
                ],
              ),
              const SizedBox(height: AppDimensions.spacingMd),
              _buildContent(c, entry),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent(AppColorsExtension c, ReviewEntry entry) {
    if (!widget.claudeEnabled) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 14, color: c.textMuted),
          const SizedBox(width: AppDimensions.spacingSm),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: AppTextStyles.caption.copyWith(color: c.textSecondary, height: 1.5),
                children: [
                  const TextSpan(
                    text: '설정 > Weekly에서 주간 요약을 켜고 provider(Anthropic API 키 또는 Claude Code CLI)를 '
                        '설정하면 이번 주 노트를 요약할 수 있습니다. ',
                  ),
                  if (widget.onOpenSettings != null)
                    TextSpan(
                      text: '설정 열기',
                      style: AppTextStyles.captionBold.copyWith(color: c.accent),
                      recognizer: _settingsTapRecognizer
                        ..onTap = widget.onOpenSettings,
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (entry.phase == ReviewPhase.generating) {
      return Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
          ),
          const SizedBox(width: AppDimensions.spacingMd),
          Text(
            'Claude Code가 이번 주를 정리하는 중...',
            style: AppTextStyles.caption.copyWith(color: c.textSecondary),
          ),
        ],
      );
    }

    if (entry.phase == ReviewPhase.error) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppDimensions.spacingMd),
        decoration: BoxDecoration(
          color: c.error.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
          border: Border.all(color: c.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, size: 16, color: c.error),
            const SizedBox(width: AppDimensions.spacingSm),
            Expanded(
              child: Text(
                entry.error ?? '오류가 발생했습니다.',
                style:
                    AppTextStyles.caption.copyWith(color: c.error, height: 1.5),
              ),
            ),
          ],
        ),
      );
    }

    if (entry.phase == ReviewPhase.done && entry.content != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarkdownBody(
            data: entry.content!,
            selectable: true,
            styleSheet: MarkdownStyleSheet(
              p: AppTextStyles.mdBody(1.0).copyWith(color: c.textPrimary),
              listBullet:
                  AppTextStyles.mdBody(1.0).copyWith(color: c.textSecondary),
              h1: AppTextStyles.mdH3(1.0).copyWith(color: c.textPrimary),
              h2: AppTextStyles.mdH4(1.0).copyWith(color: c.textPrimary),
              h3: AppTextStyles.mdH5(1.0).copyWith(color: c.textPrimary),
            ),
          ),
          const SizedBox(height: AppDimensions.spacingSm),
          Text(
            'Claude Code가 생성 · 원본 노트와 별도로 저장됩니다',
            style: AppTextStyles.micro.copyWith(color: c.textMuted),
          ),
        ],
      );
    }

    return Text(
      'Generate를 눌러 이번 주 노트를 지침대로 요약하세요.',
      style: AppTextStyles.caption.copyWith(color: c.textSecondary, height: 1.5),
    );
  }
}

class _GenerateButton extends StatelessWidget {
  const _GenerateButton({
    required this.loading,
    required this.hasResult,
    required this.onTap,
  });

  final bool loading;
  final bool hasResult;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FilledButton.icon(
      onPressed: loading ? null : onTap,
      icon: Icon(
        hasResult ? Icons.refresh_rounded : Icons.auto_awesome_rounded,
        size: 16,
      ),
      label: Text(loading
          ? 'Generating...'
          : hasResult
              ? 'Regenerate'
              : 'Generate'),
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        textStyle: AppTextStyles.captionSemibold,
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _DateGroup extends StatelessWidget {
  final DateTime date;
  final List<Note> notes;
  final bool isLast;
  final ValueChanged<Note>? onNoteTap;

  const _DateGroup({
    required this.date,
    required this.notes,
    required this.isLast,
    this.onNoteTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final today = DateTime.now();
    final isToday = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;

    final dayLabel = isToday
        ? 'Today'
        : DateFormat('EEEE').format(date);
    final dateLabel = DateFormat('MMM d').format(date);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date header
        Padding(
          padding: const EdgeInsets.only(bottom: AppDimensions.spacingMd),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isToday ? c.accent : c.borderSubtle,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppDimensions.spacingSm),
              Text(
                dayLabel,
                style: AppTextStyles.captionBold.copyWith(color: isToday ? c.accent : c.textPrimary),
              ),
              const SizedBox(width: AppDimensions.spacingSm),
              Text(
                dateLabel,
                style: Theme.of(context).textTheme.labelSmall!.copyWith(color: c.textMuted),
              ),
              const SizedBox(width: AppDimensions.spacingMd),
              Expanded(
                child: Container(
                  height: 1,
                  color: c.border,
                ),
              ),
            ],
          ),
        ),
        // Note cards
        ...notes.map((note) => _NoteCard(note: note, onTap: onNoteTap)),
        // Spacer between date groups
        if (!isLast)
          const SizedBox(height: AppDimensions.spacingXl),
      ],
    );
  }
}

class _NoteCard extends StatefulWidget {
  final Note note;
  final ValueChanged<Note>? onTap;

  const _NoteCard({required this.note, this.onTap});

  @override
  State<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<_NoteCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final timeStr = DateFormat('HH:mm').format(widget.note.updatedAt);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () => widget.onTap?.call(widget.note),
        child: AnimatedContainer(
          duration: AppDimensions.animFast,
          margin: const EdgeInsets.only(
            left: AppDimensions.spacingLg,
            bottom: AppDimensions.spacingMd,
          ),
          padding: const EdgeInsets.all(AppDimensions.spacingLg),
          decoration: BoxDecoration(
            color: _isHovered ? c.surfaceLight : c.surface,
            borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
            border: Border.all(
              color: _isHovered ? c.accent.withValues(alpha: 0.3) : c.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.note.title.isEmpty
                          ? 'Untitled'
                          : widget.note.title,
                      style: Theme.of(context).textTheme.titleMedium!.copyWith(color: c.textPrimary),
                    ),
                  ),
                  const SizedBox(width: AppDimensions.spacingSm),
                  Text(
                    timeStr,
                    style: AppTextStyles.micro.copyWith(color: c.textMuted),
                  ),
                  if (_isHovered) ...[
                    const SizedBox(width: AppDimensions.spacingSm),
                    Icon(
                      Icons.edit_outlined,
                      size: 14,
                      color: c.accent,
                    ),
                  ],
                ],
              ),
              // Tags
              if (widget.note.tags.isNotEmpty) ...[
                const SizedBox(height: AppDimensions.spacingSm),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: widget.note.tags
                      .map((tag) => _WeeklyTagChip(label: tag))
                      .toList(),
                ),
              ],
              // Content preview (rendered markdown)
              if (widget.note.content.isNotEmpty) ...[
                const SizedBox(height: AppDimensions.spacingMd),
                Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ClipRect(
                    child: ShaderMask(
                      shaderCallback: (bounds) {
                        return LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white,
                            Colors.white,
                            Colors.white.withValues(alpha: 0),
                          ],
                          stops: const [0.0, 0.85, 1.0],
                        ).createShader(bounds);
                      },
                      blendMode: BlendMode.dstIn,
                      child: IgnorePointer(
                        child: MarkdownPreviewWidget(
                          content: widget.note.content,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WeeklyTagChip extends StatelessWidget {
  final String label;

  const _WeeklyTagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
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
