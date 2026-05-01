import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../search/search_result.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

class SearchResultsPanel extends StatelessWidget {
  const SearchResultsPanel({
    super.key,
    required this.results,
    required this.query,
    this.selectedNoteId,
    required this.onResultTap,
  });

  final List<SearchResult> results;
  final String query;
  final String? selectedNoteId;
  final ValueChanged<SearchResult> onResultTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 32, color: c.textMuted),
            const SizedBox(height: AppDimensions.spacingSm),
            Text(
              'No results found',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: c.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppDimensions.spacingMd),
      itemCount: results.length,
      separatorBuilder: (_, _) =>
          const SizedBox(height: AppDimensions.spacingSm),
      itemBuilder: (context, index) {
        final result = results[index];
        final isSelected = result.note.id == selectedNoteId;
        return _SearchResultCard(
          result: result,
          query: query,
          isSelected: isSelected,
          onTap: () => onResultTap(result),
        );
      },
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({
    required this.result,
    required this.query,
    required this.isSelected,
    required this.onTap,
  });

  final SearchResult result;
  final String query;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final note = result.note;
    final dateStr = DateFormat('yyyy-MM-dd').format(note.noteDate);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(AppDimensions.spacingMd),
        decoration: BoxDecoration(
          color: isSelected ? c.accentSubtle : c.surfaceLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? c.accent : c.borderSubtle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    note.title.isEmpty ? 'Untitled' : note.title,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppDimensions.spacingSm),
                Text(
                  dateStr,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: c.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingSm),
            _ContextLines(result: result, query: query),
          ],
        ),
      ),
    );
  }
}

class _ContextLines extends StatelessWidget {
  const _ContextLines({required this.result, required this.query});

  final SearchResult result;
  final String query;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final match = result.match;
    final monoStyle = GoogleFonts.jetBrainsMono(
      fontSize: 11,
      height: 1.5,
      color: c.textSecondary,
    );
    final lineNumStyle = GoogleFonts.jetBrainsMono(
      fontSize: 10,
      color: c.textMuted,
    );

    final lines = <Widget>[];

    for (final line in result.contextBefore) {
      lines.add(_buildLine(
        lineNumStyle: lineNumStyle,
        lineNum: match.lineNumber - result.contextBefore.length +
            lines.length,
        text: Text(line, style: monoStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
      ));
    }

    // Matched line with highlight.
    lines.add(_buildLine(
      lineNumStyle: lineNumStyle,
      lineNum: match.lineNumber,
      text: _buildHighlightedLine(match.line, match.matchStart, match.matchEnd, c),
    ));

    for (var i = 0; i < result.contextAfter.length; i++) {
      lines.add(_buildLine(
        lineNumStyle: lineNumStyle,
        lineNum: match.lineNumber + 1 + i,
        text: Text(result.contextAfter[i], style: monoStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines,
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
        const SizedBox(width: 8),
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
        style: GoogleFonts.jetBrainsMono(
          fontSize: 11,
          height: 1.5,
          color: c.textPrimary,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final before = line.substring(0, matchStart);
    final matched = line.substring(matchStart, matchEnd.clamp(0, line.length));
    final after = line.substring(matchEnd.clamp(0, line.length));

    return Text.rich(
      TextSpan(
        style: GoogleFonts.jetBrainsMono(
          fontSize: 11,
          height: 1.5,
          color: c.textPrimary,
        ),
        children: [
          TextSpan(text: before),
          TextSpan(
            text: matched,
            style: TextStyle(
              backgroundColor: c.accent.withValues(alpha: 0.2),
              color: c.accent,
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
