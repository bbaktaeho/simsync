import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../services/markdown_editing.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';
import 'editor_block_decorations.dart';
import 'editor_overlay_layout.dart';
import 'inline_table_view.dart';
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
    // 모바일에는 아직 이미지 첨부/로드 경로가 없다. 감추면 <img> 줄이 통째로
    // 사라져 보이므로 원문 그대로 렌더한다.
    widget.controller.renderInlineImages = false;

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
          child: ClipRect(child: _buildTableOverlays(bodyStyle)),
        ),
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

  // 숨겨진 표 마크다운 위에 실제 표를 겹친다. 탭하면 캐럿이 표 안으로 들어가
  // 편집 컨트롤이 뜬다 (데스크탑과 같은 오버레이 패턴).
  Widget _buildTableOverlays(TextStyle bodyStyle) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final tables = findTableRegions(widget.controller.text);
        if (tables.isEmpty) return const SizedBox.shrink();
        final sel = widget.controller.selection;
        final caret = sel.isValid ? sel.baseOffset : -1;
        return CustomMultiChildLayout(
          delegate: EditorOverlayLayoutDelegate(
            editable: _renderEditable,
            relayout: _overlayRelayout,
            items: [
              for (final t in tables)
                EditorOverlayItem(
                  id: t.start,
                  start: t.start,
                  end: t.end,
                  anchor: EditorOverlayAnchor.band,
                ),
            ],
          ),
          children: [
            for (final t in tables)
              LayoutId(
                id: t.start,
                child: InlineTableView(
                  key: ValueKey(t.start),
                  data: t.table,
                  active: !widget.readOnly && caret >= t.start && caret <= t.end,
                  cellStyle: bodyStyle,
                  onActivate: () => _activateTable(t),
                  onAddRow: () => _mutateTable(
                    t,
                    MarkdownTableData(
                      [...t.table.rows, List.filled(t.table.columns, '')],
                      t.table.aligns,
                    ),
                  ),
                  onAddColumn: () => _mutateTable(
                    t,
                    MarkdownTableData(
                      [for (final row in t.table.rows) [...row, '']],
                      [...t.table.aligns, MarkdownTableAlign.left],
                    ),
                  ),
                  onRemove: () => _removeTable(t),
                  onCellChanged: (row, col, value) =>
                      _setTableCell(t, row, col, value),
                  onRemoveRow: (row) => _removeTableRow(t, row),
                  onRemoveColumn: (col) => _removeTableColumn(t, col),
                ),
              ),
          ],
        );
      },
    );
  }

  void _activateTable(TableRegion table) {
    if (widget.readOnly) return;
    widget.focusNode.requestFocus();
    widget.controller.selection = TextSelection.collapsed(
      offset: table.start.clamp(0, widget.controller.text.length),
    );
  }

  void _mutateTable(TableRegion table, MarkdownTableData next) {
    if (widget.readOnly) return;
    final text = widget.controller.text;
    final s = table.start.clamp(0, text.length);
    final e = table.end.clamp(s, text.length);
    widget.controller.value = TextEditingValue(
      text: text.replaceRange(s, e, serializeMarkdownTable(next)),
      selection: TextSelection.collapsed(offset: s),
    );
    widget.onChanged?.call();
  }

  void _removeTable(TableRegion table) {
    if (widget.readOnly) return;
    final text = widget.controller.text;
    final s = table.start.clamp(0, text.length);
    var e = table.end.clamp(s, text.length);
    if (e < text.length && text[e] == '\n') e++;
    widget.controller.value = TextEditingValue(
      text: text.replaceRange(s, e, ''),
      selection: TextSelection.collapsed(offset: s),
    );
    widget.onChanged?.call();
  }

  void _setTableCell(TableRegion table, int row, int col, String value) {
    final data = table.table;
    if (row < 0 || row >= data.rows.length || col < 0 || col >= data.columns) {
      return;
    }
    _mutateTable(
      table,
      MarkdownTableData(
        [
          for (var r = 0; r < data.rows.length; r++)
            [
              for (var k = 0; k < data.columns; k++)
                (r == row && k == col)
                    ? value
                    : (k < data.rows[r].length ? data.rows[r][k] : ''),
            ],
        ],
        data.aligns,
      ),
    );
  }

  void _removeTableRow(TableRegion table, int row) {
    final data = table.table;
    if (row <= 0 || row >= data.rows.length) return;
    _mutateTable(
      table,
      MarkdownTableData(
        [
          for (var i = 0; i < data.rows.length; i++)
            if (i != row) data.rows[i],
        ],
        data.aligns,
      ),
    );
  }

  void _removeTableColumn(TableRegion table, int col) {
    final data = table.table;
    if (col < 0 || col >= data.columns || data.columns <= 1) return;
    _mutateTable(
      table,
      MarkdownTableData(
        [
          for (final row in data.rows)
            [
              for (var j = 0; j < data.columns; j++)
                if (j != col) (j < row.length ? row[j] : ''),
            ],
        ],
        [
          for (var j = 0; j < data.columns; j++)
            if (j != col) data.aligns[j],
        ],
      ),
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
