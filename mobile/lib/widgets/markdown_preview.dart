import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

/// Renders markdown content with theme-aware styling, syntax-highlighted code
/// blocks, and pinch-zoom support via [Transform.scale].
class MarkdownPreview extends StatelessWidget {
  final String content;
  final String title;
  final double contentScale;

  const MarkdownPreview({
    super.key,
    required this.content,
    this.title = '',
    this.contentScale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasTitle = title.trim().isNotEmpty;
    final hasContent = content.trim().isNotEmpty;

    if (!hasTitle && !hasContent) {
      return Center(
        child: Text(
          'Nothing to preview',
          style: GoogleFonts.inter(
            fontSize: 14 * contentScale,
            color: c.textMuted,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDimensions.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasTitle) ...[
            Text(
              title.trim(),
              style: GoogleFonts.inter(
                fontSize: 24 * contentScale,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingLg),
          ],
          if (hasContent)
            MarkdownBody(
              data: content,
              selectable: true,
              styleSheet: _buildStyleSheet(c),
              builders: {'pre': _CodeBlockBuilder(contentScale: contentScale)},
            )
          else
            Text(
              'Nothing to preview',
              style: GoogleFonts.inter(
                fontSize: 14 * contentScale,
                color: c.textMuted,
              ),
            ),
        ],
      ),
    );
  }

  MarkdownStyleSheet _buildStyleSheet(AppColorsExtension c) {
    double scaled(double value) => value * contentScale;

    return MarkdownStyleSheet(
      h1: GoogleFonts.inter(
        fontSize: scaled(26),
        fontWeight: FontWeight.w700,
        color: c.textPrimary,
        height: 1.4,
      ),
      h2: GoogleFonts.inter(
        fontSize: scaled(21),
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
        height: 1.4,
      ),
      h3: GoogleFonts.inter(
        fontSize: scaled(17),
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
        height: 1.4,
      ),
      h4: GoogleFonts.inter(
        fontSize: scaled(15),
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
        height: 1.4,
      ),
      h5: GoogleFonts.inter(
        fontSize: scaled(14),
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
        height: 1.4,
      ),
      h6: GoogleFonts.inter(
        fontSize: scaled(13),
        fontWeight: FontWeight.w600,
        color: c.textSecondary,
        height: 1.4,
      ),
      h1Padding: const EdgeInsets.only(top: AppDimensions.spacingXl, bottom: AppDimensions.spacingLg),
      h2Padding: const EdgeInsets.only(top: AppDimensions.spacingXl, bottom: AppDimensions.spacingLg),
      h3Padding: const EdgeInsets.only(top: AppDimensions.spacingXl, bottom: AppDimensions.spacingLg),
      h4Padding: const EdgeInsets.only(top: AppDimensions.spacingLg, bottom: AppDimensions.spacingSm),
      h5Padding: const EdgeInsets.only(top: AppDimensions.spacingLg, bottom: AppDimensions.spacingSm),
      h6Padding: const EdgeInsets.only(top: AppDimensions.spacingLg, bottom: AppDimensions.spacingSm),
      p: GoogleFonts.inter(
        fontSize: scaled(14),
        color: c.textPrimary,
        height: 1.7,
      ),
      a: GoogleFonts.inter(
        fontSize: scaled(14),
        color: c.accent,
        decoration: TextDecoration.underline,
      ),
      listBullet: GoogleFonts.inter(
        fontSize: scaled(14),
        color: c.textSecondary,
      ),
      code: GoogleFonts.jetBrainsMono(
        fontSize: scaled(13),
        color: c.accent,
        backgroundColor: c.surfaceLight,
      ),
      codeblockDecoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(AppDimensions.radiusSubtle),
        border: Border.all(color: c.border),
      ),
      codeblockPadding: const EdgeInsets.all(AppDimensions.spacingMd),
      blockquote: GoogleFonts.inter(
        fontSize: scaled(14),
        color: c.textSecondary,
        fontStyle: FontStyle.italic,
        height: 1.6,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: c.accent, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.only(left: AppDimensions.spacingLg, top: AppDimensions.spacingXs, bottom: AppDimensions.spacingXs),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
      ),
      checkbox: GoogleFonts.inter(fontSize: scaled(14), color: c.accent),
      tableHead: GoogleFonts.inter(
        fontSize: scaled(13),
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
      ),
      tableBody: GoogleFonts.inter(
        fontSize: scaled(13),
        color: c.textSecondary,
      ),
      tableBorder: TableBorder.all(color: c.border, width: 1),
      tableHeadAlign: TextAlign.left,
    );
  }
}

/// Custom builder that applies syntax highlighting to fenced code blocks.
class _CodeBlockBuilder extends MarkdownElementBuilder {
  _CodeBlockBuilder({required this.contentScale});

  final double contentScale;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final textContent = element.textContent;

    // Extract language from class name (e.g. 'language-go' -> 'go').
    final className = element.attributes['class'];
    String language = 'plaintext';
    if (className != null && className.startsWith('language-')) {
      language = className.substring('language-'.length);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final highlightTheme = isDark ? atomOneDarkTheme : githubTheme;

    // Make HighlightView background transparent so the Container handles it.
    final transparentTheme = Map<String, TextStyle>.from(highlightTheme);
    transparentTheme['root'] = (transparentTheme['root'] ?? const TextStyle())
        .copyWith(backgroundColor: Colors.transparent);

    final c = context.colors;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(AppDimensions.radiusSubtle),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(AppDimensions.spacingMd),
      child: HighlightView(
        textContent.endsWith('\n')
            ? textContent.substring(0, textContent.length - 1)
            : textContent,
        language: language,
        theme: transparentTheme,
        textStyle: GoogleFonts.jetBrainsMono(fontSize: 13 * contentScale),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
