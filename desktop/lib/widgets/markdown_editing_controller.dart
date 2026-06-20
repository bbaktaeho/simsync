import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// A [TextEditingController] that renders markdown styling inline while editing,
/// like Obsidian's Live Preview — there is no separate preview pane. The text
/// stays plain markdown (the source of truth), but [buildTextSpan] paints it
/// with heading sizes, bold/italic, lists, quotes, checkboxes and code styling.
///
/// INVARIANT: the concatenated text of the returned span must always equal the
/// controller's `text` exactly — never add or drop characters — otherwise the
/// cursor and selection would desync. Syntax markers (`#`, `**`, `` ` ``, …) are
/// kept but dimmed rather than hidden.
class MarkdownEditingController extends TextEditingController {
  MarkdownEditingController({super.text});

  /// Content zoom scale applied to the rendered styles. Set before paint.
  double scale = 1.0;

  static final RegExp _heading = RegExp(r'^(#{1,6})(\s+)(.*)$');
  static final RegExp _blockquote = RegExp(r'^(\s*>\s?)(.*)$');
  static final RegExp _checkbox = RegExp(r'^(\s*[-*+] \[)([ xX])(\] )(.*)$');
  static final RegExp _bullet = RegExp(r'^(\s*)([-*+])(\s+)(.*)$');
  static final RegExp _ordered = RegExp(r'^(\s*)(\d+[.)])(\s+)(.*)$');
  static final RegExp _fence = RegExp(r'^\s*(```|~~~)');

  // Inline tokens: bold, italic, strikethrough, inline code. Bold/`__` before
  // single `*`/`_` so `**x**` is bold, not two italics. Non-greedy, no newline.
  static final RegExp _inline = RegExp(
    r'(\*\*(.+?)\*\*)'
    r'|(__(.+?)__)'
    r'|(\*(.+?)\*)'
    r'|(_(.+?)_)'
    r'|(~~(.+?)~~)'
    r'|(`(.+?)`)',
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final c = context.colors;
    final base = (style ?? AppTextStyles.mdBody(scale))
        .copyWith(color: c.textPrimary);

    if (text.isEmpty) {
      return TextSpan(style: base, text: '');
    }

    final codeStyle = AppTextStyles.codeMonoBlock(scale).copyWith(
      color: c.textSecondary,
      backgroundColor: c.surfaceLight,
    );

    final lines = text.split('\n');
    final spans = <InlineSpan>[];
    var inFence = false;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_fence.hasMatch(line)) {
        spans.add(TextSpan(text: line, style: codeStyle.copyWith(color: c.textMuted)));
        inFence = !inFence;
      } else if (inFence) {
        spans.add(TextSpan(text: line, style: codeStyle));
      } else {
        spans.addAll(_styleLine(line, base, c));
      }
      if (i < lines.length - 1) {
        spans.add(TextSpan(text: '\n', style: base));
      }
    }

    return TextSpan(style: base, children: spans);
  }

  List<InlineSpan> _styleLine(String line, TextStyle base, AppColorsExtension c) {
    final heading = _heading.firstMatch(line);
    if (heading != null) {
      final hashes = heading.group(1)!;
      final space = heading.group(2)!;
      final content = heading.group(3)!;
      final hStyle =
          _headingStyle(hashes.length).copyWith(color: c.textPrimary);
      return [
        TextSpan(text: '$hashes$space', style: hStyle.copyWith(color: c.textMuted)),
        ..._styleInline(content, hStyle, c),
      ];
    }

    final checkbox = _checkbox.firstMatch(line);
    if (checkbox != null) {
      final pre = checkbox.group(1)!;
      final mark = checkbox.group(2)!;
      final post = checkbox.group(3)!;
      final content = checkbox.group(4)!;
      final checked = mark.toLowerCase() == 'x';
      final contentStyle = checked
          ? base.copyWith(
              color: c.textMuted, decoration: TextDecoration.lineThrough)
          : base;
      return [
        TextSpan(text: pre, style: base.copyWith(color: c.textMuted)),
        TextSpan(
            text: mark,
            style: base.copyWith(color: c.accent, fontWeight: FontWeight.w700)),
        TextSpan(text: post, style: base.copyWith(color: c.textMuted)),
        ..._styleInline(content, contentStyle, c),
      ];
    }

    final bullet = _bullet.firstMatch(line);
    if (bullet != null) {
      final indent = bullet.group(1)!;
      final marker = bullet.group(2)!;
      final gap = bullet.group(3)!;
      final content = bullet.group(4)!;
      return [
        TextSpan(text: indent, style: base),
        TextSpan(
            text: marker,
            style: base.copyWith(color: c.accent, fontWeight: FontWeight.w700)),
        TextSpan(text: gap, style: base),
        ..._styleInline(content, base, c),
      ];
    }

    final ordered = _ordered.firstMatch(line);
    if (ordered != null) {
      final indent = ordered.group(1)!;
      final marker = ordered.group(2)!;
      final gap = ordered.group(3)!;
      final content = ordered.group(4)!;
      return [
        TextSpan(text: indent, style: base),
        TextSpan(
            text: marker,
            style: base.copyWith(color: c.accent, fontWeight: FontWeight.w600)),
        TextSpan(text: gap, style: base),
        ..._styleInline(content, base, c),
      ];
    }

    final quote = _blockquote.firstMatch(line);
    if (quote != null) {
      final marker = quote.group(1)!;
      final content = quote.group(2)!;
      final qStyle =
          base.copyWith(color: c.textSecondary, fontStyle: FontStyle.italic);
      return [
        TextSpan(text: marker, style: base.copyWith(color: c.accent)),
        ..._styleInline(content, qStyle, c),
      ];
    }

    return _styleInline(line, base, c);
  }

  List<InlineSpan> _styleInline(String s, TextStyle lineStyle, AppColorsExtension c) {
    if (s.isEmpty) return const [];
    final spans = <InlineSpan>[];
    final markerStyle = lineStyle.copyWith(color: c.textMuted);
    var last = 0;

    void emit(String open, String content, String close, TextStyle contentStyle) {
      spans.add(TextSpan(text: open, style: markerStyle));
      spans.add(TextSpan(text: content, style: contentStyle));
      spans.add(TextSpan(text: close, style: markerStyle));
    }

    for (final m in _inline.allMatches(s)) {
      if (m.start > last) {
        spans.add(TextSpan(text: s.substring(last, m.start), style: lineStyle));
      }
      if (m.group(1) != null) {
        emit('**', m.group(2)!, '**',
            lineStyle.copyWith(fontWeight: FontWeight.w700));
      } else if (m.group(3) != null) {
        emit('__', m.group(4)!, '__',
            lineStyle.copyWith(fontWeight: FontWeight.w700));
      } else if (m.group(5) != null) {
        emit('*', m.group(6)!, '*',
            lineStyle.copyWith(fontStyle: FontStyle.italic));
      } else if (m.group(7) != null) {
        emit('_', m.group(8)!, '_',
            lineStyle.copyWith(fontStyle: FontStyle.italic));
      } else if (m.group(9) != null) {
        emit('~~', m.group(10)!, '~~',
            lineStyle.copyWith(decoration: TextDecoration.lineThrough));
      } else if (m.group(11) != null) {
        final mono = AppTextStyles.codeMonoBlock(scale)
            .copyWith(color: c.accent, backgroundColor: c.surfaceLight);
        spans.add(TextSpan(text: '`', style: mono.copyWith(color: c.textMuted)));
        spans.add(TextSpan(text: m.group(12)!, style: mono));
        spans.add(TextSpan(text: '`', style: mono.copyWith(color: c.textMuted)));
      }
      last = m.end;
    }
    if (last < s.length) {
      spans.add(TextSpan(text: s.substring(last), style: lineStyle));
    }
    return spans;
  }

  TextStyle _headingStyle(int level) {
    switch (level) {
      case 1:
        return AppTextStyles.mdH1(scale);
      case 2:
        return AppTextStyles.mdH2(scale);
      case 3:
        return AppTextStyles.mdH3(scale);
      case 4:
        return AppTextStyles.mdH4(scale);
      case 5:
        return AppTextStyles.mdH5(scale);
      default:
        return AppTextStyles.mdH6(scale);
    }
  }
}
