import 'package:flutter/material.dart';

import '../services/markdown_editing.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';

/// A grid editor for markdown tables: you fill cells in a real table instead of
/// typing pipe syntax by hand. Returns the serialized GFM markdown on save, or
/// null on cancel. Pass [initial] to edit an existing table.
class TableEditorDialog extends StatefulWidget {
  const TableEditorDialog({super.key, this.initial});

  final MarkdownTableData? initial;

  static Future<String?> show(BuildContext context, {MarkdownTableData? initial}) {
    return showDialog<String>(
      context: context,
      builder: (_) => TableEditorDialog(initial: initial),
    );
  }

  @override
  State<TableEditorDialog> createState() => _TableEditorDialogState();
}

class _TableEditorDialogState extends State<TableEditorDialog> {
  static const double _cellWidth = 132;

  late List<List<TextEditingController>> _cells; // [row][col]; row 0 = header
  late List<MarkdownTableAlign> _aligns;

  int get _columns => _aligns.length;

  @override
  void initState() {
    super.initState();
    final data = widget.initial ?? MarkdownTableData.blank();
    _aligns = List.of(data.aligns);
    _cells = [
      for (final row in data.rows)
        [for (final cell in row) TextEditingController(text: cell)],
    ];
  }

  @override
  void dispose() {
    for (final row in _cells) {
      for (final c in row) {
        c.dispose();
      }
    }
    super.dispose();
  }

  void _addRow() {
    setState(() => _cells.add(
        [for (var i = 0; i < _columns; i++) TextEditingController()]));
  }

  void _addColumn() {
    setState(() {
      for (final row in _cells) {
        row.add(TextEditingController());
      }
      _aligns.add(MarkdownTableAlign.left);
    });
  }

  void _removeRow(int r) {
    if (r == 0 || _cells.length <= 2) return; // keep header + ≥1 body row
    setState(() {
      for (final c in _cells[r]) {
        c.dispose();
      }
      _cells.removeAt(r);
    });
  }

  void _removeColumn(int col) {
    if (_columns <= 1) return;
    setState(() {
      for (final row in _cells) {
        row[col].dispose();
        row.removeAt(col);
      }
      _aligns.removeAt(col);
    });
  }

  void _cycleAlign(int col) {
    setState(() {
      const order = MarkdownTableAlign.values;
      _aligns[col] = order[(_aligns[col].index + 1) % order.length];
    });
  }

  IconData _alignIcon(MarkdownTableAlign a) => switch (a) {
        MarkdownTableAlign.left => Icons.format_align_left_rounded,
        MarkdownTableAlign.center => Icons.format_align_center_rounded,
        MarkdownTableAlign.right => Icons.format_align_right_rounded,
      };

  void _save() {
    final data = MarkdownTableData(
      [
        for (final row in _cells) [for (final c in row) c.text],
      ],
      _aligns,
    );
    Navigator.pop(context, serializeMarkdownTable(data));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusComfortable),
        side: BorderSide(color: c.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.spacingLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.table_chart_outlined, size: 18, color: c.accent),
                  const SizedBox(width: AppDimensions.spacingSm),
                  Text(
                    widget.initial == null ? '표 삽입' : '표 편집',
                    style: Theme.of(context).textTheme.titleSmall!.copyWith(
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.spacingMd),
              Flexible(child: _buildGrid(c)),
              const SizedBox(height: AppDimensions.spacingLg),
              Row(
                children: [
                  _GridButton(
                    icon: Icons.add_rounded,
                    label: '행',
                    onTap: _addRow,
                  ),
                  const SizedBox(width: AppDimensions.spacingSm),
                  _GridButton(
                    icon: Icons.add_rounded,
                    label: '열',
                    onTap: _addColumn,
                  ),
                  const Spacer(),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: c.textSecondary,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      textStyle: AppTextStyles.captionMedium,
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('취소'),
                  ),
                  const SizedBox(width: AppDimensions.spacingSm),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      textStyle: AppTextStyles.captionSemibold,
                    ),
                    onPressed: _save,
                    child: Text(widget.initial == null ? '삽입' : '저장'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrid(AppColorsExtension c) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Per-column controls: alignment + delete column.
            Row(
              children: [
                for (var col = 0; col < _columns; col++)
                  SizedBox(
                    width: _cellWidth,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _IconBtn(
                          icon: _alignIcon(_aligns[col]),
                          tooltip: '정렬',
                          color: c.textSecondary,
                          onTap: () => _cycleAlign(col),
                        ),
                        _IconBtn(
                          icon: Icons.close_rounded,
                          tooltip: '열 삭제',
                          color: c.textMuted,
                          onTap: _columns > 1 ? () => _removeColumn(col) : null,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 28),
              ],
            ),
            const SizedBox(height: 4),
            for (var r = 0; r < _cells.length; r++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    for (var col = 0; col < _columns; col++)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: SizedBox(
                          width: _cellWidth - 6,
                          child: TextField(
                            controller: _cells[r][col],
                            style: (r == 0
                                    ? AppTextStyles.captionSemibold
                                    : AppTextStyles.caption)
                                .copyWith(color: c.textPrimary),
                            textAlign: switch (_aligns[col]) {
                              MarkdownTableAlign.left => TextAlign.left,
                              MarkdownTableAlign.center => TextAlign.center,
                              MarkdownTableAlign.right => TextAlign.right,
                            },
                            decoration: InputDecoration(
                              isDense: true,
                              filled: true,
                              fillColor: r == 0 ? c.surfaceLight : c.surface,
                              hintText: r == 0 ? 'Header' : null,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                    AppDimensions.radiusMicro),
                                borderSide: BorderSide(color: c.border),
                              ),
                            ),
                          ),
                        ),
                      ),
                    SizedBox(
                      width: 28,
                      child: _IconBtn(
                        icon: Icons.close_rounded,
                        tooltip: '행 삭제',
                        color: c.textMuted,
                        // The header row and the last body row can't be removed.
                        onTap: (r != 0 && _cells.length > 2)
                            ? () => _removeRow(r)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 16),
      tooltip: tooltip,
      color: color,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
      onPressed: onTap,
    );
  }
}

class _GridButton extends StatelessWidget {
  const _GridButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: c.textPrimary,
        side: BorderSide(color: c.border),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: AppTextStyles.captionMedium,
        minimumSize: const Size(0, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
