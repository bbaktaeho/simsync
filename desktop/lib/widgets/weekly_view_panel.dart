import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/note.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import 'markdown_preview.dart';

/// Displays all notes for a given week (Mon–Sun) in a scrollable journal view.
class WeeklyViewPanel extends StatelessWidget {
  final DateTime weekStart; // Monday
  final List<Note> weekNotes;
  final ValueChanged<Note>? onNoteTap;

  const WeeklyViewPanel({
    super.key,
    required this.weekStart,
    required this.weekNotes,
    this.onNoteTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final weekEnd = weekStart.add(const Duration(days: 6));

    return Column(
      children: [
        _buildHeader(c, weekEnd),
        Divider(height: 1, color: c.border),
        Expanded(
          child: weekNotes.isEmpty
              ? _buildEmptyState(c)
              : _buildNotesFeed(c),
        ),
      ],
    );
  }

  Widget _buildHeader(AppColorsExtension c, DateTime weekEnd) {
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
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(width: AppDimensions.spacingMd),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: c.accentSubtle,
              borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
            ),
            child: Text(
              '$startStr – $endStr',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: c.accent,
              ),
            ),
          ),
          const Spacer(),
          Text(
            '$noteCount note${noteCount != 1 ? 's' : ''}',
            style: GoogleFonts.inter(
              fontSize: 11,
              color: c.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AppColorsExtension c) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.calendar_view_week_rounded,
            size: 48,
            color: c.textMuted,
          ),
          const SizedBox(height: AppDimensions.spacingLg),
          Text(
            'No notes this week',
            style: GoogleFonts.inter(fontSize: 15, color: c.textMuted),
          ),
          const SizedBox(height: AppDimensions.spacingSm),
          Text(
            'Select a date and start writing',
            style: GoogleFonts.inter(fontSize: 13, color: c.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesFeed(AppColorsExtension c) {
    // Group notes by date
    final grouped = <DateTime, List<Note>>{};
    for (final note in weekNotes) {
      final dateKey = DateTime(
        note.noteDate.year,
        note.noteDate.month,
        note.noteDate.day,
      );
      grouped.putIfAbsent(dateKey, () => []).add(note);
    }

    // Sort dates
    final sortedDates = grouped.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingXl,
        vertical: AppDimensions.spacingLg,
      ),
      itemCount: sortedDates.length,
      itemBuilder: (context, index) {
        final date = sortedDates[index];
        final notes = grouped[date]!;
        return _DateGroup(
          date: date,
          notes: notes,
          isLast: index == sortedDates.length - 1,
          onNoteTap: onNoteTap,
        );
      },
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
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isToday ? c.accent : c.textPrimary,
                ),
              ),
              const SizedBox(width: AppDimensions.spacingSm),
              Text(
                dateLabel,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: c.textMuted,
                ),
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
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppDimensions.spacingSm),
                  Text(
                    timeStr,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: c.textMuted,
                    ),
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
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: c.accent,
        ),
      ),
    );
  }
}
