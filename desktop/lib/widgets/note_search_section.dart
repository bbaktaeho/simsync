import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

class NoteSearchSection extends StatelessWidget {
  const NoteSearchSection({
    super.key,
    this.controller,
    this.focusNode,
    required this.query,
    this.tag = '',
    this.startDate,
    this.endDate,
    required this.onQueryChanged,
    required this.onClear,
    required this.onOpenFilters,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String query;
  final String tag;
  final DateTime? startDate;
  final DateTime? endDate;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClear;
  final VoidCallback onOpenFilters;

  bool get _hasActiveFilters =>
      tag.trim().isNotEmpty || startDate != null || endDate != null;

  /// Shared control height so the search field and the filter button render at
  /// exactly the same size and stay vertically aligned.
  static const double _controlHeight = 32;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final effectiveController =
        controller ??
        TextEditingController.fromValue(
          TextEditingValue(
            text: query,
            selection: TextSelection.collapsed(offset: query.length),
          ),
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: SizedBox(
            height: _controlHeight,
            child: TextField(
              controller: effectiveController,
              focusNode: focusNode,
              onChanged: onQueryChanged,
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: c.textPrimary,
                  ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.spacingSm,
                  vertical: 6,
                ),
                hintText: _hasActiveFilters ? 'Search (filters active)' : 'Search notes',
                hintStyle: Theme.of(context).textTheme.labelSmall!.copyWith(
                      color: c.textMuted,
                    ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 16,
                  color: c.textMuted,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 16,
                ),
                suffixIcon: query.trim().isEmpty && !_hasActiveFilters
                    ? null
                    : IconButton(
                        onPressed: onClear,
                        splashRadius: 12,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        icon: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: c.textMuted,
                        ),
                      ),
                filled: true,
                fillColor: c.surfaceLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    AppDimensions.borderRadius,
                  ),
                  borderSide: BorderSide(color: c.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    AppDimensions.borderRadius,
                  ),
                  borderSide: BorderSide(color: c.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    AppDimensions.borderRadius,
                  ),
                  borderSide: BorderSide(color: c.accent),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppDimensions.spacingSm),
        InkWell(
          onTap: onOpenFilters,
          borderRadius: BorderRadius.circular(
            AppDimensions.borderRadius,
          ),
          child: Container(
            width: _controlHeight,
            height: _controlHeight,
            decoration: BoxDecoration(
              color: _hasActiveFilters ? c.accentSubtle : c.surfaceLight,
              borderRadius: BorderRadius.circular(
                AppDimensions.borderRadius,
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
      ],
    );
  }
}
