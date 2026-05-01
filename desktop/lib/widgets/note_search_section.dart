import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
      children: [
        Expanded(
          child: SizedBox(
            height: 30,
            child: TextField(
              controller: effectiveController,
              focusNode: focusNode,
              onChanged: onQueryChanged,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: c.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                hintText: _hasActiveFilters ? 'Search (filters active)' : 'Search notes',
                hintStyle: GoogleFonts.inter(
                  fontSize: 12,
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
            AppDimensions.borderRadiusSm,
          ),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _hasActiveFilters ? c.accentSubtle : c.surfaceLight,
              borderRadius: BorderRadius.circular(
                AppDimensions.borderRadiusSm,
              ),
              border: Border.all(
                color: _hasActiveFilters ? c.accent : c.border,
              ),
            ),
            child: Icon(
              Icons.tune_rounded,
              size: 14,
              color: _hasActiveFilters ? c.accent : c.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
