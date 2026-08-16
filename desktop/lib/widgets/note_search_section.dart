import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

/// Search field + filter button shown in the title bar.
///
/// Both controls are plain [Container]s sharing [_controlHeight], the same
/// border radius and the same border, so they render at identical size — the
/// search field uses `InputBorder.none` and wraps the [TextField] itself rather
/// than relying on an `OutlineInputBorder` (whose intrinsic sizing did not
/// visually match the square filter button).
class NoteSearchSection extends StatefulWidget {
  const NoteSearchSection({
    super.key,
    this.controller,
    this.focusNode,
    required this.query,
    this.hasActiveFilters = false,
    this.filterLink,
    required this.onQueryChanged,
    required this.onClear,
    required this.onOpenFilters,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String query;
  final bool hasActiveFilters;

  /// Anchors the filter popover to the filter button (the parent owns the link
  /// and the overlay).
  final LayerLink? filterLink;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClear;
  final VoidCallback onOpenFilters;

  @override
  State<NoteSearchSection> createState() => _NoteSearchSectionState();
}

class _NoteSearchSectionState extends State<NoteSearchSection> {
  /// Shared control height so the search field and the filter button render at
  /// exactly the same size and stay vertically aligned.
  static const double _controlHeight = 32;

  FocusNode? _ownedFocusNode;
  bool _focused = false;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(NoteSearchSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChange);
      _ownedFocusNode?.removeListener(_handleFocusChange);
      _focusNode.addListener(_handleFocusChange);
      _focused = _focusNode.hasFocus;
    }
  }

  void _handleFocusChange() {
    if (mounted) setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_handleFocusChange);
    _ownedFocusNode?.removeListener(_handleFocusChange);
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters => widget.hasActiveFilters;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final controller = widget.controller ??
        TextEditingController.fromValue(
          TextEditingValue(
            text: widget.query,
            selection: TextSelection.collapsed(offset: widget.query.length),
          ),
        );
    final showClear = widget.query.trim().isNotEmpty || _hasActiveFilters;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Container(
            height: _controlHeight,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.spacingSm,
            ),
            decoration: BoxDecoration(
              color: c.surfaceLight,
              borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
              border: Border.all(color: _focused ? c.accent : c.border),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 16, color: c.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: _focusNode,
                    onChanged: widget.onQueryChanged,
                    textAlignVertical: TextAlignVertical.center,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall!
                        .copyWith(color: c.textPrimary),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: _hasActiveFilters
                          ? 'Search (filters active)'
                          : 'Search notes',
                      hintStyle: Theme.of(context)
                          .textTheme
                          .labelSmall!
                          .copyWith(color: c.textMuted),
                    ),
                  ),
                ),
                if (showClear)
                  GestureDetector(
                    onTap: widget.onClear,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: _ClearIcon(),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppDimensions.spacingSm),
        _maybeLink(
          InkWell(
            onTap: widget.onOpenFilters,
            borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
            child: Container(
              width: _controlHeight,
              height: _controlHeight,
              decoration: BoxDecoration(
                color: _hasActiveFilters ? c.accentSubtle : c.surfaceLight,
                borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
                border: Border.all(
                  color: _hasActiveFilters ? c.accent : c.border,
                ),
              ),
              child: Icon(
                Icons.tune_rounded,
                size: 16,
                color: _hasActiveFilters ? c.accent : c.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _maybeLink(Widget child) {
    final link = widget.filterLink;
    return link == null
        ? child
        : CompositedTransformTarget(link: link, child: child);
  }
}

class _ClearIcon extends StatelessWidget {
  const _ClearIcon();

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.close_rounded, size: 14, color: context.colors.textMuted);
  }
}
