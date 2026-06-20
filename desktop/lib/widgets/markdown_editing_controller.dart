import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:highlight/highlight.dart' show highlight, Node;

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// A [TextEditingController] that renders markdown inline like Obsidian's Live
/// Preview. There is no separate preview pane and the text stays plain markdown
/// (the source of truth); [buildTextSpan] paints it.
///
/// Two states per line:
/// - INACTIVE (the caret/selection is elsewhere, or the editor is unfocused):
///   syntax markers (`#`, `**`, `` ` ``, fences) collapse to near-zero width so
///   the line reads as rendered markdown (a big heading, bold text, …).
/// - ACTIVE (the caret/selection touches the line): the markers are revealed,
///   dimmed, so you can edit the raw markdown while the styling stays.
///
/// Fenced code is syntax-highlighted per line via the `highlight` package.
///
/// INVARIANT: the concatenated text of the returned span always equals the
/// controller's `text` exactly — markers are never removed, only restyled — so
/// the cursor and selection never desync.
class MarkdownEditingController extends TextEditingController {
  MarkdownEditingController({super.text});

  /// Content zoom scale applied to the rendered styles. Set before paint.
  double scale = 1.0;

  /// Whether the editor is focused. When false, no line is active (everything
  /// renders). Set by the editor's focus listener before paint.
  bool focused = false;

  /// Per-line highlight parse cache. `buildTextSpan` runs on every keystroke and
  /// caret move; this keeps unchanged code lines from being re-tokenized each
  /// time. Keyed by `lang line` (parse output depends only on those, not on
  /// colors/scale). Bounded to avoid unbounded growth across an edit session.
  final Map<String, List<Node>?> _highlightCache = {};
  static const int _highlightCacheLimit = 2000;

  static final RegExp _heading = RegExp(r'^(#{1,6})(\s+)(.*)$');
  static final RegExp _blockquote = RegExp(r'^(\s*(?:>\s?)+)(.*)$');
  static final RegExp _checkbox = RegExp(r'^(\s*[-*+] \[)([ xX])(\] )(.*)$');
  static final RegExp _bullet = RegExp(r'^(\s*)([-*+])(\s+)(.*)$');
  static final RegExp _ordered = RegExp(r'^(\s*)(\d+[.)])(\s+)(.*)$');
  static final RegExp _fence = RegExp(r'^\s*(```|~~~)');
  static final RegExp _fenceLang = RegExp(r'^\s*(?:```|~~~)\s*([A-Za-z0-9_+-]*)');
  static final RegExp _rule = RegExp(r'^\s*(?:-{3,}|\*{3,}|_{3,})\s*$');

  // Inline tokens, tried left-to-right at each position. Longer openers first
  // (`***` before `**` before `*`) so the strongest emphasis wins. Each match's
  // markers collapse when inactive; the inner content keeps its style. Non-greedy
  // and newline-free so a token never spans lines.
  static final RegExp _inline = RegExp(
    r'(?<bi1>\*\*\*(?<bi1c>.+?)\*\*\*)'
    r'|(?<bi2>___(?<bi2c>.+?)___)'
    r'|(?<b1>\*\*(?<b1c>.+?)\*\*)'
    r'|(?<b2>__(?<b2c>.+?)__)'
    r'|(?<i1>\*(?<i1c>.+?)\*)'
    r'|(?<i2>_(?<i2c>.+?)_)'
    r'|(?<st>~~(?<stc>.+?)~~)'
    r'|(?<hl>==(?<hlc>.+?)==)'
    r'|(?<cd>`(?<cdc>.+?)`)'
    r'|(?<lk>\[(?<lktext>[^\]]+)\]\((?<lkurl>[^)]+)\))'
    r'|(?<au><(?<auurl>https?://[^>\s]+)>)'
    r'|(?<pu>https?://[^\s)]+)',
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

    // Active selection range (only when focused). A line is "active" when its
    // character range intersects the selection.
    final selection = this.selection;
    final hasActive = focused && selection.isValid && selection.start >= 0;
    final selStart = hasActive ? selection.start : -1;
    final selEnd = hasActive ? selection.end : -1;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = isDark ? atomOneDarkTheme : githubTheme;
    final codeColor = theme['root']?.color ?? c.textSecondary;
    // No per-glyph background — the decoration layer paints the code box behind.
    final codeBase =
        AppTextStyles.codeMonoBlock(scale).copyWith(color: codeColor);
    final fenceStyle =
        AppTextStyles.codeMonoBlock(scale).copyWith(color: c.textMuted);

    final lines = text.split('\n');
    final spans = <InlineSpan>[];
    var inFence = false;
    var fenceLang = 'plaintext';
    var offset = 0;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineStart = offset;
      final lineEnd = offset + line.length;
      final active = hasActive && selStart <= lineEnd && selEnd >= lineStart;

      if (_fence.hasMatch(line)) {
        // Collapse the fence line (```), like other inline markers, so the
        // code box wraps just the content instead of two full-height blank rows.
        spans.add(TextSpan(text: line, style: _marker(fenceStyle, c, active)));
        if (inFence) {
          inFence = false;
          fenceLang = 'plaintext';
        } else {
          inFence = true;
          fenceLang = _parseFenceLang(line);
        }
      } else if (inFence) {
        spans.addAll(_codeSpans(line, fenceLang, theme, codeBase));
      } else {
        spans.addAll(_styleLine(line, base, c, active));
      }

      if (i < lines.length - 1) {
        spans.add(TextSpan(text: '\n', style: base));
      }
      offset = lineEnd + 1; // + the '\n'
    }

    return TextSpan(style: base, children: spans);
  }

  /// Style for a syntax marker. Active: dimmed but visible (editable). Inactive:
  /// collapsed to near-zero width so the rendered content stands alone. The
  /// character stays in the text (cursor mapping is preserved) — only invisible.
  TextStyle _marker(TextStyle lineStyle, AppColorsExtension c, bool active) {
    return active
        ? lineStyle.copyWith(color: c.textMuted)
        : lineStyle.copyWith(
            fontSize: 0.1, letterSpacing: 0, color: Colors.transparent);
  }

  /// Hides a whole-line element (fence line, `---` rule) when inactive while
  /// keeping the line's height, so the decoration layer has a row to draw its
  /// box/rule into. Active: dimmed text so it can be edited.
  TextStyle _hideKeepHeight(TextStyle lineStyle, AppColorsExtension c, bool active) {
    return active
        ? lineStyle.copyWith(color: c.textMuted)
        : lineStyle.copyWith(color: Colors.transparent);
  }

  List<InlineSpan> _styleLine(
      String line, TextStyle base, AppColorsExtension c, bool active) {
    final heading = _heading.firstMatch(line);
    if (heading != null) {
      final hashes = heading.group(1)!;
      final space = heading.group(2)!;
      final content = heading.group(3)!;
      final hStyle =
          _headingStyle(hashes.length).copyWith(color: c.textPrimary);
      return [
        TextSpan(text: '$hashes$space', style: _marker(hStyle, c, active)),
        ..._styleInline(content, hStyle, c, active),
      ];
    }

    // Thematic break (`---`/`***`/`___`): the decoration layer paints the rule;
    // the text is hidden (kept for editing) when inactive.
    if (_rule.hasMatch(line)) {
      return [TextSpan(text: line, style: _hideKeepHeight(base, c, active))];
    }

    // Structural markers (checkbox, bullet, ordered, quote) stay visible even
    // when inactive — they convey block structure, not inline syntax noise.
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
        ..._styleInline(content, contentStyle, c, active),
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
        ..._styleInline(content, base, c, active),
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
        ..._styleInline(content, base, c, active),
      ];
    }

    // Blockquote: the decoration layer paints the left bar. The `>` markers are
    // hidden (but keep their width, so the text indents past the bar) when
    // inactive, and revealed dim when active for editing.
    final quote = _blockquote.firstMatch(line);
    if (quote != null) {
      final marker = quote.group(1)!;
      final content = quote.group(2)!;
      final qStyle =
          base.copyWith(color: c.textSecondary, fontStyle: FontStyle.italic);
      return [
        TextSpan(text: marker, style: _hideKeepHeight(base, c, active)),
        ..._styleInline(content, qStyle, c, active),
      ];
    }

    return _styleInline(line, base, c, active);
  }

  List<InlineSpan> _styleInline(
      String s, TextStyle lineStyle, AppColorsExtension c, bool active) {
    if (s.isEmpty) return const [];
    final spans = <InlineSpan>[];
    final markerStyle = _marker(lineStyle, c, active);
    var last = 0;

    void emit(String open, String content, String close, TextStyle contentStyle) {
      spans.add(TextSpan(text: open, style: markerStyle));
      spans.add(TextSpan(text: content, style: contentStyle));
      spans.add(TextSpan(text: close, style: markerStyle));
    }

    final bold = lineStyle.copyWith(fontWeight: FontWeight.w700);
    final italic = lineStyle.copyWith(fontStyle: FontStyle.italic);
    final boldItalic = lineStyle.copyWith(
        fontWeight: FontWeight.w700, fontStyle: FontStyle.italic);
    final link = lineStyle.copyWith(
        color: c.accent, decoration: TextDecoration.underline);

    for (final m in _inline.allMatches(s)) {
      if (m.start > last) {
        spans.add(TextSpan(text: s.substring(last, m.start), style: lineStyle));
      }
      String? g(String name) => m.namedGroup(name);

      if (g('bi1') != null) {
        emit('***', g('bi1c')!, '***', boldItalic);
      } else if (g('bi2') != null) {
        emit('___', g('bi2c')!, '___', boldItalic);
      } else if (g('b1') != null) {
        emit('**', g('b1c')!, '**', bold);
      } else if (g('b2') != null) {
        emit('__', g('b2c')!, '__', bold);
      } else if (g('i1') != null) {
        emit('*', g('i1c')!, '*', italic);
      } else if (g('i2') != null) {
        emit('_', g('i2c')!, '_', italic);
      } else if (g('st') != null) {
        emit('~~', g('stc')!, '~~',
            lineStyle.copyWith(decoration: TextDecoration.lineThrough));
      } else if (g('hl') != null) {
        emit('==', g('hlc')!, '==',
            lineStyle.copyWith(backgroundColor: c.accentMuted));
      } else if (g('cd') != null) {
        final code = AppTextStyles.codeMonoBlock(scale)
            .copyWith(color: c.accent, backgroundColor: c.surfaceLight);
        spans.add(TextSpan(text: '`', style: markerStyle));
        spans.add(TextSpan(text: g('cdc')!, style: code));
        spans.add(TextSpan(text: '`', style: markerStyle));
      } else if (g('lk') != null) {
        spans.add(TextSpan(text: '[', style: markerStyle));
        spans.add(TextSpan(text: g('lktext')!, style: link));
        spans.add(TextSpan(text: '](', style: markerStyle));
        spans.add(TextSpan(text: g('lkurl')!, style: markerStyle));
        spans.add(TextSpan(text: ')', style: markerStyle));
      } else if (g('au') != null) {
        spans.add(TextSpan(text: '<', style: markerStyle));
        spans.add(TextSpan(text: g('auurl')!, style: link));
        spans.add(TextSpan(text: '>', style: markerStyle));
      } else if (g('pu') != null) {
        spans.add(TextSpan(text: m[0]!, style: link));
      }
      last = m.end;
    }
    if (last < s.length) {
      spans.add(TextSpan(text: s.substring(last), style: lineStyle));
    }
    return spans;
  }

  /// Syntax-highlights one fenced-code line. Falls back to a single mono span
  /// (preserving the text) for unknown languages or parser errors.
  List<InlineSpan> _codeSpans(
      String line, String lang, Map<String, TextStyle> theme, TextStyle codeBase) {
    if (line.isEmpty) return const [];
    final nodes = _parseCached(line, lang);
    if (nodes == null || nodes.isEmpty) {
      return [TextSpan(text: line, style: codeBase)];
    }

    final spans = <TextSpan>[];
    void walk(List<Node> ns, TextStyle current) {
      for (final node in ns) {
        if (node.value != null) {
          final cls = node.className;
          spans.add(TextSpan(
            text: node.value,
            style: cls != null ? current.merge(theme[cls]) : current,
          ));
        } else if (node.children != null) {
          final cls = node.className;
          walk(node.children!, cls != null ? current.merge(theme[cls]) : current);
        }
      }
    }

    walk(nodes, codeBase);

    // Safety: never break the char-preservation invariant.
    final joined = spans.map((s) => s.text ?? '').join();
    if (joined != line) return [TextSpan(text: line, style: codeBase)];
    return spans;
  }

  List<Node>? _parseCached(String line, String lang) {
    final key = '$lang $line';
    final cached = _highlightCache[key];
    if (cached != null || _highlightCache.containsKey(key)) return cached;
    List<Node>? nodes;
    try {
      nodes = highlight.parse(line, language: lang).nodes;
    } catch (_) {
      nodes = null;
    }
    if (_highlightCache.length >= _highlightCacheLimit) _highlightCache.clear();
    _highlightCache[key] = nodes;
    return nodes;
  }

  String _parseFenceLang(String line) {
    final match = _fenceLang.firstMatch(line);
    final lang = match?.group(1)?.trim() ?? '';
    return lang.isEmpty ? 'plaintext' : lang;
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
