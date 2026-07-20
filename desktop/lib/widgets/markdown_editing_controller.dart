import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:highlight/highlight.dart' show highlight, Node;

import '../services/markdown_editing.dart';
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

  /// 언어 미지정 fence 블록의 자동 감지 캐시 (블록 내용 → 감지 언어 또는 null).
  final Map<String, String?> _autoLangCache = {};
  static const int _autoLangCacheLimit = 100;

  /// 블록 시작 오프셋 → 직전 감지 언어. 캐럿이 블록 안에 있는 동안(내용이
  /// 계속 바뀌어 캐시 미스가 나는 동안) 전체 재감지 대신 직전 결과를 유지한다.
  final Map<int, String?> _stickyAutoLang = {};

  static final RegExp _heading = RegExp(r'^(#{1,6})(\s+)(.*)$');
  // 인용문: 새 문법은 `| `, 레거시 `> `도 하위 호환으로 계속 렌더링한다.
  // 테이블 줄은 buildTextSpan에서 먼저 걸러지므로 여기 도달하지 않는다.
  static final RegExp _blockquote = RegExp(r'^(\s*(?:[>|]\s?)+)(.*)$');
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

    // Table lines are hidden so the decoration layer can paint a rendered table
    // over them: header/body rows go transparent (keeping their height as the
    // row's vertical space). The separator line collapses to ~0 height (the
    // editor strut is a near-zero explicit minimum, so a tiny font really
    // shrinks the line box).
    final tableRowStarts = <int>{};
    final tableSepStarts = <int>{};
    for (final t in findTableRegions(text)) {
      for (final r in t.rowRanges) {
        tableRowStarts.add(r.start);
      }
      tableSepStarts.add(t.separatorRange.start);
    }

    // <details> 블록: 태그 줄은 캐럿이 없을 때 높이까지 접고, summary는
    // 제목으로 강조한다. 닫힌(open 속성 없는) 블록의 본문 줄은 실제로 접는다
    // — 에디터 스트럿이 극소 명시값이라 극소 폰트 줄의 라인 박스가 ~0으로
    // 줄어든다. open 속성은 파일에 저장되어 GitHub 웹과도 상태를 공유한다.
    final detailsTagStarts = <int>{};
    final detailsSummaryStarts = <int>{};
    final detailsCollapsedStarts = <int>{};
    for (final d in findDetailsRegions(text)) {
      detailsTagStarts.add(d.detailsLineRange.start);
      detailsTagStarts.add(d.closeLineRange.start);
      detailsSummaryStarts.add(d.summaryLineRange.start);
      if (!d.open) {
        for (final r in d.bodyLineRanges) {
          detailsCollapsedStarts.add(r.start);
        }
      }
    }

    // 인라인 이미지 줄: 태그 텍스트는 항상 숨기고 오버레이가 이미지를 그린다.
    final imageStarts = <int, ImageRegion>{};
    for (final r in findImageRegions(text)) {
      imageStarts[r.start] = r;
    }

    final lines = text.split('\n');
    final autoLangByFence =
        _computeAutoLangs(lines, selStart, selEnd, hasActive);
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
        // Fence lines stay full-height (so the caret can land on them) but go
        // transparent when inactive; the decoration box wraps only the content.
        spans.add(
            TextSpan(text: line, style: _hideKeepHeight(fenceStyle, c, active)));
        if (inFence) {
          inFence = false;
          fenceLang = 'plaintext';
        } else {
          inFence = true;
          fenceLang = _parseFenceLang(line);
          if (fenceLang == 'plaintext') {
            fenceLang = autoLangByFence[lineStart] ?? 'plaintext';
          }
        }
      } else if (inFence) {
        spans.addAll(_codeSpans(line, fenceLang, theme, codeBase));
      } else if (detailsCollapsedStarts.contains(lineStart)) {
        // 닫힌 details의 본문 줄: 높이까지 접는다. (테이블/이미지 줄이어도
        // 접힘이 우선 — 오버레이는 밴드 높이 ~0을 보고 스스로 숨는다.)
        spans.add(TextSpan(text: line, style: _collapsed(base)));
      } else if (tableSepStarts.contains(lineStart)) {
        spans.add(TextSpan(text: line, style: _collapsed(base)));
      } else if (tableRowStarts.contains(lineStart)) {
        spans.add(TextSpan(text: line, style: base.copyWith(color: Colors.transparent)));
      } else if (imageStarts.containsKey(lineStart)) {
        spans.addAll(_imageLineSpans(line, imageStarts[lineStart]!, base));
      } else if (detailsTagStarts.contains(lineStart)) {
        // 태그 줄은 구조 노이즈: 캐럿이 있으면 편집용으로 노출, 아니면 접는다.
        spans.add(TextSpan(
            text: line,
            style:
                active ? base.copyWith(color: c.textMuted) : _collapsed(base)));
      } else if (detailsSummaryStarts.contains(lineStart)) {
        spans.addAll(_summarySpans(line, base, c, active));
      } else {
        spans.addAll(_styleLine(line, base, c, active));
      }

      if (i < lines.length - 1) {
        // 접힌 줄은 그 줄을 끝내는 개행까지 접어야 라인 박스가 완전히 사라진다.
        final collapseNewline = detailsCollapsedStarts.contains(lineStart) ||
            tableSepStarts.contains(lineStart) ||
            (detailsTagStarts.contains(lineStart) && !active);
        spans.add(TextSpan(
            text: '\n', style: collapseNewline ? _collapsed(base) : base));
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

  /// 줄을 높이까지 접는다(투명 + 극소 폰트). 에디터 스트럿이 극소 명시값이라
  /// 라인 박스가 실제로 ~0 높이로 줄어든다. 문자는 남으므로 invariant는
  /// 유지되고, 캐럿/선택도 정상 동작한다.
  TextStyle _collapsed(TextStyle base) => base.copyWith(
      fontSize: 0.1, height: 1.0, letterSpacing: 0, color: Colors.transparent);

  /// 이미지 줄 상하 여백 (예약 높이 = 이미지 높이 + 여백*2).
  static const double imagePadding = 6.0;

  /// 예약 글리프의 라인 박스 배율. 폰트의 잉크 범위(ascent+descent, Inter는
  /// ~1.21em)보다 넉넉해야 한다 — height 1.0을 쓰면 잉크가 라인 박스를 위로
  /// 넘치고, RenderEditable의 밴드 측정(top)이 윗줄까지 올라가 큰 이미지가
  /// 위 텍스트를 덮는다 (이미지가 클수록 침범이 커지는 것이 실측/수식으로
  /// 확인된 버그). fontSize를 그만큼 줄이므로 예약 높이는 변하지 않는다.
  static const double _reservedGlyphHeightFactor = 1.3;

  /// 이미지 줄: 첫 글자에 (이미지 높이 + 여백) 크기의 라인 박스를 줘 줄
  /// 높이를 예약하고, 전체를 투명 처리한다. 오버레이가 이 밴드 위에 이미지를
  /// 그린다. 캐럿이 줄에 있어도 원문을 노출하지 않는다(높이 요동 방지) —
  /// 수정/삭제는 오버레이 컨트롤로 한다.
  List<InlineSpan> _imageLineSpans(String line, ImageRegion r, TextStyle base) {
    final reserved = (r.height + imagePadding * 2) * scale;
    return [
      TextSpan(
        text: line.substring(0, 1),
        style: base.copyWith(
            fontSize: reserved / _reservedGlyphHeightFactor,
            height: _reservedGlyphHeightFactor,
            color: Colors.transparent),
      ),
      if (line.length > 1)
        TextSpan(
          text: line.substring(1),
          style: base.copyWith(
              fontSize: 0.1,
              height: 1.0,
              letterSpacing: 0,
              color: Colors.transparent),
        ),
    ];
  }

  static final RegExp _summaryLine =
      RegExp(r'^(\s*<summary>)(.*)(</summary>\s*)$');

  /// `<summary>제목</summary>` 줄: 태그는 마커로 접고 제목은 강조한다.
  /// 접기 버튼은 텍스트 왼쪽의 거터에 있으므로 제목과 겹치지 않는다.
  List<InlineSpan> _summarySpans(
      String line, TextStyle base, AppColorsExtension c, bool active) {
    final m = _summaryLine.firstMatch(line);
    if (m == null) return _styleLine(line, base, c, active);
    final titleStyle = base.copyWith(fontWeight: FontWeight.w600);
    return [
      TextSpan(text: m.group(1)!, style: _marker(base, c, active)),
      ..._styleInline(m.group(2)!, titleStyle, c, active),
      TextSpan(text: m.group(3)!, style: _marker(base, c, active)),
    ];
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

  /// 언어 미지정 fence 블록마다 자동 감지 언어를 정한다.
  /// 반환: fence 여는 줄 시작 오프셋 → 언어.
  Map<int, String> _computeAutoLangs(
      List<String> lines, int selStart, int selEnd, bool hasActive) {
    final result = <int, String>{};
    var offset = 0;
    var inFence = false;
    var fenceStart = -1;
    var explicitLang = false;
    final content = StringBuffer();

    for (final line in lines) {
      final lineStart = offset;
      final lineEnd = offset + line.length;
      if (_fence.hasMatch(line)) {
        if (inFence) {
          if (!explicitLang && content.isNotEmpty) {
            // 캐럿이 블록(여는 fence..닫는 fence) 안이면 감지를 미룬다.
            final caretInside =
                hasActive && selStart <= lineEnd && selEnd >= fenceStart;
            final lang =
                _autoLang(content.toString(), fenceStart, caretInside);
            if (lang != null) result[fenceStart] = lang;
          }
          inFence = false;
        } else {
          inFence = true;
          fenceStart = lineStart;
          explicitLang = _parseFenceLang(line) != 'plaintext';
          content.clear();
        }
      } else if (inFence && !explicitLang) {
        if (content.isNotEmpty) content.write('\n');
        content.write(line);
      }
      offset = lineEnd + 1;
    }
    return result;
  }

  String? _autoLang(String blockText, int blockStart, bool caretInside) {
    if (_autoLangCache.containsKey(blockText)) {
      final cached = _autoLangCache[blockText];
      if (_stickyAutoLang.length >= _autoLangCacheLimit) _stickyAutoLang.clear();
      _stickyAutoLang[blockStart] = cached;
      return cached;
    }
    if (caretInside) return _stickyAutoLang[blockStart];
    final lang = detectFenceLanguage(blockText);
    if (_autoLangCache.length >= _autoLangCacheLimit) _autoLangCache.clear();
    _autoLangCache[blockText] = lang;
    if (_stickyAutoLang.length >= _autoLangCacheLimit) _stickyAutoLang.clear();
    _stickyAutoLang[blockStart] = lang;
    return lang;
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

  /// 블록 전체 텍스트로 언어를 자동 감지한다. 신뢰도가 낮으면 null
  /// (무채색 유지). highlight의 auto-detection은 비싸므로 호출부에서 캐시한다.
  static String? detectFenceLanguage(String blockText) {
    try {
      final result = runZoned(
        () => highlight.parse(blockText, autoDetection: true),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) {
            // highlight의 autoDetection은 언어별 시도 중 실패를 print로 흘린다.
            // 라이브러리 내부 노이즈이므로 이 호출 범위에서만 무음 처리한다.
          },
        ),
      );
      if ((result.relevance ?? 0) < 5) return null;
      return result.language;
    } catch (_) {
      return null;
    }
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
