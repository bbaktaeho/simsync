import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../services/markdown_editing.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';
import 'editor_block_decorations.dart';
import 'editor_overlay_layout.dart';
import 'markdown_editing_controller.dart';

/// 엔진(레이아웃)과 TextPainter(캐럿 메트릭) 모두 "스트럿 없음"으로 취급하는
/// 스트럿. 줄 높이 floor가 사라져 접힌 줄(닫힌 details 본문, 테이블 구분선)이
/// 실제 ~0 높이가 된다. 데스크탑과 같은 이유로 getter를 재정의한다 —
/// `StrutStyle.disabled`은 EditableText가 본문 폰트로 되살리고,
/// `fontSize: 0.1`은 TextPainter가 "활성 스트럿"으로 보기 때문이다.
class _DisabledStrutStyle extends StrutStyle {
  const _DisabledStrutStyle() : super(height: 1, leading: 0);

  @override
  double? get fontSize => 0.0;

  @override
  StrutStyle inheritFromTextStyle(TextStyle? other) => this;

  @override
  StrutStyle merge(StrutStyle? other) => this;
}

/// 모바일 에디터의 본문 영역. 데스크탑과 같은 인라인 렌더링(Obsidian Live
/// Preview 방식)을 쓴다 — 별도 미리보기 없이 원문 위에 스타일을 입히고,
/// 체크박스는 실제 컨트롤로 그려 탭하면 토글된다.
///
/// 데스크탑과 다른 점은 입력 방식뿐이다. 호버/툴팁/Tab 들여쓰기는 없고,
/// 체크박스 탭 영역만 손가락 크기로 키운다.
class EditorPanel extends StatefulWidget {
  const EditorPanel({
    super.key,
    required this.controller,
    required this.focusNode,
    this.contentScale = 1.0,
    this.readOnly = false,
    this.onChanged,
  });

  final MarkdownEditingController controller;
  final FocusNode focusNode;
  final double contentScale;
  final bool readOnly;
  final VoidCallback? onChanged;

  @override
  State<EditorPanel> createState() => _EditorPanelState();
}

class _EditorPanelState extends State<EditorPanel> {
  final GlobalKey _fieldKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();

  /// 체크박스 한 변 (본문 14px 기준 `[ ]` 폭). 탭 영역은 이보다 크게 준다.
  static const double _checkboxSize = 14;
  static const double _checkboxTapPadding = 6;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() => widget.controller.focused = widget.focusNode.hasFocus);
  }

  /// 콘텐츠 TextField 내부의 [RenderEditable]. 데코/오버레이가 이번 프레임의
  /// 실제 좌표를 읽는 데 쓴다.
  RenderEditable? _renderEditable() {
    RenderEditable? found;
    void visit(RenderObject child) {
      if (found != null) return;
      if (child is RenderEditable) {
        found = child;
        return;
      }
      child.visitChildren(visit);
    }

    final root = _fieldKey.currentContext?.findRenderObject();
    if (root != null) visit(root);
    return found;
  }

  Listenable get _overlayRelayout =>
      Listenable.merge([widget.controller, _scrollController]);

  /// 체크박스 탭: `[ ]` ↔ `[x]`. 글자 수가 같아 캐럿은 건드리지 않는다.
  void _toggleCheckbox(CheckboxRegion box) {
    if (widget.readOnly) return;
    final text = widget.controller.text;
    if (box.end > text.length || !' xX'.contains(text[box.markOffset])) return;
    widget.controller.value = widget.controller.value.copyWith(
      text: text.replaceRange(
        box.markOffset,
        box.markOffset + 1,
        box.checked ? ' ' : 'x',
      ),
    );
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    widget.controller.scale = widget.contentScale;

    final baseStyle = AppTextStyles.mdBody(
      widget.contentScale,
    ).copyWith(color: c.textPrimary);
    final bodyStyle = (Theme.of(context).textTheme.bodyLarge ?? const TextStyle())
        .merge(baseStyle);

    final field = TextField(
      key: _fieldKey,
      controller: widget.controller,
      focusNode: widget.focusNode,
      scrollController: _scrollController,
      selectionHeightStyle: ui.BoxHeightStyle.max,
      onChanged: widget.readOnly ? null : (_) => widget.onChanged?.call(),
      readOnly: widget.readOnly,
      inputFormatters: widget.readOnly
          ? null
          : [
              MarkdownListInputFormatter(),
              DetailsBlockInputFormatter(),
              CheckboxShorthandInputFormatter(),
            ],
      maxLines: null,
      expands: true,
      keyboardType: TextInputType.multiline,
      textAlignVertical: TextAlignVertical.top,
      cursorColor: c.accent,
      style: bodyStyle,
      strutStyle: const _DisabledStrutStyle(),
      decoration: InputDecoration(
        hintText: '마크다운으로 작성하세요...',
        hintStyle: bodyStyle.copyWith(color: c.textMuted),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        contentPadding: EdgeInsets.zero,
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: IgnorePointer(child: _buildDecorations(c)),
        ),
        field,
        Positioned.fill(
          child: ClipRect(child: _buildCheckboxOverlays(c)),
        ),
      ],
    );
  }

  // 코드 박스 / `---` 규칙선 / 인용문 바를 필드 뒤에 그린다.
  Widget _buildDecorations(AppColorsExtension c) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final text = widget.controller.text;
        final tables = findTableRegions(text);
        final details = findDetailsRegions(text);
        final regions = [
          ...filterEditorRegions(parseEditorBlockRegions(text), tables, details),
          ...detailsGuideRegions(details),
        ];
        if (regions.isEmpty) return const SizedBox.expand();
        return CustomPaint(
          painter: EditorBlockDecorationPainter(
            editable: _renderEditable,
            regions: regions,
            repaint: _scrollController,
            codeBackground: c.surfaceLight,
            codeBorder: c.border,
            ruleColor: c.border,
            quoteBar: c.textMuted,
            detailsGuide: c.textMuted.withValues(alpha: 0.35),
          ),
        );
      },
    );
  }

  // 감춰진 `[x]` 자리에 실제 체크박스를 겹친다.
  Widget _buildCheckboxOverlays(AppColorsExtension c) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final boxes = findCheckboxRegions(widget.controller.text);
        if (boxes.isEmpty) return const SizedBox.shrink();
        return CustomMultiChildLayout(
          delegate: EditorOverlayLayoutDelegate(
            editable: _renderEditable,
            relayout: _overlayRelayout,
            items: [
              for (final b in boxes)
                EditorOverlayItem(
                  id: b.start,
                  start: b.start,
                  end: b.start + 1,
                  anchor: EditorOverlayAnchor.charBox,
                ),
            ],
          ),
          children: [
            for (final b in boxes)
              LayoutId(
                id: b.start,
                child: _CheckboxToggle(
                  key: ValueKey('checkbox:${b.start}'),
                  checked: b.checked,
                  size: _checkboxSize * widget.contentScale,
                  tapPadding: _checkboxTapPadding,
                  onTap: widget.readOnly ? null : () => _toggleCheckbox(b),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 작업 목록 체크박스. 그림은 감춰진 `[x]` 자리에 정확히 얹고, 탭 영역만
/// 손가락 크기로 넓힌다 (그림 크기를 키우면 글자 흐름을 밀어낸다).
class _CheckboxToggle extends StatelessWidget {
  const _CheckboxToggle({
    super.key,
    required this.checked,
    required this.size,
    required this.tapPadding,
    required this.onTap,
  });

  final bool checked;
  final double size;
  final double tapPadding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.all(tapPadding),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: checked ? c.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
            border: Border.all(
              color: checked ? c.accent : c.textMuted,
              width: 1.2,
            ),
          ),
          child: checked
              ? Icon(Icons.check_rounded, size: size - 2, color: c.textOnAccent)
              : null,
        ),
      ),
    );
  }
}
