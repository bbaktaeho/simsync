import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;

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
      builders: {
        'code': _CodeBlockBuilder(context),
      },
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

/// Custom builder that applies syntax highlighting to fenced code blocks
/// while keeping inline code styled by the default stylesheet.
class _CodeBlockBuilder extends MarkdownElementBuilder {
  final BuildContext context;

  _CodeBlockBuilder(this.context);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    // Only handle fenced code blocks (pre > code), not inline code.
    // Inline code elements have no children that are Elements with className.
    // For fenced code blocks, flutter_markdown wraps them in 'pre' > 'code'.
    // The builder key 'code' is called for both inline and block code.
    // Block code elements are nested inside a 'pre' tag, which we detect
    // by checking if the element has a class attribute (language info).
    // However, fenced code blocks without a language also need handling.
    // The element.attributes['class'] is set to 'language-xxx' for fenced blocks.

    final textContent = element.textContent;

    // Detect if this is a code block vs inline code.
    // Fenced code blocks have class attribute or are multi-line.
    final className = element.attributes['class'];
    final isCodeBlock = className != null || textContent.contains('\n');

    if (!isCodeBlock) {
      // Inline code — return null to let the default style handle it.
      return null;
    }

    // Extract language from class name (e.g., 'language-go' -> 'go').
    String language = 'plaintext';
    if (className != null && className.startsWith('language-')) {
      language = className.substring('language-'.length);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final highlightTheme = isDark ? atomOneDarkTheme : githubTheme;

    // Make HighlightView background transparent so Container handles it.
    final transparentTheme = Map<String, TextStyle>.from(highlightTheme);
    transparentTheme['root'] = (transparentTheme['root'] ?? const TextStyle())
        .copyWith(backgroundColor: Colors.transparent);

    final c = context.colors;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(12),
      child: HighlightView(
        textContent.endsWith('\n')
            ? textContent.substring(0, textContent.length - 1)
            : textContent,
        language: language,
        theme: transparentTheme,
        textStyle: GoogleFonts.jetBrainsMono(fontSize: 13),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
