import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/note.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';

/// Horizontal strip of open editor tabs above the editor surface.
///
/// Tabs are labelled `yyyy-MM-dd:title`. As the available width per tab
/// shrinks, the label is abbreviated (short date, then date dropped) so the
/// file name stays visible; the full label is always available as a tooltip.
/// When the tabs cannot fit even at their minimum width the strip scrolls
/// horizontally.
class EditorTabBar extends StatelessWidget {
  const EditorTabBar({
    super.key,
    required this.tabs,
    required this.activeNoteId,
    required this.onSelect,
    required this.onClose,
  });

  final List<Note> tabs;
  final String? activeNoteId;
  final ValueChanged<Note> onSelect;
  final ValueChanged<Note> onClose;

  static const double _height = 36;
  static const double _minTabWidth = 96;
  static const double _maxTabWidth = 188;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      height: _height,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = tabs.length;
          final available = constraints.maxWidth;
          var tabWidth =
              count == 0 ? _maxTabWidth : available / count;
          tabWidth = tabWidth.clamp(_minTabWidth, _maxTabWidth);
          final fits = tabWidth * count <= available + 0.5;

          final row = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final note in tabs)
                _EditorTab(
                  key: ValueKey(note.id),
                  width: tabWidth,
                  note: note,
                  isActive: note.id == activeNoteId,
                  onTap: () => onSelect(note),
                  onClose: () => onClose(note),
                ),
            ],
          );

          if (fits) return row;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: row,
          );
        },
      ),
    );
  }
}

class _EditorTab extends StatefulWidget {
  const _EditorTab({
    super.key,
    required this.width,
    required this.note,
    required this.isActive,
    required this.onTap,
    required this.onClose,
  });

  final double width;
  final Note note;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  State<_EditorTab> createState() => _EditorTabState();
}

class _EditorTabState extends State<_EditorTab> {
  bool _hovered = false;

  String get _fileName =>
      widget.note.title.trim().isEmpty ? 'Untitled' : widget.note.title.trim();

  String get _fullLabel {
    final date = DateFormat('yyyy-MM-dd').format(widget.note.noteDate);
    return '$date:$_fileName';
  }

  /// Picks a label that fits the tab width, prioritising the file name.
  String _responsiveLabel() {
    final note = widget.note;
    if (widget.width >= 150) {
      return '${DateFormat('yyyy-MM-dd').format(note.noteDate)}:$_fileName';
    }
    if (widget.width >= 118) {
      return '${DateFormat('MM-dd').format(note.noteDate)}:$_fileName';
    }
    return _fileName;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLocal = widget.note.storageType == StorageType.local;
    final accent = isLocal ? c.localAccent : c.accent;

    final bg = widget.isActive
        ? c.scaffold
        : _hovered
            ? c.surfaceHover
            : c.surface;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Tooltip(
          message: _fullLabel,
          waitDuration: const Duration(milliseconds: 500),
          child: Container(
            width: widget.width,
            decoration: BoxDecoration(
              color: bg,
              border: Border(
                right: BorderSide(color: c.border),
                bottom: BorderSide(
                  color: widget.isActive ? accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            padding: const EdgeInsets.only(
              left: AppDimensions.spacingMd,
              right: AppDimensions.spacingXs,
            ),
            child: Row(
              children: [
                if (isLocal) ...[
                  Icon(Icons.folder_outlined,
                      size: 11, color: accent.withValues(alpha: 0.8)),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    _responsiveLabel(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.micro.copyWith(
                      color: widget.isActive ? c.textPrimary : c.textSecondary,
                      fontWeight:
                          widget.isActive ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                _TabCloseButton(
                  visible: widget.isActive || _hovered,
                  onTap: widget.onClose,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabCloseButton extends StatefulWidget {
  const _TabCloseButton({required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback onTap;

  @override
  State<_TabCloseButton> createState() => _TabCloseButtonState();
}

class _TabCloseButtonState extends State<_TabCloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Reserve the slot so the label width does not jump as the button appears.
    return SizedBox(
      width: 20,
      height: 20,
      child: widget.visible
          ? MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: GestureDetector(
                onTap: widget.onTap,
                child: Container(
                  decoration: BoxDecoration(
                    color: _hovered ? c.surfaceHover : Colors.transparent,
                    borderRadius:
                        BorderRadius.circular(AppDimensions.radiusMicro),
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 13,
                    color: _hovered ? c.textPrimary : c.textMuted,
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
