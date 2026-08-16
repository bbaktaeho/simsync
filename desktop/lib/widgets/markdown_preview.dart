import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';

/// Renders markdown content with theme-aware styling.
class MarkdownPreviewWidget extends StatelessWidget {
  final String content;
  final double contentScale;

  const MarkdownPreviewWidget({
    super.key,
    required this.content,
    this.contentScale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    if (content.trim().isEmpty) {
      return Center(
        child: Text(
          'Nothing to preview',
          style: AppTextStyles.mdBody(contentScale).copyWith(color: c.textMuted),
        ),
      );
    }

    return Markdown(
      data: content,
      selectable: true,
      padding: EdgeInsets.zero,
      styleSheet: buildMarkdownStyleSheet(context, contentScale: contentScale),
      builders: {'code': _CodeBlockBuilder(contentScale: contentScale)},
    );
  }

}

/// 앱 공용 마크다운 스타일시트.
///
/// 테마에서 시작해야 여기서 지정하지 않은 슬롯(strong/em/del…)도 테마 색을
/// 따른다. 직접 생성하면 그 슬롯들이 기본 검정이 되어 다크 모드에서 글자가
/// 보이지 않는다 — 위클리/먼슬리 리뷰가 그 상태였다.
MarkdownStyleSheet buildMarkdownStyleSheet(
  BuildContext context, {
  double contentScale = 1.0,
}) {
  final c = context.colors;
  return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
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

/// Custom builder that applies syntax highlighting to fenced and indented code
/// blocks.
///
/// IMPORTANT: this MUST be keyed on 'code', not 'pre'. flutter_markdown routes a
/// `pre` block's text through [MarkdownElementBuilder.visitText] (null by
/// default), which starves the lazily-created parent inline of children. Because
/// `_addAnonymousBlockIfNeeded` only clears the inline stack when the inline has
/// children, the empty inline is left dangling and trips the internal
/// `assert(_inlines.isEmpty)` — a hard crash on every code block.
///
/// Keying on 'code' lets the default text path feed the inline first, so the
/// bookkeeping stays balanced. The block child is then replaced with the
/// highlighted view. Inline code (`` `like this` ``) returns null to keep its
/// compact default styling untouched. The surrounding box (background, border,
/// radius) comes from `codeblockDecoration` in the style sheet.
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
    final className = element.attributes['class'];
    final hasLanguageClass =
        className != null && className.startsWith('language-');
    final rawText = element.textContent;

    // Distinguish block code from inline code. Inline code is single-line and
    // carries no language class; block code from the markdown package always
    // has a trailing newline or an explicit `language-` class. Leaving inline
    // code to the default `code` style (return null) also avoids replacing the
    // text child, keeping flutter_markdown's inline bookkeeping balanced.
    final isBlock = hasLanguageClass || rawText.contains('\n');
    if (!isBlock) return null;

    // Extract language from class name (e.g., 'language-go' -> 'go'). highlight
    // falls back to plaintext for any unregistered language, so this is safe.
    var language = 'plaintext';
    if (hasLanguageClass) {
      final parsed = className.substring('language-'.length).trim();
      if (parsed.isNotEmpty) language = parsed;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final highlightTheme = isDark ? atomOneDarkTheme : githubTheme;

    // Make HighlightView background transparent so the code block decoration
    // from the style sheet provides the single surrounding surface.
    final transparentTheme = Map<String, TextStyle>.from(highlightTheme);
    transparentTheme['root'] = (transparentTheme['root'] ?? const TextStyle())
        .copyWith(backgroundColor: Colors.transparent);

    final code = rawText.endsWith('\n')
        ? rawText.substring(0, rawText.length - 1)
        : rawText;

    return Padding(
      padding: const EdgeInsets.all(AppDimensions.spacingMd),
      child: HighlightView(
        code,
        language: language,
        theme: transparentTheme,
        textStyle: AppTextStyles.codeMonoBlock(contentScale),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
