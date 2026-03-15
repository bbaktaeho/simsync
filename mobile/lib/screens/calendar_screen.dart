import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/note.dart';
import '../services/note_service.dart';
import '../settings/app_settings_controller.dart';
import '../storage/github/repo_cache.dart';
import '../storage/note_storage.dart';
import '../storage/sync_engine.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import 'editor_screen.dart';

class CalendarScreen extends StatefulWidget {
  final NoteStorage storage;
  final NoteStorage? localStorage;
  final NoteService noteService;
  final ValueNotifier<int> refreshSignal;
  final String? avatarUrl;
  final RepoEntry? activeRepo;
  final AppSettingsController settingsController;
  final SyncEngine? syncEngine;

  const CalendarScreen({
    super.key,
    required this.storage,
    this.localStorage,
    required this.noteService,
    required this.refreshSignal,
    this.avatarUrl,
    this.activeRepo,
    required this.settingsController,
    this.syncEngine,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _displayedMonth = DateTime.now();
  DateTime _selectedDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  bool _calendarExpanded = true;
  List<Note> _notes = [];
  Set<DateTime> _datesWithNotes = {};
  bool _isLoading = true;
  StreamSubscription<SyncStatus>? _syncSub;
  SyncStatus _syncStatus = SyncStatus.idle;

  static final DateFormat _monthFmt = DateFormat('yyyy년 M월');
  static final DateFormat _dayHeaderFmt = DateFormat('M월 d일 EEEE', 'ko');

  static const List<String> _weekdayHeaders = [
    '일',
    '월',
    '화',
    '수',
    '목',
    '금',
    '토',
  ];

  @override
  void initState() {
    super.initState();
    _loadNotes();
    _loadDatesWithNotes();
    widget.refreshSignal.addListener(_onRefresh);
    _syncSub = widget.syncEngine?.statusStream.listen((status) {
      if (!mounted) return;
      setState(() => _syncStatus = status);
    });
  }

  @override
  void didUpdateWidget(covariant CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSignal != widget.refreshSignal) {
      oldWidget.refreshSignal.removeListener(_onRefresh);
      widget.refreshSignal.addListener(_onRefresh);
    }
    if (oldWidget.storage != widget.storage ||
        oldWidget.localStorage != widget.localStorage) {
      _loadNotes();
      _loadDatesWithNotes();
    }
    if (oldWidget.syncEngine != widget.syncEngine) {
      _syncSub?.cancel();
      _syncSub = widget.syncEngine?.statusStream.listen((status) {
        if (!mounted) return;
        setState(() => _syncStatus = status);
      });
    }
  }

  @override
  void dispose() {
    widget.refreshSignal.removeListener(_onRefresh);
    _syncSub?.cancel();
    super.dispose();
  }

  void _onRefresh() {
    _loadNotes();
    _loadDatesWithNotes();
  }

  Future<void> _loadNotes() async {
    try {
      final notes = <Note>[];
      final dayNotes = await widget.storage.listNotes(_selectedDate);
      notes.addAll(dayNotes);
      if (widget.localStorage != null) {
        final localDayNotes = await widget.localStorage!.listNotes(
          _selectedDate,
        );
        notes.addAll(localDayNotes);
      }
      notes.sort((a, b) {
        if (a.isDefault && !b.isDefault) return -1;
        if (!a.isDefault && b.isDefault) return 1;
        return a.createdAt.compareTo(b.createdAt);
      });
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      debugPrint('_loadNotes error: $e');
    }
  }

  Future<void> _loadDatesWithNotes() async {
    try {
      final ym =
          '${_displayedMonth.year}-${_displayedMonth.month.toString().padLeft(2, '0')}';
      final dates = <DateTime>{};
      final syncedDates = await widget.storage.listDates(ym);
      for (final d in syncedDates) {
        dates.add(DateTime(d.year, d.month, d.day));
      }
      if (widget.localStorage != null) {
        final localDates = await widget.localStorage!.listDates(ym);
        for (final d in localDates) {
          dates.add(DateTime(d.year, d.month, d.day));
        }
      }
      if (!mounted) return;
      setState(() => _datesWithNotes = dates);
    } catch (e) {
      debugPrint('_loadDatesWithNotes error: $e');
    }
  }

  Future<void> _createNote() async {
    final now = DateTime.now();
    final existingNotes = _notes;
    final isDefault = existingNotes.isEmpty;
    final newNote = Note(
      id: now.millisecondsSinceEpoch.toString(),
      noteDate: _selectedDate,
      title: '',
      content: '',
      isDefault: isDefault,
      tags: [],
      createdAt: now,
      updatedAt: now,
    );
    await widget.storage.saveNote(newNote);
    if (!mounted) return;
    setState(() => _notes.add(newNote));
    _datesWithNotes.add(
      DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day),
    );
    if (!mounted) return;
    _openEditor(newNote);
  }

  Future<void> _deleteNote(Note note) async {
    final confirmed = await _showDeleteConfirmation(note);
    if (confirmed != true) return;

    final storage = _storageFor(note);
    try {
      await storage.deleteNote(note);
      if (!mounted) return;
      setState(() {
        _notes.removeWhere((n) => n.id == note.id);
      });
      _loadDatesWithNotes();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
      }
    }
  }

  NoteStorage _storageFor(Note note) {
    if (note.storageType == StorageType.local && widget.localStorage != null) {
      return widget.localStorage!;
    }
    return widget.storage;
  }

  Future<bool?> _showDeleteConfirmation(Note note) {
    final c = context.colors;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.borderRadiusLg),
          side: BorderSide(color: c.border),
        ),
        title: Text(
          '노트 삭제',
          style: GoogleFonts.manrope(
            color: c.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          "'${note.title.isEmpty ? 'Untitled' : note.title}' 노트를 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.",
          style: TextStyle(color: c.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소', style: TextStyle(color: c.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('삭제', style: TextStyle(color: c.error)),
          ),
        ],
      ),
    );
  }

  void _openEditor(Note note) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          note: note,
          storage: _storageFor(note),
          settingsController: widget.settingsController,
          refreshSignal: widget.refreshSignal,
          onNoteChanged: (updated) {
            setState(() {
              final idx = _notes.indexWhere((n) => n.id == updated.id);
              if (idx != -1) {
                _notes[idx] = updated;
              }
            });
          },
          onNoteDeleted: (deleted) {
            setState(() {
              _notes.removeWhere((n) => n.id == deleted.id);
            });
            _loadDatesWithNotes();
          },
        ),
      ),
    ).then((_) {
      _loadNotes();
      _loadDatesWithNotes();
    });
  }

  void _previousMonth() {
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month - 1,
      );
    });
    _loadDatesWithNotes();
  }

  void _nextMonth() {
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month + 1,
      );
    });
    _loadDatesWithNotes();
  }

  void _goToToday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _displayedMonth = DateTime(now.year, now.month);
      _selectedDate = today;
    });
    _loadNotes();
    _loadDatesWithNotes();
  }

  void _selectDate(DateTime date) {
    setState(() {
      _selectedDate = DateTime(date.year, date.month, date.day);
    });
    _loadNotes();
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.scaffold,
      appBar: _buildAppBar(c),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: c.accent))
          : Column(
              children: [
                _buildCalendarSection(c),
                Divider(height: 1, color: c.border),
                _buildDateHeader(c),
                Expanded(child: _buildNoteList(c)),
              ],
            ),
    );
  }

  PreferredSizeWidget _buildAppBar(AppColorsExtension c) {
    final avatarUrl = widget.avatarUrl?.trim();
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;

    return AppBar(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: AppDimensions.spacingLg,
      leading: Padding(
        padding: const EdgeInsets.only(left: AppDimensions.spacingLg),
        child: CircleAvatar(
          radius: 16,
          backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
          backgroundColor: c.surfaceHover,
          child: !hasAvatar
              ? Icon(Icons.person, size: 16, color: c.textMuted)
              : null,
        ),
      ),
      title: Text(
        _monthFmt.format(_displayedMonth),
        style: GoogleFonts.manrope(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: c.textPrimary,
        ),
      ),
      actions: [
        _buildSyncIndicator(c),
        IconButton(
          icon: Icon(Icons.chevron_left_rounded, color: c.textSecondary),
          onPressed: _previousMonth,
          splashRadius: 20,
        ),
        GestureDetector(
          onTap: _goToToday,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.spacingSm,
              vertical: AppDimensions.spacingXs,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
              border: Border.all(color: c.border),
            ),
            child: Text(
              '오늘',
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
              ),
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.chevron_right_rounded, color: c.textSecondary),
          onPressed: _nextMonth,
          splashRadius: 20,
        ),
        const SizedBox(width: AppDimensions.spacingSm),
      ],
    );
  }

  Widget _buildSyncIndicator(AppColorsExtension c) {
    IconData icon;
    Color color;
    switch (_syncStatus) {
      case SyncStatus.syncing:
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingSm,
          ),
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
          ),
        );
      case SyncStatus.error:
        icon = Icons.cloud_off_rounded;
        color = c.error;
      case SyncStatus.idle:
        icon = Icons.cloud_done_outlined;
        color = c.success;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingSm),
      child: Icon(icon, size: 18, color: color),
    );
  }

  Widget _buildCalendarSection(AppColorsExtension c) {
    return AnimatedContainer(
      duration: AppDimensions.animMedium,
      color: c.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_calendarExpanded)
            _buildCalendarGrid(c)
          else
            _buildCollapsedBadge(c),
          _buildCalendarToggle(c),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid(AppColorsExtension c) {
    final year = _displayedMonth.year;
    final month = _displayedMonth.month;
    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0);
    // Sunday = 0 offset
    final startWeekday = firstDay.weekday % 7;
    final daysInMonth = lastDay.day;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingLg,
        vertical: AppDimensions.spacingSm,
      ),
      child: Column(
        children: [
          // Weekday headers
          Row(
            children: _weekdayHeaders.map((day) {
              return Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: c.textMuted,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppDimensions.spacingSm),
          // Calendar cells
          ..._buildCalendarRows(
            c,
            startWeekday,
            daysInMonth,
            year,
            month,
            today,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCalendarRows(
    AppColorsExtension c,
    int startWeekday,
    int daysInMonth,
    int year,
    int month,
    DateTime today,
  ) {
    final rows = <Widget>[];
    var dayCounter = 1;
    final totalCells = startWeekday + daysInMonth;
    final rowCount = (totalCells / 7).ceil();

    for (var row = 0; row < rowCount; row++) {
      final cells = <Widget>[];
      for (var col = 0; col < 7; col++) {
        final cellIndex = row * 7 + col;
        if (cellIndex < startWeekday || dayCounter > daysInMonth) {
          cells.add(const Expanded(child: SizedBox.shrink()));
          continue;
        }

        final date = DateTime(year, month, dayCounter);
        final isToday = date == today;
        final isSelected = date == _selectedDate;
        final hasNotes = _datesWithNotes.contains(date);
        final day = dayCounter;
        dayCounter++;

        cells.add(
          Expanded(
            child: GestureDetector(
              onTap: () => _selectDate(date),
              child: Container(
                height: AppDimensions.calendarCellSize + 8,
                decoration: BoxDecoration(
                  color: isSelected ? c.calendarSelected : Colors.transparent,
                  borderRadius: BorderRadius.circular(
                    AppDimensions.borderRadiusSm,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      constraints: const BoxConstraints.tightFor(
                        width: AppDimensions.calendarCellSize,
                        height: AppDimensions.calendarCellSize,
                      ),
                      decoration: BoxDecoration(
                        color: isToday ? c.accentSubtle : Colors.transparent,
                        borderRadius: BorderRadius.circular(
                          AppDimensions.borderRadius,
                        ),
                        border: isToday
                            ? Border.all(
                                color: c.calendarToday.withValues(alpha: 0.55),
                              )
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$day',
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: isToday
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isToday
                              ? c.calendarToday
                              : isSelected
                              ? c.accent
                              : c.textPrimary,
                        ),
                      ),
                    ),
                    if (hasNotes)
                      Container(
                        width: AppDimensions.calendarDotSize,
                        height: AppDimensions.calendarDotSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.calendarDot,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(children: cells),
        ),
      );
    }
    return rows;
  }

  Widget _buildCollapsedBadge(AppColorsExtension c) {
    final weekdayNames = ['월', '화', '수', '목', '금', '토', '일'];
    final weekdayName = weekdayNames[_selectedDate.weekday - 1];
    final noteCount = _notes.length;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingLg,
        vertical: AppDimensions.spacingMd,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.spacingMd,
              vertical: AppDimensions.spacingSm,
            ),
            decoration: BoxDecoration(
              color: c.calendarSelected,
              borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_selectedDate.day}',
                  style: GoogleFonts.manrope(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: c.accent,
                  ),
                ),
                const SizedBox(width: AppDimensions.spacingSm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      weekdayName,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                    Text(
                      '$noteCount개 노트',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        color: c.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarToggle(AppColorsExtension c) {
    return GestureDetector(
      onTap: () => setState(() => _calendarExpanded = !_calendarExpanded),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: AppDimensions.spacingSm),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _calendarExpanded ? '접기' : '펼치기',
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: c.textMuted,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              _calendarExpanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: c.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateHeader(AppColorsExtension c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.spacingLg,
        AppDimensions.spacingMd,
        AppDimensions.spacingLg,
        AppDimensions.spacingSm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _dayHeaderFmt.format(_selectedDate),
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _createNote,
            icon: Icon(Icons.add_rounded, size: 18, color: c.accent),
            label: Text(
              '새 노트',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.accent,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.spacingMd,
                vertical: AppDimensions.spacingSm,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
                side: BorderSide(color: c.accent.withValues(alpha: 0.3)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteList(AppColorsExtension c) {
    if (_notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.note_alt_outlined, size: 48, color: c.textMuted),
            const SizedBox(height: AppDimensions.spacingMd),
            Text(
              '이 날짜에 노트가 없습니다',
              style: GoogleFonts.manrope(fontSize: 14, color: c.textMuted),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingLg,
        vertical: AppDimensions.spacingSm,
      ),
      itemCount: _notes.length,
      itemBuilder: (context, index) {
        final note = _notes[index];
        return _buildNoteCard(c, note);
      },
    );
  }

  Widget _buildNoteCard(AppColorsExtension c, Note note) {
    final preview = note.content.split('\n').take(2).join('\n').trim();
    final isLocal = note.storageType == StorageType.local;

    return Dismissible(
      key: Key(note.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _deleteNote(note);
        return false; // We handle removal ourselves
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppDimensions.spacingLg),
        decoration: BoxDecoration(
          color: c.error.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppDimensions.cardBorderRadius),
        ),
        child: Icon(Icons.delete_outline_rounded, color: c.error),
      ),
      child: GestureDetector(
        onTap: () => _openEditor(note),
        child: Container(
          margin: const EdgeInsets.only(bottom: AppDimensions.spacingSm),
          padding: const EdgeInsets.all(AppDimensions.spacingMd),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(AppDimensions.cardBorderRadius),
            border: Border.all(color: c.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              if (preview.isNotEmpty) ...[
                const SizedBox(height: AppDimensions.spacingXs),
                Text(
                  preview,
                  style: TextStyle(
                    fontSize: 13,
                    color: c.textSecondary,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (note.tags.isNotEmpty) ...[
                const SizedBox(height: AppDimensions.spacingSm),
                Wrap(
                  spacing: AppDimensions.spacingXs,
                  runSpacing: AppDimensions.spacingXs,
                  children: note.tags
                      .take(AppDimensions.maxVisibleTags)
                      .map((tag) => _buildTagChip(c, tag))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTagChip(AppColorsExtension c, String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.accentSubtle,
        borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
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
  }
}
