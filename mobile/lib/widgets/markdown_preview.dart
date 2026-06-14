import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';

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
          style: AppTextStyles.mdBody(contentScale).copyWith(color: c.textMuted),
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
              style: AppTextStyles.scaledH1(contentScale).copyWith(color: c.textPrimary),
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
              style: AppTextStyles.mdBody(contentScale).copyWith(color: c.textMuted),
            ),
        ],
      ),
    );
  }

  MarkdownStyleSheet _buildStyleSheet(AppColorsExtension c) {
    return MarkdownStyleSheet(
      h1: AppTextStyles.mdH1(contentScale).copyWith(color: c.textPrimary),
      h2: AppTextStyles.mdH2(contentScale).copyWith(color: c.textPrimary),
      h3: AppTextStyles.mdH3(contentScale).copyWith(color: c.textPrimary),
      h4: AppTextStyles.mdH4(contentScale).copyWith(color: c.textPrimary),
      h5: AppTextStyles.mdH5(contentScale).copyWith(color: c.textPrimary),
      h6: AppTextStyles.mdH6(contentScale).copyWith(color: c.textSecondary),
      h1Padding: const EdgeInsets.only(top: AppDimensions.spacingXl, bottom: AppDimensions.spacingLg),
      h2Padding: const EdgeInsets.only(top: AppDimensions.spacingXl, bottom: AppDimensions.spacingLg),
      h3Padding: const EdgeInsets.only(top: AppDimensions.spacingXl, bottom: AppDimensions.spacingLg),
      h4Padding: const EdgeInsets.only(top: AppDimensions.spacingLg, bottom: AppDimensions.spacingSm),
      h5Padding: const EdgeInsets.only(top: AppDimensions.spacingLg, bottom: AppDimensions.spacingSm),
      h6Padding: const EdgeInsets.only(top: AppDimensions.spacingLg, bottom: AppDimensions.spacingSm),
      p: AppTextStyles.mdBody(contentScale).copyWith(color: c.textPrimary),
      a: AppTextStyles.mdBody(contentScale).copyWith(
        color: c.accent,
        decoration: TextDecoration.underline,
      ),
      listBullet: AppTextStyles.mdBody(contentScale).copyWith(color: c.textSecondary),
      code: AppTextStyles.codeMonoBlock(contentScale).copyWith(
        color: c.accent,
        backgroundColor: c.surfaceLight,
      ),
      codeblockDecoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(AppDimensions.radiusSubtle),
        border: Border.all(color: c.border),
      ),
      codeblockPadding: const EdgeInsets.all(AppDimensions.spacingMd),
      blockquote: AppTextStyles.mdBody(contentScale).copyWith(
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
      checkbox: AppTextStyles.mdBody(contentScale).copyWith(color: c.accent),
      tableHead: AppTextStyles.mdTableHead(contentScale).copyWith(color: c.textPrimary),
      tableBody: AppTextStyles.mdTableBody(contentScale).copyWith(color: c.textSecondary),
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
        textStyle: AppTextStyles.codeMonoBlock(contentScale),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
