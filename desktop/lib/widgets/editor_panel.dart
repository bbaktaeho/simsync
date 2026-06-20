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
import 'markdown_preview.dart';

/// Auto-save debounce duration.
const _autoSaveDelay = Duration(seconds: 1);

/// Editor display mode: edit only, side-by-side split, or preview only.
enum EditorViewMode { edit, split, preview }

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

  /// Whether the side-by-side split view is permitted. Disabled when the
  /// surrounding layout is already space-constrained (e.g. the search results
  /// panel is showing), in which case split falls back to edit.
  final bool allowSplit;

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
    this.allowSplit = true,
  });

  @override
  State<EditorPanel> createState() => _EditorPanelState();
}

class _EditorPanelState extends State<EditorPanel> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late TextEditingController _tagController;
  EditorViewMode _viewMode = EditorViewMode.split;
  Timer? _autoSaveTimer;
  DateTime? _lastSaved;
  String? _loadedNoteId;
  double _panZoomBaseScale = 1.0;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _contentController = TextEditingController();
    _tagController = TextEditingController();
    _syncControllers();
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

  Future<void> _insertTable() async {
    if (widget.isReadOnly || widget.note == null) return;
    final spec = await showDialog<_TableSpec>(
      context: context,
      builder: (_) => const _InsertTableDialog(),
    );
    if (spec == null) return;
    _insertBlock(buildMarkdownTable(columns: spec.columns, rows: spec.rows));
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
        Expanded(child: _buildBody(c)),
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
              icon: Icons.table_chart_outlined,
              tooltip: 'Insert table',
              onTap: () => unawaited(_insertTable()),
            ),
            const SizedBox(width: AppDimensions.spacingXs),
            _ToolbarIconButton(
              icon: Icons.format_list_numbered_rounded,
              tooltip: 'Renumber list',
              onTap: _renumberList,
            ),
            const SizedBox(width: AppDimensions.spacingMd),
          ],
          _ViewModeControl(
            mode: _effectiveViewMode,
            allowSplit: widget.allowSplit,
            onChanged: (mode) => setState(() => _viewMode = mode),
          ),
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
    return _buildZoomAwareSurface(
      Container(
        color: c.scaffold,
        padding: const EdgeInsets.all(AppDimensions.spacingLg),
        child: TextField(
          controller: _contentController,
          onChanged: widget.isReadOnly ? null : (_) => _onContentChanged(),
          readOnly: widget.isReadOnly,
          inputFormatters:
              widget.isReadOnly ? null : [MarkdownListInputFormatter()],
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: AppTextStyles.codeMonoBody(widget.contentScale).copyWith(color: c.textPrimary),
          decoration: InputDecoration(
            hintText: 'Start writing in markdown...',
            hintStyle: AppTextStyles.codeMonoBody(widget.contentScale).copyWith(color: c.textMuted),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }

  EditorViewMode get _effectiveViewMode {
    if (_viewMode == EditorViewMode.split && !widget.allowSplit) {
      return EditorViewMode.edit;
    }
    return _viewMode;
  }

  Widget _buildBody(AppColorsExtension c) {
    switch (_effectiveViewMode) {
      case EditorViewMode.edit:
        return _buildEditor(c);
      case EditorViewMode.preview:
        return _buildLivePreview(c);
      case EditorViewMode.split:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildEditor(c)),
            VerticalDivider(width: 1, thickness: 1, color: c.border),
            Expanded(child: _buildLivePreview(c)),
          ],
        );
    }
  }

  Widget _buildLivePreview(AppColorsExtension c) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _contentController,
      builder: (context, value, _) => _buildPreviewSurface(c, value.text),
    );
  }

  Widget _buildPreviewSurface(AppColorsExtension c, String content) {
    return _buildZoomAwareSurface(
      Container(
        color: c.scaffold,
        padding: const EdgeInsets.all(AppDimensions.spacingLg),
        child: MarkdownPreviewWidget(
          content: content,
          contentScale: widget.contentScale,
        ),
      ),
    );
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

/// Segmented control switching between Edit / Split / Preview view modes.
/// The Split segment is omitted when [allowSplit] is false.
class _ViewModeControl extends StatelessWidget {
  final EditorViewMode mode;
  final bool allowSplit;
  final ValueChanged<EditorViewMode> onChanged;

  const _ViewModeControl({
    required this.mode,
    required this.allowSplit,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ViewModeSegment(
            label: 'Edit',
            active: mode == EditorViewMode.edit,
            onTap: () => onChanged(EditorViewMode.edit),
          ),
          if (allowSplit)
            _ViewModeSegment(
              label: 'Split',
              active: mode == EditorViewMode.split,
              onTap: () => onChanged(EditorViewMode.split),
            ),
          _ViewModeSegment(
            label: 'Preview',
            active: mode == EditorViewMode.preview,
            onTap: () => onChanged(EditorViewMode.preview),
          ),
        ],
      ),
    );
  }
}

class _ViewModeSegment extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ViewModeSegment({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppDimensions.animFast,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: active ? c.accentMuted : Colors.transparent,
            borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
          ),
          child: Text(
            label,
            style: AppTextStyles.microMedium.copyWith(
              color: active ? c.accent : c.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Column/row count returned by [_InsertTableDialog].
class _TableSpec {
  const _TableSpec(this.columns, this.rows);
  final int columns;
  final int rows;
}

/// Dialog to choose the dimensions of a markdown table to insert.
class _InsertTableDialog extends StatefulWidget {
  const _InsertTableDialog();

  @override
  State<_InsertTableDialog> createState() => _InsertTableDialogState();
}

class _InsertTableDialogState extends State<_InsertTableDialog> {
  int _columns = 2;
  int _rows = 2;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return AlertDialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
        side: BorderSide(color: c.border),
      ),
      title: Text(
        'Insert table',
        style: Theme.of(context).textTheme.titleSmall!.copyWith(
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
      ),
      content: SizedBox(
        width: 240,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepperRow(
              label: 'Columns',
              value: _columns,
              onChanged: (v) => setState(() => _columns = v),
            ),
            const SizedBox(height: AppDimensions.spacingMd),
            _StepperRow(
              label: 'Rows',
              value: _rows,
              onChanged: (v) => setState(() => _rows = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: AppTextStyles.captionThin.copyWith(color: c.textMuted),
          ),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, _TableSpec(_columns, _rows)),
          child: const Text('Insert'),
        ),
      ],
    );
  }
}

class _StepperRow extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _StepperRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  static const int _min = 1;
  static const int _max = 10;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.caption.copyWith(color: c.textSecondary),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
          color: c.textSecondary,
          splashRadius: 14,
          onPressed: value > _min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 24,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(color: c.textPrimary),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
          color: c.textSecondary,
          splashRadius: 14,
          onPressed: value < _max ? () => onChanged(value + 1) : null,
        ),
      ],
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
