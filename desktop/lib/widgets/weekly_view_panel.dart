import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';

import '../models/note.dart';
import '../services/review_controller.dart';
import '../services/review_outline.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';
import 'hover_builder.dart';
import 'markdown_preview.dart';

/// Displays all notes for a given week (Mon–Sun) in a scrollable journal view,
/// with an optional two-stage AI review at the top.
class WeeklyViewPanel extends StatelessWidget {
  final DateTime weekStart; // Monday
  final List<Note> weekNotes;
  final ValueChanged<Note>? onNoteTap;

  /// Whether the AI review integration is enabled in settings.
  final bool aiEnabled;

  /// Holds two-stage review state (outline + review) OUTSIDE this widget so
  /// generation continues across panel rebuilds / unmounts.
  final ReviewController reviewController;

  /// Stage-1 (outline) generate/regenerate. Null disables the affordance.
  final VoidCallback? onGenerateOutline;

  /// Stage-2 (review) generate/regenerate. Null disables the affordance.
  final VoidCallback? onGenerateReview;

  /// Toggles the stage-1 checkbox on the given line index.
  final ValueChanged<int>? onToggleOutlineItem;

  /// Checks (true) or clears (false) every stage-1 checkbox at once.
  final ValueChanged<bool>? onToggleAllOutlineItems;

  /// Opens settings so the user can enable / configure the AI provider.
  final VoidCallback? onOpenSettings;

  const WeeklyViewPanel({
    super.key,
    required this.weekStart,
    required this.weekNotes,
    required this.reviewController,
    this.onNoteTap,
    this.aiEnabled = false,
    this.onGenerateOutline,
    this.onGenerateReview,
    this.onToggleOutlineItem,
    this.onToggleAllOutlineItems,
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
        _TwoStageReviewSection(
          enabled: aiEnabled,
          controller: reviewController,
          entryOf: () => reviewController.weekly(weekStart),
          title: 'Weekly Summary',
          outlineGeneratingLabel: '이번 주 핵심을 정리하는 중...',
          reviewGeneratingLabel: '선택한 항목으로 주간 리뷰를 작성하는 중...',
          onGenerateOutline: onGenerateOutline,
          onGenerateReview: onGenerateReview,
          onToggleItem: onToggleOutlineItem,
          onToggleAll: onToggleAllOutlineItems,
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
              borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
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

/// Two-stage AI review card shown at the top of the weekly / monthly view.
///
/// Stage 1 ("핵심 정리") runs the fixed system instruction to gather the
/// period's key items into an interactive checkbox list. Stage 2 ("최종 리뷰")
/// runs the user's instruction over the checked items to produce the final
/// write-up. Both stages run in the background via [ReviewController] (so they
/// survive the panel closing) and can be regenerated independently. Generation
/// is requested only on an explicit user action (the "explicit consent before
/// AI summary" rule); results are persisted separately from the original notes.
class _TwoStageReviewSection extends StatefulWidget {
  const _TwoStageReviewSection({
    required this.enabled,
    required this.controller,
    required this.entryOf,
    required this.title,
    required this.outlineGeneratingLabel,
    required this.reviewGeneratingLabel,
    required this.onGenerateOutline,
    required this.onGenerateReview,
    required this.onToggleItem,
    required this.onToggleAll,
    required this.onOpenSettings,
  });

  final bool enabled;
  final ReviewController controller;

  /// Reads the relevant entry from [controller] (weekly(weekStart) or
  /// monthly(month)) — kept as a callback so this widget is period-agnostic.
  final ReviewEntry Function() entryOf;
  final String title;
  final String outlineGeneratingLabel;
  final String reviewGeneratingLabel;
  final VoidCallback? onGenerateOutline;
  final VoidCallback? onGenerateReview;
  final ValueChanged<int>? onToggleItem;
  final ValueChanged<bool>? onToggleAll;
  final VoidCallback? onOpenSettings;

  @override
  State<_TwoStageReviewSection> createState() => _TwoStageReviewSectionState();
}

class _TwoStageReviewSectionState extends State<_TwoStageReviewSection> {
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

    // Subscribe to the controller so the card updates as background generation
    // progresses — even if it started before this panel was built.
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final entry = widget.entryOf();
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
                    widget.title,
                    style: Theme.of(context).textTheme.titleSmall!.copyWith(
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                  ),
                ],
              ),
              if (!widget.enabled) ...[
                const SizedBox(height: AppDimensions.spacingMd),
                _buildDisabledHint(c),
              ] else ...[
                const SizedBox(height: AppDimensions.spacingLg),
                _buildStage1(c, entry.outline),
                _buildConnector(c),
                _buildStage2(c, entry),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildDisabledHint(AppColorsExtension c) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 14, color: c.textMuted),
        const SizedBox(width: AppDimensions.spacingSm),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: AppTextStyles.caption
                  .copyWith(color: c.textSecondary, height: 1.5),
              children: [
                const TextSpan(
                  text: '설정 > AI에서 AI 요약을 켜고 연동 방식(Anthropic API 키, '
                      'Claude Code CLI 또는 Codex CLI)을 설정하면 2단계 리뷰를 사용할 수 '
                      '있습니다. ',
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

  /// Thin vertical line tying stage 1 → stage 2, aligned under the step badge.
  Widget _buildConnector(AppColorsExtension c) {
    return Padding(
      padding: EdgeInsets.only(left: AppDimensions.spacingMd + 10),
      child: Container(
        width: 2,
        height: AppDimensions.spacingMd,
        color: c.borderSubtle,
      ),
    );
  }

  Widget _buildStage1(AppColorsExtension c, StageState outline) {
    final action = widget.onGenerateOutline == null
        ? null
        : _GenerateButton(
            loading: outline.phase == ReviewPhase.generating,
            hasResult: outline.phase == ReviewPhase.done,
            onTap: widget.onGenerateOutline!,
          );
    return _StageCard(
      step: 1,
      title: '핵심 정리',
      accent: c.accent,
      action: action,
      child: _buildStage1Body(c, outline),
    );
  }

  Widget _buildStage1Body(AppColorsExtension c, StageState outline) {
    switch (outline.phase) {
      case ReviewPhase.generating:
        return _GeneratingRow(label: widget.outlineGeneratingLabel);
      case ReviewPhase.error:
        return _ErrorBox(message: outline.error);
      case ReviewPhase.done:
        final content = outline.content;
        if (content != null && content.trim().isNotEmpty) {
          return _OutlineChecklist(
            outline: content,
            onToggle: widget.onToggleItem,
            onToggleAll: widget.onToggleAll,
          );
        }
        return _hint(c, '핵심 항목이 없습니다. 다시 생성해 보세요.');
      case ReviewPhase.idle:
        return _hint(c, 'Generate를 눌러 이번 기간의 핵심을 체크리스트로 정리하세요.');
    }
  }

  Widget _buildStage2(AppColorsExtension c, ReviewEntry entry) {
    final outline = entry.outline;
    final review = entry.review;
    final outlineReady = outline.phase == ReviewPhase.done &&
        outline.content != null &&
        hasCheckedItems(outline.content!);
    final action = (widget.onGenerateReview == null || !outlineReady)
        ? null
        : _GenerateButton(
            loading: review.phase == ReviewPhase.generating,
            hasResult: review.phase == ReviewPhase.done,
            onTap: widget.onGenerateReview!,
          );
    return _StageCard(
      step: 2,
      title: '최종 리뷰',
      accent: c.accent,
      action: action,
      child: _buildStage2Body(c, review, outlineReady),
    );
  }

  Widget _buildStage2Body(
      AppColorsExtension c, StageState review, bool outlineReady) {
    if (review.phase == ReviewPhase.generating) {
      return _GeneratingRow(label: widget.reviewGeneratingLabel);
    }
    if (review.phase == ReviewPhase.error) {
      return _ErrorBox(message: review.error);
    }
    if (review.phase == ReviewPhase.done && review.content != null) {
      return _ReviewMarkdown(content: review.content!);
    }
    // idle
    if (!outlineReady) {
      return _hint(c, '먼저 1단계에서 항목을 선택하면 최종 리뷰를 만들 수 있습니다.');
    }
    return _hint(c, '선택한 항목으로 지침에 따라 최종 리뷰를 생성하세요.');
  }

  Widget _hint(AppColorsExtension c, String text) => Text(
        text,
        style:
            AppTextStyles.caption.copyWith(color: c.textSecondary, height: 1.5),
      );
}

/// A single numbered stage box (step badge + title + action button + body).
class _StageCard extends StatelessWidget {
  const _StageCard({
    required this.step,
    required this.title,
    required this.accent,
    required this.child,
    this.action,
  });

  final int step;
  final String title;
  final Color accent;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(AppDimensions.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                child: Text(
                  '$step',
                  style: AppTextStyles.microMedium
                      .copyWith(color: c.textOnAccent, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: AppDimensions.spacingSm),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall!.copyWith(
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
              ),
              const Spacer(),
              ?action,
            ],
          ),
          const SizedBox(height: AppDimensions.spacingMd),
          child,
        ],
      ),
    );
  }
}

/// Interactive checkbox list rendered from a stage-1 outline. Tapping a row
/// toggles that item via [onToggle] (by its source line index).
class _OutlineChecklist extends StatelessWidget {
  const _OutlineChecklist({
    required this.outline,
    required this.onToggle,
    this.onToggleAll,
  });

  final String outline;
  final ValueChanged<int>? onToggle;

  /// Checks (true) or clears (false) every item at once. Null hides the control.
  final ValueChanged<bool>? onToggleAll;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = parseOutlineItems(outline);
    if (items.isEmpty) {
      // No checkbox lines — fall back to showing the raw markdown.
      return _ReviewMarkdown(content: outline);
    }
    final checkedCount = items.where((it) => it.checked).length;
    final allChecked = checkedCount == items.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Master "select all" row, sitting above and column-aligned with the
        // item checkboxes (left). Tri-state box: empty / dash (some) / check.
        if (onToggleAll != null) ...[
          _SelectAllRow(
            allChecked: allChecked,
            someChecked: checkedCount > 0 && !allChecked,
            onToggle: () => onToggleAll!(!allChecked),
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: AppDimensions.spacingXs),
            color: c.borderSubtle,
          ),
        ],
        for (final item in items)
          _ChecklistRow(item: item, onToggle: onToggle),
        const SizedBox(height: AppDimensions.spacingSm),
        Text(
          '$checkedCount / ${items.length} 선택됨 · 체크한 항목으로 2단계를 생성합니다',
          style: AppTextStyles.micro.copyWith(color: c.textMuted),
        ),
      ],
    );
  }
}

/// Master checkbox row that selects / clears every item at once. Mirrors
/// [_ChecklistRow]'s box so it lines up with the item checkbox column, and
/// shows an indeterminate dash when only some items are checked.
class _SelectAllRow extends StatelessWidget {
  const _SelectAllRow({
    required this.allChecked,
    required this.someChecked,
    required this.onToggle,
  });

  final bool allChecked;
  final bool someChecked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = allChecked || someChecked;
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: active ? c.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                border: Border.all(
                  color: active ? c.accent : c.borderSubtle,
                  width: 1.5,
                ),
              ),
              child: allChecked
                  ? Icon(Icons.check_rounded, size: 12, color: c.textOnAccent)
                  : someChecked
                      ? Icon(Icons.remove_rounded,
                          size: 12, color: c.textOnAccent)
                      : null,
            ),
            const SizedBox(width: AppDimensions.spacingSm),
            Text(
              allChecked ? '전체 해제' : '전체 선택',
              style: AppTextStyles.captionBold.copyWith(color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.item, required this.onToggle});

  final OutlineItem item;
  final ValueChanged<int>? onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onToggle == null ? null : () => onToggle!(item.lineIndex),
      borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Compact custom checkbox (Notion-style; avoids Material Checkbox's
            // fixed 48px slop in a dense list).
            Container(
              margin: const EdgeInsets.only(top: 1),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: item.checked ? c.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                border: Border.all(
                  color: item.checked ? c.accent : c.borderSubtle,
                  width: 1.5,
                ),
              ),
              child: item.checked
                  ? Icon(Icons.check_rounded, size: 12, color: c.textOnAccent)
                  : null,
            ),
            const SizedBox(width: AppDimensions.spacingSm),
            Expanded(
              child: Text(
                item.label,
                style: AppTextStyles.caption.copyWith(
                  color: item.checked ? c.textPrimary : c.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GeneratingRow extends StatelessWidget {
  const _GeneratingRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
        ),
        const SizedBox(width: AppDimensions.spacingMd),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.caption.copyWith(color: c.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
              message ?? '오류가 발생했습니다.',
              style: AppTextStyles.caption.copyWith(color: c.error, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewMarkdown extends StatelessWidget {
  const _ReviewMarkdown({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarkdownBody(
          data: content,
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
          '원본 노트와 별도로 저장됩니다',
          style: AppTextStyles.micro.copyWith(color: c.textMuted),
        ),
      ],
    );
  }
}

/// Displays a month's notes (grouped by date) with an optional two-stage AI
/// review at the top. Mirrors [WeeklyViewPanel] but for a calendar month, and
/// shares the journal + review widgets.
class MonthlyViewPanel extends StatelessWidget {
  final DateTime month; // any day within the month
  final List<Note> monthNotes;
  final ValueChanged<Note>? onNoteTap;
  final bool aiEnabled;
  final ReviewController reviewController;
  final VoidCallback? onGenerateOutline;
  final VoidCallback? onGenerateReview;
  final ValueChanged<int>? onToggleOutlineItem;
  final ValueChanged<bool>? onToggleAllOutlineItems;
  final VoidCallback? onOpenSettings;

  const MonthlyViewPanel({
    super.key,
    required this.month,
    required this.monthNotes,
    required this.reviewController,
    this.onNoteTap,
    this.aiEnabled = false,
    this.onGenerateOutline,
    this.onGenerateReview,
    this.onToggleOutlineItem,
    this.onToggleAllOutlineItems,
    this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        _buildHeader(context, c),
        Divider(height: 1, color: c.border),
        Expanded(child: _buildBody(context, c)),
      ],
    );
  }

  Widget _buildBody(BuildContext context, AppColorsExtension c) {
    final grouped = <DateTime, List<Note>>{};
    for (final note in monthNotes) {
      final dateKey =
          DateTime(note.noteDate.year, note.noteDate.month, note.noteDate.day);
      grouped.putIfAbsent(dateKey, () => []).add(note);
    }
    final sortedDates = grouped.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingXl,
        vertical: AppDimensions.spacingLg,
      ),
      children: [
        _TwoStageReviewSection(
          enabled: aiEnabled,
          controller: reviewController,
          entryOf: () => reviewController.monthly(month),
          title: 'Monthly Summary',
          outlineGeneratingLabel: '이번 달 핵심을 주별로 정리하는 중...',
          reviewGeneratingLabel: '선택한 항목으로 월간 리뷰를 작성하는 중...',
          onGenerateOutline: onGenerateOutline,
          onGenerateReview: onGenerateReview,
          onToggleItem: onToggleOutlineItem,
          onToggleAll: onToggleAllOutlineItems,
          onOpenSettings: onOpenSettings,
        ),
        const SizedBox(height: AppDimensions.spacingXl),
        if (monthNotes.isEmpty)
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
        children: [
          Icon(Icons.calendar_month_rounded, size: 40, color: c.textMuted),
          const SizedBox(height: AppDimensions.spacingMd),
          Text(
            'No notes this month',
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

  Widget _buildHeader(BuildContext context, AppColorsExtension c) {
    final monthStr = DateFormat('MMMM yyyy').format(month);
    final noteCount = monthNotes.length;

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingLg),
      color: c.surface,
      child: Row(
        children: [
          Icon(Icons.calendar_month_rounded, size: 16, color: c.accent),
          const SizedBox(width: AppDimensions.spacingSm),
          Text(
            'Monthly View',
            style: Theme.of(context).textTheme.titleSmall!.copyWith(
                fontWeight: FontWeight.w600, color: c.textPrimary),
          ),
          const SizedBox(width: AppDimensions.spacingMd),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.spacingSm, vertical: 2),
            decoration: BoxDecoration(
              color: c.accentSubtle,
              borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
            ),
            child: Text(
              monthStr,
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
    return FilledButton.icon(
      onPressed: loading ? null : onTap,
      icon: Icon(
        hasResult ? Icons.refresh_rounded : Icons.auto_awesome_rounded,
        size: 14,
      ),
      label: Text(loading
          ? 'Generating...'
          : hasResult
              ? 'Regenerate'
              : 'Generate'),
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

class _NoteCard extends StatelessWidget {
  final Note note;
  final ValueChanged<Note>? onTap;

  const _NoteCard({required this.note, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final timeStr = DateFormat('HH:mm').format(note.updatedAt);

    return HoverBuilder(
      builder: (context, hovered) => GestureDetector(
        onTap: () => onTap?.call(note),
        child: AnimatedContainer(
          duration: AppDimensions.animFast,
          margin: const EdgeInsets.only(
            left: AppDimensions.spacingLg,
            bottom: AppDimensions.spacingMd,
          ),
          padding: const EdgeInsets.all(AppDimensions.spacingLg),
          decoration: BoxDecoration(
            color: hovered ? c.surfaceLight : c.surface,
            borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
            border: Border.all(
              color: hovered ? c.accent.withValues(alpha: 0.3) : c.border,
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
                      note.title.isEmpty
                          ? 'Untitled'
                          : note.title,
                      style: Theme.of(context).textTheme.titleMedium!.copyWith(color: c.textPrimary),
                    ),
                  ),
                  const SizedBox(width: AppDimensions.spacingSm),
                  Text(
                    timeStr,
                    style: AppTextStyles.micro.copyWith(color: c.textMuted),
                  ),
                  if (hovered) ...[
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
              if (note.tags.isNotEmpty) ...[
                const SizedBox(height: AppDimensions.spacingSm),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: note.tags
                      .map((tag) => _WeeklyTagChip(label: tag))
                      .toList(),
                ),
              ],
              // Content preview (rendered markdown)
              if (note.content.isNotEmpty) ...[
                const SizedBox(height: AppDimensions.spacingMd),
                Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ClipRect(
                    child: ShaderMask(
                      shaderCallback: (bounds) {
                        // dstIn 블렌드의 알파 마스크 — 색은 쓰이지 않고
                        // 아래쪽 페이드 아웃만 만든다 (테마 색 아님).
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
                          content: note.content,
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
