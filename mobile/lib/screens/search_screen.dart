import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/note.dart';
import '../search/note_search_index.dart';
import '../search/note_search_query.dart';
import '../search/search_result.dart';
import '../settings/app_settings_controller.dart';
import '../storage/note_storage.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import 'editor_screen.dart';

class SearchScreen extends StatefulWidget {
  final NoteStorage storage;
  final NoteStorage? localStorage;
  final AppSettingsController settingsController;

  const SearchScreen({
    super.key,
    required this.storage,
    this.localStorage,
    required this.settingsController,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final NoteSearchIndex _searchIndex = NoteSearchIndex();

  NoteSearchQuery _query = const NoteSearchQuery();
  List<SearchResult> _results = [];
  bool _isIndexBuilt = false;

  static final DateFormat _dateFmt = DateFormat('yyyy-MM-dd');
  static final DateFormat _dateDisplayFmt = DateFormat('M월 d일', 'ko');

  @override
  void initState() {
    super.initState();
    _buildIndex();
  }

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storage != widget.storage ||
        oldWidget.localStorage != widget.localStorage) {
      _buildIndex();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _buildIndex() async {
    final notes = <Note>[
      ...await widget.storage.listAllNotes(),
      if (widget.localStorage != null)
        ...await widget.localStorage!.listAllNotes(),
    ];
    _searchIndex.replaceAll(notes);
    if (!mounted) return;
    setState(() {
      _isIndexBuilt = true;
    });
    _runSearch();
  }

  void _runSearch() {
    if (_query.isEmpty) {
      setState(() => _results = []);
      return;
    }
    final contextLines = widget.settingsController.value.searchContextLines;
    final results = _searchIndex.searchWithContext(
      _query,
      contextLines: contextLines,
    );
    setState(() => _results = results);
  }

  void _onSearchTextChanged(String value) {
    _query = _query.copyWith(text: value);
    _runSearch();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _query = const NoteSearchQuery();
      _results = [];
    });
  }

  void _removeTagFilter() {
    _query = _query.copyWith(tag: '');
    _runSearch();
  }

  void _removeDateFilter() {
    _query = _query.copyWith(startDate: null, endDate: null);
    _runSearch();
  }

  bool get _hasFilters =>
      _query.tag.trim().isNotEmpty ||
      _query.startDate != null ||
      _query.endDate != null;

  void _openFilterSheet() {
    final c = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppDimensions.borderRadiusLg),
        ),
      ),
      isScrollControlled: true,
      builder: (ctx) => _FilterSheet(
        initialQuery: _query,
        colors: c,
        onApply: (updatedQuery) {
          Navigator.pop(ctx);
          _query = updatedQuery;
          _runSearch();
        },
      ),
    );
  }

  NoteStorage _storageFor(Note note) {
    if (note.storageType == StorageType.local && widget.localStorage != null) {
      return widget.localStorage!;
    }
    return widget.storage;
  }

  void _openResult(SearchResult result) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          note: result.note,
          storage: _storageFor(result.note),
          settingsController: widget.settingsController,
          onNoteChanged: (_) {},
          onNoteDeleted: (_) {},
        ),
      ),
    ).then((_) => _buildIndex());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.scaffold,
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(c),
            if (_hasFilters) _buildActiveFilters(c),
            if (_query.isEmpty)
              Expanded(child: _buildEmptyState(c))
            else ...[
              _buildResultsCount(c),
              Expanded(child: _buildResultsList(c)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(AppColorsExtension c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.spacingLg,
        AppDimensions.spacingMd,
        AppDimensions.spacingLg,
        AppDimensions.spacingSm,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _onSearchTextChanged,
              style: GoogleFonts.manrope(
                fontSize: 15,
                color: c.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: '노트 검색...',
                hintStyle: TextStyle(color: c.textMuted, fontSize: 15),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: c.textMuted,
                  size: 20,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: c.textMuted,
                          size: 18,
                        ),
                        onPressed: _clearSearch,
                      )
                    : null,
                filled: true,
                fillColor: c.surfaceLight,
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppDimensions.borderRadius),
                  borderSide: BorderSide(color: c.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppDimensions.borderRadius),
                  borderSide: BorderSide(color: c.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppDimensions.borderRadius),
                  borderSide: BorderSide(color: c.accent, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.spacingMd,
                  vertical: AppDimensions.spacingMd,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppDimensions.spacingSm),
          Stack(
            children: [
              IconButton(
                onPressed: _openFilterSheet,
                icon: Icon(
                  Icons.tune_rounded,
                  color: _hasFilters ? c.accent : c.textSecondary,
                  size: 22,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: _hasFilters ? c.accentSubtle : c.surfaceLight,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppDimensions.borderRadius),
                    side: BorderSide(color: c.border),
                  ),
                ),
              ),
              if (_hasFilters)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.accent,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFilters(AppColorsExtension c) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingLg,
      ),
      child: Wrap(
        spacing: AppDimensions.spacingSm,
        runSpacing: AppDimensions.spacingXs,
        children: [
          if (_query.tag.trim().isNotEmpty)
            _buildFilterChip(
              c,
              label: '#${_query.tag}',
              onRemove: _removeTagFilter,
            ),
          if (_query.startDate != null || _query.endDate != null)
            _buildFilterChip(
              c,
              label: _buildDateRangeLabel(),
              onRemove: _removeDateFilter,
            ),
        ],
      ),
    );
  }

  String _buildDateRangeLabel() {
    final start = _query.startDate;
    final end = _query.endDate;
    if (start != null && end != null) {
      return '${_dateDisplayFmt.format(start)} - ${_dateDisplayFmt.format(end)}';
    }
    if (start != null) {
      return '${_dateDisplayFmt.format(start)} ~';
    }
    if (end != null) {
      return '~ ${_dateDisplayFmt.format(end)}';
    }
    return '';
  }

  Widget _buildFilterChip(
    AppColorsExtension c, {
    required String label,
    required VoidCallback onRemove,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.accentSubtle,
        borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
        border: Border.all(color: c.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: c.accent,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close_rounded, size: 14, color: c.accent),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsCount(AppColorsExtension c) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingLg,
        vertical: AppDimensions.spacingSm,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '${_results.length}개 결과',
          style: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: c.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppColorsExtension c) {
    if (!_isIndexBuilt) {
      return Center(child: CircularProgressIndicator(color: c.accent));
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_rounded, size: 48, color: c.textMuted),
          const SizedBox(height: AppDimensions.spacingMd),
          Text(
            '검색어를 입력하세요',
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: c.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList(AppColorsExtension c) {
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: c.textMuted),
            const SizedBox(height: AppDimensions.spacingMd),
            Text(
              '검색 결과가 없습니다',
              style: GoogleFonts.manrope(fontSize: 14, color: c.textMuted),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingLg,
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final result = _results[index];
        return _buildResultCard(c, result);
      },
    );
  }

  Widget _buildResultCard(AppColorsExtension c, SearchResult result) {
    final note = result.note;
    final isLocal = note.storageType == StorageType.local;

    return GestureDetector(
      onTap: () => _openResult(result),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppDimensions.spacingSm),
        padding: const EdgeInsets.all(AppDimensions.spacingMd),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius:
              BorderRadius.circular(AppDimensions.cardBorderRadius),
          border: Border.all(color: c.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title + date + storage badge
            Row(
              children: [
                Expanded(
                  child: Text(
                    note.title.isEmpty ? 'Untitled' : note.title,
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppDimensions.spacingSm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isLocal
                        ? c.localAccent.withValues(alpha: 0.15)
                        : c.accentSubtle,
                    borderRadius: BorderRadius.circular(
                      AppDimensions.borderRadiusSm,
                    ),
                  ),
                  child: Text(
                    isLocal ? 'local' : 'synced',
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isLocal ? c.localAccent : c.accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _dateFmt.format(note.noteDate),
              style: TextStyle(fontSize: 12, color: c.textMuted),
            ),
            const SizedBox(height: AppDimensions.spacingSm),
            // Context lines with highlight
            _buildContextLines(c, result),
            if (note.tags.isNotEmpty) ...[
              const SizedBox(height: AppDimensions.spacingSm),
              Wrap(
                spacing: AppDimensions.spacingXs,
                runSpacing: AppDimensions.spacingXs,
                children: note.tags.map((tag) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: c.accentSubtle,
                      borderRadius: BorderRadius.circular(
                        AppDimensions.borderRadiusSm,
                      ),
                    ),
                    child: Text(
                      '#$tag',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: c.accent,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContextLines(AppColorsExtension c, SearchResult result) {
    final lines = <InlineSpan>[];

    // Context before
    for (final line in result.contextBefore) {
      lines.add(TextSpan(
        text: '$line\n',
        style: TextStyle(color: c.textMuted, fontSize: 12, height: 1.5),
      ));
    }

    // Matched line with highlight
    final match = result.match;
    if (match.matchStart < match.matchEnd && match.line.isNotEmpty) {
      final before = match.line.substring(0, match.matchStart);
      final matched =
          match.line.substring(match.matchStart, match.matchEnd);
      final after = match.line.substring(match.matchEnd);
      lines.add(TextSpan(
        children: [
          TextSpan(
            text: before,
            style: TextStyle(color: c.textSecondary, fontSize: 12, height: 1.5),
          ),
          TextSpan(
            text: matched,
            style: TextStyle(
              color: c.accent,
              fontSize: 12,
              height: 1.5,
              fontWeight: FontWeight.w700,
              backgroundColor: c.accentSubtle,
            ),
          ),
          TextSpan(
            text: '$after\n',
            style: TextStyle(color: c.textSecondary, fontSize: 12, height: 1.5),
          ),
        ],
      ));
    } else {
      lines.add(TextSpan(
        text: '${match.line}\n',
        style: TextStyle(color: c.textSecondary, fontSize: 12, height: 1.5),
      ));
    }

    // Context after
    for (final line in result.contextAfter) {
      lines.add(TextSpan(
        text: '$line\n',
        style: TextStyle(color: c.textMuted, fontSize: 12, height: 1.5),
      ));
    }

    return RichText(
      text: TextSpan(children: lines),
      maxLines: 6,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// ── Filter Bottom Sheet ──

class _FilterSheet extends StatefulWidget {
  final NoteSearchQuery initialQuery;
  final AppColorsExtension colors;
  final void Function(NoteSearchQuery) onApply;

  const _FilterSheet({
    required this.initialQuery,
    required this.colors,
    required this.onApply,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late TextEditingController _tagController;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _tagController = TextEditingController(text: widget.initialQuery.tag);
    _startDate = widget.initialQuery.startDate;
    _endDate = widget.initialQuery.endDate;
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _startDate = DateTime(picked.year, picked.month, picked.day);
      if (_endDate != null && _endDate!.isBefore(_startDate!)) {
        _endDate = _startDate;
      }
    });
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _endDate = DateTime(picked.year, picked.month, picked.day);
      if (_startDate != null && _startDate!.isAfter(_endDate!)) {
        _startDate = _endDate;
      }
    });
  }

  void _quickSelectToday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _startDate = today;
      _endDate = today;
    });
  }

  void _quickSelectThisWeek() {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    setState(() {
      _startDate = DateTime(weekStart.year, weekStart.month, weekStart.day);
      _endDate = DateTime(now.year, now.month, now.day);
    });
  }

  void _quickSelectThisMonth() {
    final now = DateTime.now();
    setState(() {
      _startDate = DateTime(now.year, now.month, 1);
      _endDate = DateTime(now.year, now.month, now.day);
    });
  }

  void _clearFilters() {
    widget.onApply(widget.initialQuery.copyWith(
      tag: '',
      startDate: null,
      endDate: null,
    ));
  }

  void _applyFilters() {
    widget.onApply(widget.initialQuery.copyWith(
      tag: _tagController.text.trim(),
      startDate: _startDate,
      endDate: _endDate,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final dateFmt = DateFormat('yyyy-MM-dd');

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppDimensions.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.borderSubtle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.spacingLg),
            Text(
              '필터',
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingLg),

            // Tag input
            Text(
              '태그',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingSm),
            TextField(
              controller: _tagController,
              style: GoogleFonts.manrope(fontSize: 14, color: c.textPrimary),
              decoration: InputDecoration(
                hintText: '태그를 입력하세요',
                hintStyle: TextStyle(color: c.textMuted),
                prefixIcon: Icon(Icons.tag_rounded, size: 18, color: c.textMuted),
              ),
            ),
            const SizedBox(height: AppDimensions.spacingLg),

            // Date range
            Text(
              '날짜 범위',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingSm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickStartDate,
                    icon: Icon(Icons.calendar_today_rounded, size: 14, color: c.textSecondary),
                    label: Text(
                      _startDate != null
                          ? dateFmt.format(_startDate!)
                          : '시작일',
                      style: TextStyle(color: c.textSecondary, fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: c.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppDimensions.borderRadius,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: AppDimensions.spacingMd,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.spacingSm,
                  ),
                  child: Text('~', style: TextStyle(color: c.textMuted)),
                ),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickEndDate,
                    icon: Icon(Icons.calendar_today_rounded, size: 14, color: c.textSecondary),
                    label: Text(
                      _endDate != null ? dateFmt.format(_endDate!) : '종료일',
                      style: TextStyle(color: c.textSecondary, fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: c.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppDimensions.borderRadius,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: AppDimensions.spacingMd,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingMd),

            // Quick select
            Wrap(
              spacing: AppDimensions.spacingSm,
              children: [
                _QuickDateButton(
                  label: '오늘',
                  onTap: _quickSelectToday,
                  colors: c,
                ),
                _QuickDateButton(
                  label: '이번 주',
                  onTap: _quickSelectThisWeek,
                  colors: c,
                ),
                _QuickDateButton(
                  label: '이번 달',
                  onTap: _quickSelectThisMonth,
                  colors: c,
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingXl),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _clearFilters,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: c.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppDimensions.borderRadius,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: AppDimensions.spacingMd,
                      ),
                    ),
                    child: Text(
                      '초기화',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppDimensions.spacingMd),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _applyFilters,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: c.textOnAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppDimensions.borderRadius,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: AppDimensions.spacingMd,
                      ),
                    ),
                    child: Text(
                      '적용',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingSm),
          ],
        ),
      ),
    );
  }
}

class _QuickDateButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final AppColorsExtension colors;

  const _QuickDateButton({
    required this.label,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surfaceLight,
          borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
          border: Border.all(color: colors.border),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
