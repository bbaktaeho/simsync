import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../services/markdown_editing.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';

/// A spreadsheet-style editor for markdown tables built on PlutoGrid: you edit
/// cells with keyboard navigation (Tab/arrows) instead of typing pipe syntax.
/// Row 0 is the (tinted) header. Returns the serialized GFM markdown on save, or
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
  late List<List<String>> _data; // [row][col]; row 0 = header
  late List<MarkdownTableAlign> _aligns;
  PlutoGridStateManager? _sm;
  int _gridVersion = 0; // bumped to rebuild the grid on structure changes

  int get _columns => _aligns.length;

  @override
  void initState() {
    super.initState();
    final data = widget.initial ?? MarkdownTableData.blank();
    _aligns = List.of(data.aligns);
    _data = [
      for (final row in data.rows)
        [for (var i = 0; i < data.columns; i++) i < row.length ? row[i] : ''],
    ];
  }

  // Pull the grid's current (committed) cell values back into [_data]. Called
  // before any structure change and on save so edits aren't lost on rebuild.
  void _syncFromGrid() {
    final sm = _sm;
    if (sm == null) return;
    // A live editing cell commits its TextField to cell.value only on
    // Enter/Tab/blur — NOT synchronously on setEditing(false). So copy the
    // editing controller's text into the cell ourselves, or a mouse-driven
    // Save/toolbar click would silently drop the in-progress edit.
    if (sm.isEditing && sm.currentCell != null) {
      final text = sm.textEditingController?.text;
      if (text != null) {
        sm.changeCellValue(sm.currentCell!, text,
            callOnChangedEvent: false, notify: false);
      }
    }
    sm.setEditing(false);
    for (var r = 0; r < _data.length && r < sm.refRows.length; r++) {
      for (var col = 0; col < _columns; col++) {
        final v = sm.refRows[r].cells['c$col']?.value;
        if (v != null) _data[r][col] = v.toString();
      }
    }
  }

  int _currentColumn() {
    final field = _sm?.currentColumn?.field;
    final idx = field == null ? null : int.tryParse(field.substring(1));
    return (idx ?? _columns - 1).clamp(0, _columns - 1);
  }

  int _currentRow() {
    final idx = _sm?.currentRowIdx;
    return (idx ?? _data.length - 1).clamp(0, _data.length - 1);
  }

  void _mutate(VoidCallback change) {
    _syncFromGrid();
    setState(() {
      change();
      _gridVersion++; // force PlutoGrid to rebuild from the new _data/_aligns
    });
  }

  void _addRow() => _mutate(() => _data.add(List.filled(_columns, '')));

  void _addColumn() => _mutate(() {
        for (final row in _data) {
          row.add('');
        }
        _aligns.add(MarkdownTableAlign.left);
      });

  void _deleteRow() {
    if (_data.length <= 2) return; // keep the header + at least one body row
    final idx = _currentRow();
    if (idx == 0) return; // never delete the header
    _mutate(() => _data.removeAt(idx));
  }

  void _deleteColumn() {
    if (_columns <= 1) return;
    final idx = _currentColumn();
    _mutate(() {
      for (final row in _data) {
        if (idx < row.length) row.removeAt(idx);
      }
      _aligns.removeAt(idx);
    });
  }

  void _cycleAlign() {
    final idx = _currentColumn();
    _mutate(() {
      const order = MarkdownTableAlign.values;
      _aligns[idx] = order[(_aligns[idx].index + 1) % order.length];
    });
  }

  void _save() {
    _syncFromGrid();
    Navigator.pop(
      context,
      serializeMarkdownTable(MarkdownTableData(_data, _aligns)),
    );
  }

  PlutoColumnTextAlign _plutoAlign(MarkdownTableAlign a) => switch (a) {
        MarkdownTableAlign.left => PlutoColumnTextAlign.left,
        MarkdownTableAlign.center => PlutoColumnTextAlign.center,
        MarkdownTableAlign.right => PlutoColumnTextAlign.right,
      };

  IconData _alignIcon(MarkdownTableAlign a) => switch (a) {
        MarkdownTableAlign.left => Icons.format_align_left_rounded,
        MarkdownTableAlign.center => Icons.format_align_center_rounded,
        MarkdownTableAlign.right => Icons.format_align_right_rounded,
      };

  List<PlutoColumn> _buildColumns() => [
        for (var i = 0; i < _columns; i++)
          PlutoColumn(
            title: '열 ${i + 1}',
            field: 'c$i',
            type: PlutoColumnType.text(),
            textAlign: _plutoAlign(_aligns[i]),
            enableEditingMode: true,
            enableContextMenu: false,
            enableColumnDrag: false,
            enableSorting: false,
            enableDropToResize: true,
            width: 150,
            minWidth: 80,
          ),
      ];

  List<PlutoRow> _buildRows() => [
        for (final row in _data)
          PlutoRow(
            cells: {
              for (var i = 0; i < _columns; i++)
                'c$i': PlutoCell(value: i < row.length ? row[i] : ''),
            },
          ),
      ];

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
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 580),
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
                  const Spacer(),
                  Text(
                    '첫 행이 헤더입니다 · Tab/방향키로 이동',
                    style: AppTextStyles.micro.copyWith(color: c.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.spacingMd),
              _buildToolbar(c),
              const SizedBox(height: AppDimensions.spacingSm),
              SizedBox(
                width: 680,
                height: 320,
                child: PlutoGrid(
                  key: ValueKey(_gridVersion),
                  columns: _buildColumns(),
                  rows: _buildRows(),
                  onLoaded: (e) {
                    _sm = e.stateManager;
                    _sm!.setSelectingMode(PlutoGridSelectingMode.cell);
                  },
                  onChanged: (e) {
                    final col = int.tryParse(e.column.field.substring(1));
                    if (col != null && e.rowIdx < _data.length) {
                      _data[e.rowIdx][col] = e.value?.toString() ?? '';
                    }
                  },
                  rowColorCallback: (ctx) =>
                      ctx.rowIdx == 0 ? c.accentSubtle : c.surface,
                  configuration: PlutoGridConfiguration(
                    style: PlutoGridStyleConfig(
                      gridBackgroundColor: c.surface,
                      rowColor: c.surface,
                      borderColor: c.border,
                      gridBorderColor: c.border,
                      activatedColor: c.accentSubtle,
                      cellTextStyle:
                          AppTextStyles.caption.copyWith(color: c.textPrimary),
                      columnTextStyle: AppTextStyles.captionMedium
                          .copyWith(color: c.textSecondary),
                      iconColor: c.textMuted,
                      rowHeight: 38,
                      columnHeight: 38,
                      gridBorderRadius:
                          BorderRadius.circular(AppDimensions.radiusStandard),
                      enableGridBorderShadow: false,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppDimensions.spacingLg),
              Row(
                children: [
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

  Widget _buildToolbar(AppColorsExtension c) {
    final currentAlign = _aligns[_currentColumn().clamp(0, _columns - 1)];
    return Wrap(
      spacing: AppDimensions.spacingSm,
      runSpacing: AppDimensions.spacingSm,
      children: [
        _ToolBtn(icon: Icons.add_rounded, label: '행', onTap: _addRow),
        _ToolBtn(icon: Icons.add_rounded, label: '열', onTap: _addColumn),
        _ToolBtn(
          icon: Icons.remove_rounded,
          label: '행 삭제',
          onTap: _data.length > 2 ? _deleteRow : null,
        ),
        _ToolBtn(
          icon: Icons.remove_rounded,
          label: '열 삭제',
          onTap: _columns > 1 ? _deleteColumn : null,
        ),
        _ToolBtn(
          icon: _alignIcon(currentAlign),
          label: '정렬',
          onTap: _cycleAlign,
        ),
      ],
    );
  }
}

class _ToolBtn extends StatelessWidget {
  const _ToolBtn({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15),
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
