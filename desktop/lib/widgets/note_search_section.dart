import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_theme.dart';

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

  /// 아이콘·글자 잉크가 박스보다 아래에 그려지는 것을 상쇄하는 값.
  static const double _opticalNudge = 4;

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
    final controller =
        widget.controller ??
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
            // 아래쪽에만 여백을 조금 준다. 아이콘과 글자 모두 잉크가 박스보다
            // 아래에 그려져(실측 각각 +2.0px, +1.5px) 그냥 가운데 정렬하면
            // 눈에는 내려앉아 보인다 — 광학 보정.
            padding: const EdgeInsets.fromLTRB(
              AppDimensions.spacingSm,
              0,
              AppDimensions.spacingSm,
              _opticalNudge,
            ),
            decoration: BoxDecoration(
              color: c.surfaceLight,
              borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
              // 평상시엔 채운 배경만으로 충분하다. 테두리는 포커스 표시로만
              // 쓴다 (DESIGN.md §8: 인터랙티브 요소는 포커스가 보여야 한다).
              border: _focused ? Border.all(color: c.accent) : null,
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
                    // 한 줄 컨트롤의 세로 정렬. height 1.0으로 라인 박스를
                    // 글자 크기에 맞추고, leading을 위아래 균등 분배해야 잉크가
                    // 박스 가운데 온다 (기본 proportional은 아래로 쏠린다 —
                    // 실측 +1.5px).
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      color: c.textPrimary,
                      height: 1.0,
                      leadingDistribution: TextLeadingDistribution.even,
                    ),
                    // 배경/테두리는 바깥 Container가 그린다. isDense 조합이라야
                    // 32px 슬롯 안에서 글자가 가운데 온다 (isCollapsed는 위로 붙는다).
                    decoration: bareInputDecoration.copyWith(
                      hintText: _hasActiveFilters
                          ? 'Search (filters active)'
                          : 'Search notes',
                      hintStyle: Theme.of(context).textTheme.labelSmall!.copyWith(
                        color: c.textMuted,
                        height: 1.0,
                        leadingDistribution: TextLeadingDistribution.even,
                      ),
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
                borderRadius: BorderRadius.circular(
                  AppDimensions.radiusStandard,
                ),
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
