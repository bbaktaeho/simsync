import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// Renders markdown content with theme-aware styling.
class MarkdownPreviewWidget extends StatelessWidget {
  final String content;

  const MarkdownPreviewWidget({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    if (content.trim().isEmpty) {
      return Center(
        child: Text(
          'Nothing to preview',
          style: GoogleFonts.manrope(fontSize: 14, color: c.textMuted),
        ),
      );
    }

    return Markdown(
      data: content,
      selectable: true,
      padding: EdgeInsets.zero,
      styleSheet: _buildStyleSheet(c),
    );
  }

  MarkdownStyleSheet _buildStyleSheet(AppColorsExtension c) {
    return MarkdownStyleSheet(
      h1: GoogleFonts.manrope(
        fontSize: 26, fontWeight: FontWeight.w700, color: c.textPrimary, height: 1.4,
      ),
      h2: GoogleFonts.manrope(
        fontSize: 21, fontWeight: FontWeight.w600, color: c.textPrimary, height: 1.4,
      ),
      h3: GoogleFonts.manrope(
        fontSize: 17, fontWeight: FontWeight.w600, color: c.textPrimary, height: 1.4,
      ),
      h4: GoogleFonts.manrope(
        fontSize: 15, fontWeight: FontWeight.w600, color: c.textPrimary, height: 1.4,
      ),
      p: GoogleFonts.manrope(
        fontSize: 14, color: c.textPrimary, height: 1.7,
      ),
      a: GoogleFonts.manrope(
        fontSize: 14, color: c.accent, decoration: TextDecoration.underline,
      ),
      listBullet: GoogleFonts.manrope(fontSize: 14, color: c.textSecondary),
      code: GoogleFonts.jetBrainsMono(
        fontSize: 13, color: c.accent, backgroundColor: c.surfaceLight,
      ),
      codeblockDecoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.border),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      blockquote: GoogleFonts.manrope(
        fontSize: 14, color: c.textSecondary, fontStyle: FontStyle.italic, height: 1.6,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: c.accent, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
      ),
      checkbox: GoogleFonts.manrope(fontSize: 14, color: c.accent),
      tableHead: GoogleFonts.manrope(
        fontSize: 13, fontWeight: FontWeight.w600, color: c.textPrimary,
      ),
      tableBody: GoogleFonts.manrope(fontSize: 13, color: c.textSecondary),
      tableBorder: TableBorder.all(color: c.border, width: 1),
      tableHeadAlign: TextAlign.left,
    );
  }
}
