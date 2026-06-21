import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/markdown_editing.dart';
import '../theme/app_colors.dart';

/// A rendered, horizontally-scrollable markdown table shown inline in the editor
/// over its (hidden) markdown source.
///
/// When [active] (the caret is inside the table) it shows a `+` button on the
/// right (add column) and one at the bottom (add row); tapping the table when it
/// is inactive calls [onActivate] so the editor can move the caret into it. Cell
/// CONTENT is read-only here — it is edited via the toolbar's grid dialog.
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
  });

  final MarkdownTableData data;
  final bool active;
  final TextStyle cellStyle;
  final VoidCallback onActivate;
  final VoidCallback onAddRow;
  final VoidCallback onAddColumn;
  final VoidCallback onRemove;

  /// Columns are at least this wide; past that the table scrolls horizontally.
  static const double minColumnWidth = 132;

  @override
  State<InlineTableView> createState() => _InlineTableViewState();
}

class _InlineTableViewState extends State<InlineTableView> {
  final ScrollController _hScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  Alignment _cellAlignment(MarkdownTableAlign a) => switch (a) {
        MarkdownTableAlign.left => Alignment.centerLeft,
        MarkdownTableAlign.center => Alignment.center,
        MarkdownTableAlign.right => Alignment.centerRight,
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
          Container(
            width: colW,
            alignment: _cellAlignment(data.aligns[k]),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isHeader ? c.accentSubtle : null,
              border: Border(
                right: k < data.columns - 1
                    ? BorderSide(color: c.border)
                    : BorderSide.none,
                bottom: !isLastRow ? BorderSide(color: c.border) : BorderSide.none,
              ),
            ),
            child: Text(
              k < data.rows[r].length ? data.rows[r][k] : '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: isHeader ? headerStyle : bodyStyle,
            ),
          ),
      ],
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
