import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

class NoteSearchSection extends StatelessWidget {
  const NoteSearchSection({
    super.key,
    this.controller,
    required this.query,
    this.tag = '',
    this.startDate,
    this.endDate,
    this.isLoading = false,
    required this.onQueryChanged,
    required this.onClear,
    required this.onOpenFilters,
  });

  final TextEditingController? controller;
  final String query;
  final String tag;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isLoading;
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

    return Container(
      color: c.surface,
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.spacingMd,
        AppDimensions.spacingSm,
        AppDimensions.spacingMd,
        AppDimensions.spacingSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: effectiveController,
                  onChanged: onQueryChanged,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: c.textPrimary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search notes',
                    hintStyle: GoogleFonts.manrope(
                      fontSize: 12,
                      color: c.textMuted,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 16,
                      color: c.textMuted,
                    ),
                    suffixIcon: query.trim().isEmpty && !_hasActiveFilters
                        ? null
                        : IconButton(
                            onPressed: onClear,
                            splashRadius: 14,
                            icon: Icon(
                              Icons.close_rounded,
                              size: 16,
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
              const SizedBox(width: AppDimensions.spacingSm),
              InkWell(
                onTap: onOpenFilters,
                borderRadius: BorderRadius.circular(
                  AppDimensions.borderRadiusSm,
                ),
                child: Container(
                  padding: const EdgeInsets.all(8),
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
                    size: 16,
                    color: _hasActiveFilters ? c.accent : c.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          if (_hasActiveFilters) ...[
            const SizedBox(height: AppDimensions.spacingSm),
            Wrap(
              spacing: AppDimensions.spacingXs,
              runSpacing: AppDimensions.spacingXs,
              children: [
                if (tag.trim().isNotEmpty) _FilterChip(label: '#${tag.trim()}'),
                if (startDate != null || endDate != null)
                  _FilterChip(
                    label:
                        '${_formatDate(startDate)} - ${_formatDate(endDate)}',
                  ),
              ],
            ),
          ],
          if (isLoading) ...[
            const SizedBox(height: AppDimensions.spacingSm),
            LinearProgressIndicator(
              minHeight: 2,
              color: c.accent,
              backgroundColor: c.surfaceHover,
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '...';
    return DateFormat('yyyy-MM-dd').format(value);
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.accentSubtle,
        borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: c.accent,
        ),
      ),
    );
  }
}
