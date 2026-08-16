import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/note.dart';
import '../search/search_result.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';

/// Displays search results with context lines and keyword highlighting.
class SearchResultsWidget extends StatelessWidget {
  final List<SearchResult> results;
  final void Function(Note note) onResultTapped;

  const SearchResultsWidget({
    super.key,
    required this.results,
    required this.onResultTapped,
  });

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return _buildEmptyState(context);
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppDimensions.spacingMd),
      itemCount: results.length,
      separatorBuilder: (_, _) =>
          const SizedBox(height: AppDimensions.spacingSm),
      itemBuilder: (context, index) {
        final result = results[index];
        return _SearchResultCard(
          result: result,
          onTap: () => onResultTapped(result.note),
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
          Icon(Icons.search_off_rounded, size: 40, color: c.textMuted),
          const SizedBox(height: AppDimensions.spacingMd),
          Text(
            '검색 결과가 없습니다',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: c.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Individual search result card ──

class _SearchResultCard extends StatelessWidget {
  final SearchResult result;
  final VoidCallback onTap;

  const _SearchResultCard({
    required this.result,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final note = result.note;
    final dateStr = DateFormat('yyyy-MM-dd').format(note.noteDate);
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
            // Header: title + date + badge.
            Row(
              children: [
                Expanded(
                  child: Text(
                    note.title.isEmpty ? 'Untitled' : note.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppDimensions.spacingSm),
                _StorageBadge(isLocal: isLocal),
                const SizedBox(width: AppDimensions.spacingSm),
                Text(
                  dateStr,
                  style: AppTextStyles.micro.copyWith(color: c.textMuted),
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingSm),

            // Context lines with line numbers and highlight.
            _ContextLines(result: result),

            // Tag chips.
            if (note.tags.isNotEmpty) ...[
              const SizedBox(height: AppDimensions.spacingSm),
              _buildTags(c, note.tags),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTags(AppColorsExtension c, List<String> tags) {
    return Wrap(
      spacing: AppDimensions.spacingXs,
      runSpacing: AppDimensions.spacingXs,
      children: tags.map((tag) => _TagChip(label: tag)).toList(),
    );
  }
}

// ── Context lines with line numbers and keyword highlighting ──

class _ContextLines extends StatelessWidget {
  final SearchResult result;

  const _ContextLines({required this.result});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final match = result.match;
    final monoStyle = AppTextStyles.codeMono(size: 11, height: 1.5)
        .copyWith(color: c.textSecondary);
    final lineNumStyle = AppTextStyles.codeMono(size: 10).copyWith(color: c.textMuted);

    final lines = <Widget>[];

    // Context before.
    for (var i = 0; i < result.contextBefore.length; i++) {
      final lineNum =
          match.lineNumber - result.contextBefore.length + i;
      lines.add(_buildLine(
        lineNumStyle: lineNumStyle,
        lineNum: lineNum,
        text: Text(
          result.contextBefore[i],
          style: monoStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ));
    }

    // Matched line with highlight.
    lines.add(_buildLine(
      lineNumStyle: lineNumStyle,
      lineNum: match.lineNumber,
      text: _buildHighlightedLine(
        match.line,
        match.matchStart,
        match.matchEnd,
        c,
      ),
    ));

    // Context after.
    for (var i = 0; i < result.contextAfter.length; i++) {
      lines.add(_buildLine(
        lineNumStyle: lineNumStyle,
        lineNum: match.lineNumber + 1 + i,
        text: Text(
          result.contextAfter[i],
          style: monoStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ));
    }

    return Container(
      padding: const EdgeInsets.all(AppDimensions.spacingSm),
      decoration: BoxDecoration(
        color: context.colors.surfaceLight,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines,
      ),
    );
  }

  Widget _buildLine({
    required TextStyle lineNumStyle,
    required int lineNum,
    required Widget text,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 28,
          child: Text(
            '${lineNum + 1}',
            style: lineNumStyle,
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: AppDimensions.spacingSm),
        Expanded(child: text),
      ],
    );
  }

  Widget _buildHighlightedLine(
    String line,
    int matchStart,
    int matchEnd,
    AppColorsExtension c,
  ) {
    if (matchStart == matchEnd || matchStart >= line.length) {
      return Text(
        line,
        style: AppTextStyles.codeMono(size: 11, height: 1.5)
            .copyWith(color: c.textPrimary),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final before = line.substring(0, matchStart);
    final matched =
        line.substring(matchStart, matchEnd.clamp(0, line.length));
    final after = line.substring(matchEnd.clamp(0, line.length));

    return Text.rich(
      TextSpan(
        style: AppTextStyles.codeMono(size: 11, height: 1.5)
            .copyWith(color: c.textPrimary),
        children: [
          TextSpan(text: before),
          TextSpan(
            text: matched,
            style: TextStyle(
              backgroundColor: const Color(0xFFFDE68A), // yellow highlight
              color: c.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: after),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// ── Storage type badge ──

class _StorageBadge extends StatelessWidget {
  final bool isLocal;

  const _StorageBadge({required this.isLocal});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = isLocal ? c.localAccent : c.accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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
            style: AppTextStyles.atto.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
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
