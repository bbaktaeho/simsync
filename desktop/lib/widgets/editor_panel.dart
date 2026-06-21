import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/note.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';
import '../services/markdown_editing.dart';
import 'editor_block_decorations.dart';
import 'inline_table_view.dart';
import 'markdown_editing_controller.dart';
import 'table_editor_dialog.dart';

/// Auto-save debounce duration.
const _autoSaveDelay = Duration(seconds: 1);

class EditorPanel extends StatefulWidget {
  final Note? note;
  final ValueChanged<Note>? onNoteChanged;
  final DateTime? selectedDate;
  final VoidCallback? onCreateNote;
  final VoidCallback? onCreateLocalNote;
  final bool isReadOnly;
  final String? readOnlyReason;
  final double contentScale;
  final Future<void> Function()? onIncreaseContentScale;
  final Future<void> Function()? onDecreaseContentScale;
  final Future<void> Function(double value)? onSetContentScale;

  const EditorPanel({
    super.key,
    this.note,
    this.onNoteChanged,
    this.selectedDate,
    this.onCreateNote,
    this.onCreateLocalNote,
    this.isReadOnly = false,
    this.readOnlyReason,
    this.contentScale = 1.0,
    this.onIncreaseContentScale,
    this.onDecreaseContentScale,
    this.onSetContentScale,
  });

  @override
  State<EditorPanel> createState() => _EditorPanelState();
}

class _EditorPanelState extends State<EditorPanel> {
  late TextEditingController _titleController;
  late MarkdownEditingController _contentController;
  late TextEditingController _tagController;
  late FocusNode _contentFocusNode;
  late ScrollController _contentScrollController;
  Timer? _autoSaveTimer;
  DateTime? _lastSaved;
  String? _loadedNoteId;
  double _panZoomBaseScale = 1.0;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _contentController = MarkdownEditingController();
    _tagController = TextEditingController();
    _contentFocusNode = FocusNode()..addListener(_onContentFocusChanged);
    _contentScrollController = ScrollController();
    _syncControllers();
  }

  /// When the editor gains/loses focus, the controller re-renders so the caret's
  /// line reveals its markdown markers (focused) or everything renders (blurred).
  void _onContentFocusChanged() {
    if (!mounted) return;
    setState(() => _contentController.focused = _contentFocusNode.hasFocus);
  }

  @override
  void didUpdateWidget(EditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.note?.id != _loadedNoteId) {
      // Flush any pending edit for the previous note before swapping the
      // controllers — otherwise the edited text only ever lived in the
      // controllers and would be discarded by `_syncControllers`.
      final previousNote = oldWidget.note;
      if (previousNote != null) {
        _flushPending(previousNote);
      }
      _syncControllers();
    }
  }

  void _syncControllers() {
    final note = widget.note;
    _loadedNoteId = note?.id;
    _titleController.text = note?.title ?? '';
    _contentController.text = note?.content ?? '';
    _tagController.clear();
    _lastSaved = note?.updatedAt;
  }

  /// Flushes the current controller text into [note] via [onNoteChanged] if
  /// the note has unsaved edits. Cancels the pending auto-save timer to avoid
  /// it firing later against a stale note reference.
  ///
  /// The captured text is snapshotted synchronously (before the controllers are
  /// re-synced to the next note), but the parent callback is invoked after the
  /// frame: [didUpdateWidget] runs mid-build when the note prop changes (e.g.
  /// switching or closing a tab), so calling the parent's setState synchronously
  /// here would throw "setState() called during build".
  void _flushPending(Note note) {
    if (widget.isReadOnly || !note.isDirty) return;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    final callback = widget.onNoteChanged;
    if (callback == null) return;
    final updated = note.copyWith(
      title: _titleController.text,
      content: _contentController.text,
      updatedAt: DateTime.now(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => callback(updated));
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    final note = widget.note;
    if (note != null && note.isDirty && !widget.isReadOnly) {
      // Last-chance flush before controllers are torn down.
      final updated = note.copyWith(
        title: _titleController.text,
        content: _contentController.text,
        updatedAt: DateTime.now(),
      );
      widget.onNoteChanged?.call(updated);
    }
    _titleController.dispose();
    _contentController.dispose();
    _tagController.dispose();
    _contentFocusNode.dispose();
    _contentScrollController.dispose();
    super.dispose();
  }

  void _onContentChanged() {
    if (widget.isReadOnly) return;
    widget.note?.isDirty = true;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(_autoSaveDelay, _save);
  }

  void _save() {
    final note = widget.note;
    if (note == null || widget.isReadOnly) return;
    // Guard against a stale timer firing after the user switched notes.
    if (note.id != _loadedNoteId) return;
    final now = DateTime.now();
    final updated = note.copyWith(
      title: _titleController.text,
      content: _contentController.text,
      updatedAt: now,
    );
    widget.onNoteChanged?.call(updated);
    setState(() => _lastSaved = now);
  }

  void _addTag() {
    if (widget.isReadOnly) return;
    final tag = _tagController.text.trim();
    if (tag.isEmpty || widget.note == null) return;
    if (!widget.note!.tags.contains(tag)) {
      setState(() => widget.note!.tags.add(tag));
      _tagController.clear();
      _save();
    }
  }

  void _removeTag(String tag) {
    if (widget.note == null || widget.isReadOnly) return;
    setState(() => widget.note!.tags.remove(tag));
    _save();
  }

  void _renumberList() {
    if (widget.isReadOnly || widget.note == null) return;
    final updated = renumberOrderedListAtCursor(_contentController.value);
    if (updated.text == _contentController.text) return;
    _contentController.value = updated;
    _onContentChanged();
  }

  /// Inserts [block] at the cursor, ensuring it starts on its own line and is
  /// followed by a trailing newline.
  void _insertBlock(String block) {
    if (widget.isReadOnly || widget.note == null) return;
    final text = _contentController.text;
    final selection = _contentController.selection;
    final start = (selection.isValid ? selection.baseOffset : text.length)
        .clamp(0, text.length);
    final needsLeadingNewline = start > 0 && text[start - 1] != '\n';
    final insertion = '${needsLeadingNewline ? '\n' : ''}$block\n';
    final newText = text.replaceRange(start, start, insertion);
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + insertion.length),
    );
    _onContentChanged();
  }

  /// Opens the table grid editor. If the caret is inside an existing table it
  /// edits that table in-place; otherwise it inserts a new one. Either way the
  /// user fills cells in a real grid instead of typing pipe syntax.
  Future<void> _insertTable() async {
    if (widget.isReadOnly || widget.note == null) return;
    final selection = _contentController.selection;
    final offset = selection.isValid ? selection.baseOffset : -1;
    final found =
        offset >= 0 ? tableAtOffset(_contentController.text, offset) : null;
    if (found != null) {
      await _editTableAt(found);
      return;
    }
    final markdown = await TableEditorDialog.show(context, initial: null);
    if (markdown == null || !mounted) return;
    _insertBlock(markdown);
  }

  Future<void> _editTableAt(
      ({MarkdownTableData table, int start, int end}) found) async {
    if (widget.isReadOnly || widget.note == null) return;
    final markdown =
        await TableEditorDialog.show(context, initial: found.table);
    if (markdown == null || !mounted) return;
    _replaceRange(found.start, found.end, markdown);
  }

  // Tapping a rendered table moves the caret into it, which marks it active and
  // reveals the +col/+row controls (the table widget hides its raw markdown).
  void _activateTable(TableRegion table) {
    if (widget.isReadOnly) return;
    _contentFocusNode.requestFocus();
    _contentController.selection =
        TextSelection.collapsed(offset: table.start.clamp(0, _contentController.text.length));
  }

  void _addTableRow(TableRegion table) {
    final data = table.table;
    _mutateTable(
      table,
      MarkdownTableData(
        [...data.rows, List.filled(data.columns, '')],
        data.aligns,
      ),
    );
  }

  void _addTableColumn(TableRegion table) {
    final data = table.table;
    _mutateTable(
      table,
      MarkdownTableData(
        [for (final row in data.rows) [...row, '']],
        [...data.aligns, MarkdownTableAlign.left],
      ),
    );
  }

  // Removes one body row. The header row (index 0) is kept so the table stays a
  // valid markdown table even after all data rows are gone.
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

  // Removes one column from every row (and its alignment). Keeps at least one
  // column; use the X control to remove the table entirely.
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

  // Writes one cell's text in place (inline cell editing) and re-serializes the
  // table. Keeps the table active so the caret/controls stay put while typing.
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

  // Replaces the table's markdown in place and keeps the caret inside it so it
  // stays active (the +col/+row controls remain visible after the change).
  void _mutateTable(TableRegion table, MarkdownTableData next) {
    if (widget.isReadOnly || widget.note == null) return;
    final text = _contentController.text;
    final s = table.start.clamp(0, text.length);
    final e = table.end.clamp(s, text.length);
    _contentController.value = TextEditingValue(
      text: text.replaceRange(s, e, serializeMarkdownTable(next)),
      selection: TextSelection.collapsed(offset: s),
    );
    _onContentChanged();
  }

  // Removes the whole table (the X control). Also drops the table's trailing
  // newline so no blank line is left where it was. Undoable via the editor.
  void _removeTable(TableRegion table) {
    if (widget.isReadOnly || widget.note == null) return;
    final text = _contentController.text;
    final s = table.start.clamp(0, text.length);
    var e = table.end.clamp(s, text.length);
    if (e < text.length && text[e] == '\n') e++;
    _contentController.value = TextEditingValue(
      text: text.replaceRange(s, e, ''),
      selection: TextSelection.collapsed(offset: s),
    );
    _onContentChanged();
  }

  void _replaceRange(int start, int end, String replacement) {
    final text = _contentController.text;
    final s = start.clamp(0, text.length);
    final e = end.clamp(s, text.length);
    _contentController.value = TextEditingValue(
      text: text.replaceRange(s, e, replacement),
      selection: TextSelection.collapsed(offset: s + replacement.length),
    );
    _onContentChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.note == null) {
      return _buildEmptyState(context);
    }

    final c = context.colors;

    return Column(
      children: [
        _buildToolbar(c),
        Divider(height: 1, color: c.border),
        _buildMetaHeader(c),
        Divider(height: 1, color: c.border),
        Expanded(child: _buildEditor(c)),
        _buildStatusBar(c),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final c = context.colors;
    final hasDate = widget.selectedDate != null;
    final dateLabel = hasDate
        ? DateFormat('yyyy. M. d. (E)').format(widget.selectedDate!)
        : null;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasDate ? Icons.note_add_outlined : Icons.edit_document,
            size: 48,
            color: c.textMuted,
          ),
          const SizedBox(height: AppDimensions.spacingLg),
          if (hasDate) ...[
            Text(
              dateLabel!,
              style: Theme.of(context).textTheme.titleSmall!.copyWith(fontWeight: FontWeight.w600, color: c.textSecondary),
            ),
            const SizedBox(height: AppDimensions.spacingSm),
            Text(
              'No notes for this date',
              style: AppTextStyles.caption.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: AppDimensions.spacingXl),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CreateNoteButton(
                  label: '동기화 노트',
                  icon: Icons.cloud_outlined,
                  onTap: widget.onCreateNote,
                ),
                if (widget.onCreateLocalNote != null) ...[
                  const SizedBox(width: AppDimensions.spacingSm),
                  _CreateNoteButton(
                    label: '로컬 노트',
                    icon: Icons.folder_outlined,
                    useLocalAccent: true,
                    onTap: widget.onCreateLocalNote,
                  ),
                ],
              ],
            ),
          ] else ...[
            Text(
              'Select a note to start editing',
              style: Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w400, color: c.textMuted),
            ),
            const SizedBox(height: AppDimensions.spacingSm),
            Text(
              'or create a new one from the sidebar',
              style: AppTextStyles.caption.copyWith(color: c.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToolbar(AppColorsExtension c) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingLg),
      color: c.surface,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _titleController,
              onChanged: widget.isReadOnly ? null : (_) => _onContentChanged(),
              readOnly: widget.isReadOnly,
              style: Theme.of(context).textTheme.labelLarge!.copyWith(color: c.textPrimary),
              decoration: InputDecoration(
                hintText: 'Untitled',
                hintStyle: Theme.of(context).textTheme.labelLarge!.copyWith(color: c.textMuted),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: AppDimensions.spacingMd),
          if (!widget.isReadOnly) ...[
            _ToolbarIconButton(
              icon: Icons.format_bold_rounded,
              tooltip: 'Bold',
              onTap: () => _wrapSelection('**'),
            ),
            const SizedBox(width: AppDimensions.spacingXs),
            _ToolbarIconButton(
              icon: Icons.format_italic_rounded,
              tooltip: 'Italic',
              onTap: () => _wrapSelection('*'),
            ),
            const SizedBox(width: AppDimensions.spacingXs),
            _ToolbarIconButton(
              icon: Icons.title_rounded,
              tooltip: 'Heading',
              onTap: () => _toggleLinePrefix('# '),
            ),
            const SizedBox(width: AppDimensions.spacingXs),
            _ToolbarIconButton(
              icon: Icons.format_list_bulleted_rounded,
              tooltip: 'Bullet list',
              onTap: () => _toggleLinePrefix('- '),
            ),
            const SizedBox(width: AppDimensions.spacingXs),
            _ToolbarIconButton(
              icon: Icons.checklist_rounded,
              tooltip: 'Checklist',
              onTap: () => _toggleLinePrefix('- [ ] '),
            ),
            const SizedBox(width: AppDimensions.spacingMd),
            _ToolbarIconButton(
              icon: Icons.table_chart_outlined,
              tooltip: '표 삽입 / 편집',
              onTap: () => unawaited(_insertTable()),
            ),
            const SizedBox(width: AppDimensions.spacingXs),
            _ToolbarIconButton(
              icon: Icons.format_list_numbered_rounded,
              tooltip: 'Renumber list',
              onTap: _renumberList,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetaHeader(AppColorsExtension c) {
    final note = widget.note!;
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(note.updatedAt);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingLg,
        vertical: AppDimensions.spacingSm,
      ),
      color: c.surface,
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ...note.tags.map(
                  (tag) => _EditorTagChip(
                    label: tag,
                    onRemove: widget.isReadOnly ? null : () => _removeTag(tag),
                  ),
                ),
                SizedBox(
                  width: 80,
                  height: 22,
                  child: TextField(
                    controller: _tagController,
                    readOnly: widget.isReadOnly,
                    style: AppTextStyles.micro.copyWith(color: c.textSecondary),
                    decoration: InputDecoration(
                      hintText: '+ tag',
                      hintStyle: AppTextStyles.micro.copyWith(color: c.textMuted),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                    onSubmitted: widget.isReadOnly ? null : (_) => _addTag(),
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.update_rounded, size: 12, color: c.textMuted),
              const SizedBox(width: AppDimensions.spacingXs),
              Text(
                dateStr,
                style: AppTextStyles.micro.copyWith(color: c.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEditor(AppColorsExtension c) {
    // The controller renders markdown styling inline as you type (Notion /
    // Obsidian style) — there is no separate preview pane.
    _contentController.scale = widget.contentScale;
    final bodyStyle =
        AppTextStyles.mdBody(widget.contentScale).copyWith(color: c.textPrimary);
    // The decoration painter lays out an identical TextPainter, so the field and
    // the painter must share strut + text scaler + width for the boxes to align.
    // The strut mirrors the body style so the caret lines up with the text.
    final strut = StrutStyle.fromTextStyle(bodyStyle, forceStrutHeight: false);
    final textScaler = MediaQuery.textScalerOf(context);

    final field = TextField(
      controller: _contentController,
      focusNode: _contentFocusNode,
      scrollController: _contentScrollController,
      onChanged: widget.isReadOnly ? null : (_) => _onContentChanged(),
      readOnly: widget.isReadOnly,
      inputFormatters:
          widget.isReadOnly ? null : [MarkdownListInputFormatter()],
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      cursorColor: c.accent,
      style: bodyStyle,
      strutStyle: strut,
      decoration: InputDecoration(
        hintText: 'Start writing in markdown...',
        hintStyle: bodyStyle.copyWith(color: c.textMuted),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        contentPadding: EdgeInsets.zero,
      ),
    );

    final Widget body = Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            // Rebuild the decoration layer on every text/caret change so code
            // boxes (and `---` rules / quote bars) grow and shrink with the
            // content as you type — the rest of the editor does not rebuild.
            child: ListenableBuilder(
              listenable: _contentController,
              builder: (context, _) {
                final allRegions =
                    parseEditorBlockRegions(_contentController.text);
                final tables = findTableRegions(_contentController.text);
                // A pipe-less `---` table separator also matches the `---` rule;
                // drop that rule so it is not drawn as a line inside the table.
                final sepStarts = {for (final t in tables) t.separatorRange.start};
                final regions = sepStarts.isEmpty
                    ? allRegions
                    : allRegions
                        .where((r) => !(r.kind == EditorBlockKind.rule &&
                            sepStarts.contains(r.start)))
                        .toList();
                if (regions.isEmpty) {
                  return const SizedBox.expand();
                }
                return CustomPaint(
                  painter: EditorBlockDecorationPainter(
                    span: _contentController.buildTextSpan(
                      context: context,
                      withComposing: false,
                    ),
                    regions: regions,
                    strutStyle: strut,
                    textScaler: textScaler,
                    scrollController: _contentScrollController,
                    codeBackground: c.surfaceLight,
                    codeBorder: c.border,
                    ruleColor: c.border,
                    quoteBar: c.textMuted,
                  ),
                );
              },
            ),
          ),
        ),
        field,
        // Tables render as real, scrollable widgets over their hidden markdown,
        // on top of the field so they can take taps and show the +col/+row
        // controls when the caret is inside them.
        Positioned.fill(
          child: _buildTableOverlays(c, bodyStyle, strut, textScaler),
        ),
      ],
    );

    return _buildZoomAwareSurface(
      Container(
        color: c.scaffold,
        padding: const EdgeInsets.all(AppDimensions.spacingLg),
        child: body,
      ),
    );
  }

  // Positions an [InlineTableView] over each table's hidden markdown. It rebuilds
  // on every text/caret/scroll change so the overlays follow the content; the
  // table containing the caret renders active (with the +col/+row controls).
  Widget _buildTableOverlays(
    AppColorsExtension c,
    TextStyle bodyStyle,
    StrutStyle strut,
    TextScaler textScaler,
  ) {
    return ListenableBuilder(
      listenable: Listenable.merge([_contentController, _contentScrollController]),
      builder: (context, _) {
        final tables = findTableRegions(_contentController.text);
        if (tables.isEmpty) return const SizedBox.shrink();
        return LayoutBuilder(
          builder: (context, constraints) {
            final span = _contentController.buildTextSpan(
                context: context, withComposing: false);
            final measured = measureTableRegions(
                span, tables, strut, textScaler, constraints.maxWidth);
            final scrollY = _contentScrollController.hasClients
                ? _contentScrollController.offset
                : 0.0;
            final sel = _contentController.selection;
            final caret = sel.isValid ? sel.baseOffset : -1;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                for (final m in measured)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: m.top - scrollY,
                    height: m.bottom - m.top,
                    child: InlineTableView(
                      key: ValueKey(m.table.start),
                      data: m.table.table,
                      active: !widget.isReadOnly &&
                          caret >= m.table.start &&
                          caret <= m.table.end,
                      cellStyle: bodyStyle,
                      onActivate: () => _activateTable(m.table),
                      onAddRow: () => _addTableRow(m.table),
                      onAddColumn: () => _addTableColumn(m.table),
                      onRemove: () => _removeTable(m.table),
                      onCellChanged: (row, col, value) =>
                          _setTableCell(m.table, row, col, value),
                      onRemoveRow: (row) => _removeTableRow(m.table, row),
                      onRemoveColumn: (col) =>
                          _removeTableColumn(m.table, col),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  static final RegExp _leadingIndent = RegExp(r'^[ \t]*');
  static final List<RegExp> _blockPrefixes = [
    RegExp(r'^#{1,6} '), // heading
    RegExp(r'^[-*+] \[[ xX]\] '), // checkbox (before bullet)
    RegExp(r'^[-*+] '), // bullet
    RegExp(r'^\d+[.)] '), // ordered
    RegExp(r'^> '), // quote
  ];

  /// Length of any recognized block prefix at the start of [body] (no indent),
  /// or 0 when the line has no block marker.
  int _blockPrefixLength(String body) {
    for (final pattern in _blockPrefixes) {
      final match = pattern.firstMatch(body);
      if (match != null) return match.end;
    }
    return 0;
  }

  /// Toggles inline [marker] (e.g. `**` for bold) on the selection. An empty
  /// selection inserts the markers with the cursor between them; a selection
  /// already wrapped in [marker] is un-wrapped.
  void _wrapSelection(String marker) {
    if (widget.isReadOnly) return;
    final value = _contentController.value;
    final text = value.text;
    final selection = value.selection;
    if (!selection.isValid) return;
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(0, text.length);
    final selected = text.substring(start, end);

    // Un-wrap if the selection is already exactly wrapped.
    if (selected.length >= marker.length * 2 &&
        selected.startsWith(marker) &&
        selected.endsWith(marker)) {
      final inner =
          selected.substring(marker.length, selected.length - marker.length);
      _contentController.value = TextEditingValue(
        text: text.replaceRange(start, end, inner),
        selection:
            TextSelection(baseOffset: start, extentOffset: start + inner.length),
      );
      _onContentChanged();
      return;
    }

    _contentController.value = TextEditingValue(
      text: text.replaceRange(start, end, '$marker$selected$marker'),
      selection: selected.isEmpty
          ? TextSelection.collapsed(offset: start + marker.length)
          : TextSelection(
              baseOffset: start + marker.length,
              extentOffset: end + marker.length,
            ),
    );
    _onContentChanged();
  }

  /// Toggles a line-level [prefix] (`# `, `- `, `- [ ] `) on the caret's line.
  /// Setting a new block type replaces any existing one (Notion/Obsidian style)
  /// rather than stacking; pressing the same type again clears it. Leading
  /// indentation is preserved.
  void _toggleLinePrefix(String prefix) {
    if (widget.isReadOnly) return;
    final value = _contentController.value;
    final text = value.text;
    final selection = value.selection;
    final caret =
        (selection.isValid ? selection.baseOffset : text.length).clamp(0, text.length);
    final lineStart = caret == 0 ? 0 : text.lastIndexOf('\n', caret - 1) + 1;
    var lineEnd = text.indexOf('\n', caret);
    if (lineEnd == -1) lineEnd = text.length;
    final line = text.substring(lineStart, lineEnd);

    final indent = _leadingIndent.firstMatch(line)!.group(0)!;
    final body = line.substring(indent.length);
    final existingLen = _blockPrefixLength(body);
    final content = body.substring(existingLen);
    // Toggle off only when the existing block prefix is exactly this one;
    // otherwise replace it (e.g. checkbox -> bullet, not strip to plain).
    final toggleOff = body.substring(0, existingLen) == prefix;
    final newPrefixLen = toggleOff ? 0 : prefix.length;
    final newBody = toggleOff ? content : '$prefix$content';
    final newLine = '$indent$newBody';

    final caretInLine = caret - lineStart;
    final contentStart = indent.length + existingLen;
    final newContentStart = indent.length + newPrefixLen;
    final newCaretInLine = caretInLine <= contentStart
        ? newContentStart
        : caretInLine - contentStart + newContentStart;

    final newText = text.replaceRange(lineStart, lineEnd, newLine);
    final newCaret =
        (lineStart + newCaretInLine).clamp(lineStart, lineStart + newLine.length);
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCaret),
    );
    _onContentChanged();
  }

  Widget _buildZoomAwareSurface(Widget child) {
    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent ||
            !HardwareKeyboard.instance.isMetaPressed) {
          return;
        }

        if (event.scrollDelta.dy < 0) {
          unawaited(widget.onIncreaseContentScale?.call());
        } else if (event.scrollDelta.dy > 0) {
          unawaited(widget.onDecreaseContentScale?.call());
        }
      },
      onPointerPanZoomStart: (_) {
        _panZoomBaseScale = widget.contentScale;
      },
      onPointerPanZoomUpdate: (event) {
        unawaited(
          widget.onSetContentScale?.call(_panZoomBaseScale * event.scale),
        );
      },
      child: child,
    );
  }

  Widget _buildStatusBar(AppColorsExtension c) {
    final savedText = _lastSaved != null
        ? 'Saved at ${DateFormat('HH:mm:ss').format(_lastSaved!)}'
        : '';

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingLg),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          if (widget.isReadOnly && widget.readOnlyReason != null) ...[
            Icon(Icons.lock_outline_rounded, size: 12, color: c.textMuted),
            const SizedBox(width: AppDimensions.spacingXs),
            Expanded(
              child: Text(
                widget.readOnlyReason!,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.micro.copyWith(color: c.textMuted),
              ),
            ),
            const SizedBox(width: AppDimensions.spacingMd),
          ],
          if (savedText.isNotEmpty) ...[
            Icon(
              Icons.check_circle_outline_rounded,
              size: 12,
              color: c.success,
            ),
            const SizedBox(width: AppDimensions.spacingXs),
            Text(
              savedText,
              style: AppTextStyles.micro.copyWith(color: c.textMuted),
            ),
          ],
          const Spacer(),
          Text(
            'Markdown ${(widget.contentScale * 100).round()}%',
            style: AppTextStyles.micro.copyWith(color: c.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Compact hover icon button used for editor toolbar actions.
class _ToolbarIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_ToolbarIconButton> createState() => _ToolbarIconButtonState();
}

class _ToolbarIconButtonState extends State<_ToolbarIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AppDimensions.animFast,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _isHovered ? c.surfaceHover : c.surfaceLight,
              borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
              border: Border.all(color: c.border),
            ),
            child: Icon(widget.icon, size: 16, color: c.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _CreateNoteButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool useLocalAccent;
  final VoidCallback? onTap;

  const _CreateNoteButton({
    required this.label,
    required this.icon,
    this.useLocalAccent = false,
    this.onTap,
  });

  @override
  State<_CreateNoteButton> createState() => _CreateNoteButtonState();
}

class _CreateNoteButtonState extends State<_CreateNoteButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accentColor = widget.useLocalAccent ? c.localAccent : c.accent;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingLg,
            vertical: AppDimensions.spacingSm,
          ),
          decoration: BoxDecoration(
            color: _isHovered ? c.surfaceHover : c.surfaceLight,
            borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
            border: Border.all(
              color: _isHovered ? accentColor.withValues(alpha: 0.3) : c.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: _isHovered ? accentColor : c.textSecondary,
              ),
              const SizedBox(width: AppDimensions.spacingSm),
              Text(
                widget.label,
                style: Theme.of(context).textTheme.labelSmall!.copyWith(fontWeight: FontWeight.w500, color: _isHovered ? accentColor : c.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorTagChip extends StatelessWidget {
  final String label;
  final VoidCallback? onRemove;

  const _EditorTagChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      padding: const EdgeInsets.only(left: AppDimensions.spacingSm, right: 2, top: 2, bottom: 2),
      decoration: BoxDecoration(
        color: c.accentSubtle,
        borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
        border: Border.all(color: c.accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTextStyles.microMedium.copyWith(color: c.accent),
          ),
          if (onRemove != null)
            GestureDetector(
              onTap: onRemove,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  Icons.close_rounded,
                  size: 12,
                  color: c.accent.withValues(alpha: 0.6),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
