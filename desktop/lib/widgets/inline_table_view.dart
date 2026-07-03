import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/markdown_editing.dart';
import '../theme/app_colors.dart';

/// A rendered, horizontally-scrollable markdown table shown inline in the editor
/// over its (hidden) markdown source.
///
/// When [active] (the caret is inside the table) it shows a `+` button on the
/// right (add column), one at the bottom (add row), a red `×` at the top-left
/// (remove the table), and each cell becomes editable: tap a cell to type its
/// content directly — every keystroke is committed to the markdown via
/// [onCellChanged]. Tapping the table when it is inactive calls [onActivate].
class InlineTableView extends StatefulWidget {
  const InlineTableView({
    super.key,
    required this.data,
    required this.active,
    required this.cellStyle,
    required this.onActivate,
    required this.onAddRow,
    required this.onAddColumn,
    required this.onRemove,
    required this.onCellChanged,
    required this.onRemoveRow,
    required this.onRemoveColumn,
  });

  final MarkdownTableData data;
  final bool active;
  final TextStyle cellStyle;
  final VoidCallback onActivate;
  final VoidCallback onAddRow;
  final VoidCallback onAddColumn;
  final VoidCallback onRemove;

  /// Called with the new text whenever an editable cell changes.
  final void Function(int row, int col, String value) onCellChanged;

  /// Removes the given body row (index >= 1; the header row is never removable).
  final void Function(int row) onRemoveRow;

  /// Removes the given column (only offered when more than one column exists).
  final void Function(int col) onRemoveColumn;

  /// Columns are at least this wide; past that the table scrolls horizontally.
  static const double minColumnWidth = 132;

  @override
  State<InlineTableView> createState() => _InlineTableViewState();
}

class _InlineTableViewState extends State<InlineTableView> {
  final ScrollController _hScroll = ScrollController();
  final TextEditingController _cellCtrl = TextEditingController();
  final FocusNode _cellFocus = FocusNode();

  /// The (row, col) currently being edited, or null. Survives the frequent
  /// overlay rebuilds because the State is keyed by the table's start offset.
  ({int row, int col})? _editingCell;

  @override
  void initState() {
    super.initState();
    _cellFocus.addListener(_handleCellFocusChange);
    // The column − buttons live in the outer stack but must stay over their
    // (horizontally scrollable) columns, so reposition them as the table scrolls.
    _hScroll.addListener(_handleHScroll);
  }

  void _handleHScroll() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(InlineTableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final editing = _editingCell;
    if (editing == null) return;
    // Exit edit mode if the table deactivated, the edited cell fell out of
    // bounds, or the row/column structure changed. A structural change (a row or
    // column was added/removed) shifts cell indices, so leaving the editor open
    // would write the in-progress text into a different cell than is on screen.
    // Per-keystroke commits only change a cell's text, not the counts, so they
    // keep the editor open.
    final structureChanged =
        oldWidget.data.rows.length != widget.data.rows.length ||
            oldWidget.data.columns != widget.data.columns;
    if (!widget.active ||
        structureChanged ||
        editing.row >= widget.data.rows.length ||
        editing.col >= widget.data.columns) {
      _editingCell = null;
      if (_cellFocus.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _editingCell == null) _cellFocus.unfocus();
        });
      }
    }
  }

  @override
  void dispose() {
    _cellFocus.removeListener(_handleCellFocusChange);
    _cellFocus.dispose();
    _cellCtrl.dispose();
    _hScroll.removeListener(_handleHScroll);
    _hScroll.dispose();
    super.dispose();
  }

  void _handleCellFocusChange() {
    // The value is committed on each keystroke, so blur just exits edit mode.
    if (!_cellFocus.hasFocus && _editingCell != null && mounted) {
      setState(() => _editingCell = null);
    }
  }

  void _startEdit(int row, int col, String value) {
    setState(() {
      _editingCell = (row: row, col: col);
      _cellCtrl.text = value;
      _cellCtrl.selection = TextSelection.collapsed(offset: value.length);
    });
    _cellFocus.requestFocus();
  }

  Alignment _cellAlignment(MarkdownTableAlign a) => switch (a) {
        MarkdownTableAlign.left => Alignment.centerLeft,
        MarkdownTableAlign.center => Alignment.center,
        MarkdownTableAlign.right => Alignment.centerRight,
      };

  TextAlign _textAlign(MarkdownTableAlign a) => switch (a) {
        MarkdownTableAlign.left => TextAlign.left,
        MarkdownTableAlign.center => TextAlign.center,
        MarkdownTableAlign.right => TextAlign.right,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final data = widget.data;
    final cols = data.columns;
    if (cols == 0 || data.rows.isEmpty) return const SizedBox.shrink();

    final headerStyle = widget.cellStyle.copyWith(
      fontWeight: FontWeight.w600,
      color: c.textPrimary,
    );
    final bodyStyle = widget.cellStyle.copyWith(color: c.textPrimary);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Few columns stretch to fill the width; many columns hit the min width
        // and the table scrolls horizontally instead of shrinking off-screen.
        final colW =
            math.max(InlineTableView.minColumnWidth, constraints.maxWidth / cols);
        final totalWidth = colW * cols;
        // Rows split the measured band evenly; column buttons offset by scroll.
        final rowH = constraints.maxHeight / data.rows.length;
        final scrollX = _hScroll.hasClients ? _hScroll.offset : 0.0;

        final grid = Container(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(6),
          ),
          clipBehavior: Clip.antiAlias,
          child: Scrollbar(
            controller: _hScroll,
            thumbVisibility: widget.active && totalWidth > constraints.maxWidth,
            child: SingleChildScrollView(
              controller: _hScroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalWidth,
                child: Column(
                  children: [
                    for (var r = 0; r < data.rows.length; r++)
                      Expanded(
                        child: _row(c, data, r, colW, headerStyle, bodyStyle),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.active ? null : widget.onActivate,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: grid),
              if (widget.active) ...[
                Positioned(
                  top: 0,
                  bottom: 14,
                  right: -1,
                  child: Center(
                    child: _CornerButton(
                      color: c.accent,
                      icon: Icons.add_rounded,
                      tooltip: '열 추가',
                      onTap: widget.onAddColumn,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 14,
                  bottom: -1,
                  child: Center(
                    child: _CornerButton(
                      color: c.accent,
                      icon: Icons.add_rounded,
                      tooltip: '행 추가',
                      onTap: widget.onAddRow,
                    ),
                  ),
                ),
                // Remove the whole table (top-left corner).
                Positioned(
                  top: -1,
                  left: -1,
                  child: _CornerButton(
                    color: c.error,
                    icon: Icons.close_rounded,
                    tooltip: '테이블 삭제',
                    onTap: widget.onRemove,
                  ),
                ),
                // Remove a body row — blue − on the left of each row (the header
                // row, index 0, is intentionally not removable). Hugs the edge
                // (centre stays inside the bounds so the button stays tappable).
                for (var r = 1; r < data.rows.length; r++)
                  Positioned(
                    left: -8,
                    top: (r + 0.5) * rowH - 12,
                    child: _CornerButton(
                      color: c.accent,
                      icon: Icons.remove_rounded,
                      tooltip: '행 제거',
                      onTap: () => widget.onRemoveRow(r),
                    ),
                  ),
                // Remove a column — blue − above each column (only when there is
                // more than one). Tracks the horizontal scroll. Skipped within a
                // corner-button width of either edge so it can never stack on top
                // of the × (top-left) or +col (right) and steal their taps.
                if (cols > 1)
                  for (var k = 0; k < cols; k++)
                    if ((k + 0.5) * colW - scrollX >= 36 &&
                        (k + 0.5) * colW - scrollX <=
                            constraints.maxWidth - 36)
                      Positioned(
                        top: -8,
                        left: (k + 0.5) * colW - scrollX - 12,
                        child: _CornerButton(
                          color: c.accent,
                          icon: Icons.remove_rounded,
                          tooltip: '열 제거',
                          onTap: () => widget.onRemoveColumn(k),
                        ),
                      ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _row(
    AppColorsExtension c,
    MarkdownTableData data,
    int r,
    double colW,
    TextStyle headerStyle,
    TextStyle bodyStyle,
  ) {
    final isHeader = r == 0;
    final isLastRow = r == data.rows.length - 1;
    return Row(
      children: [
        for (var k = 0; k < data.columns; k++)
          _cell(c, data, r, k, colW, isHeader, isLastRow,
              isHeader ? headerStyle : bodyStyle),
      ],
    );
  }

  Widget _cell(
    AppColorsExtension c,
    MarkdownTableData data,
    int r,
    int k,
    double colW,
    bool isHeader,
    bool isLastRow,
    TextStyle style,
  ) {
    final value = k < data.rows[r].length ? data.rows[r][k] : '';
    final editing =
        widget.active && _editingCell?.row == r && _editingCell?.col == k;

    final Widget child = editing
        ? TextField(
            controller: _cellCtrl,
            focusNode: _cellFocus,
            maxLines: 1,
            textAlign: _textAlign(data.aligns[k]),
            style: style,
            cursorColor: c.accent,
            decoration: const InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (text) => widget.onCellChanged(r, k, text),
            onSubmitted: (_) => _cellFocus.unfocus(), // Enter exits the cell
          )
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.active ? () => _startEdit(r, k, value) : null,
            child: Align(
              alignment: _cellAlignment(data.aligns[k]),
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          );

    return Container(
      width: colW,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isHeader
            ? c.accentSubtle
            : (editing ? c.surfaceLight : null),
        border: Border(
          right: k < data.columns - 1
              ? BorderSide(color: c.border)
              : BorderSide.none,
          bottom: !isLastRow ? BorderSide(color: c.border) : BorderSide.none,
        ),
      ),
      alignment: Alignment.centerLeft,
      child: child,
    );
  }
}

/// A round 24px overlay button (white glyph) shown on a table edge while the
/// table is active — `+` for add row/column, red `×` for removing the table.
class _CornerButton extends StatelessWidget {
  const _CornerButton({
    required this.color,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        elevation: 1,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 24,
            height: 24,
            child: Icon(icon, size: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
