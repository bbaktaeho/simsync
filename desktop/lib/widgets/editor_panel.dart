import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/note.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';
import 'markdown_preview.dart';

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
  late TextEditingController _contentController;
  late TextEditingController _tagController;
  bool _showPreview = false;
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
  void _flushPending(Note note) {
    if (widget.isReadOnly || !note.isDirty) return;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    final updated = note.copyWith(
      title: _titleController.text,
      content: _contentController.text,
      updatedAt: DateTime.now(),
    );
    widget.onNoteChanged?.call(updated);
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
        Expanded(child: _showPreview ? _buildPreview(c) : _buildEditor(c)),
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
          _ToggleButton(
            icon: _showPreview ? Icons.edit_rounded : Icons.visibility_rounded,
            label: _showPreview ? 'Edit' : 'Preview',
            onTap: () => setState(() => _showPreview = !_showPreview),
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

  Widget _buildPreview(AppColorsExtension c) {
    return _buildZoomAwareSurface(
      Container(
        color: c.scaffold,
        padding: const EdgeInsets.all(AppDimensions.spacingLg),
        child: MarkdownPreviewWidget(
          content: _contentController.text,
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

class _ToggleButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_ToggleButton> createState() => _ToggleButtonState();
}

class _ToggleButtonState extends State<_ToggleButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppDimensions.animFast,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _isHovered ? c.surfaceHover : c.surfaceLight,
            borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
            border: Border.all(color: c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: c.textSecondary),
              const SizedBox(width: 4),
              Text(
                widget.label,
                style: AppTextStyles.microMedium.copyWith(color: c.textSecondary),
              ),
            ],
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
