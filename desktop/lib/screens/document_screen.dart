import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../models/note.dart';
import '../services/note_service.dart';
import '../storage/note_storage.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../widgets/calendar_section.dart';
import '../widgets/editor_panel.dart';
import '../widgets/note_list_section.dart';
import '../widgets/weekly_view_panel.dart';

class DocumentScreen extends StatefulWidget {
  final Future<void> Function() onLogout;
  final NoteStorage storage;
  final NoteService noteService;
  final String? avatarUrl;

  /// Optional notifier that signals when remote data has changed.
  /// Each value change triggers a full reload of notes from storage.
  final ValueNotifier<int>? refreshSignal;

  const DocumentScreen({
    super.key,
    required this.onLogout,
    required this.storage,
    required this.noteService,
    this.avatarUrl,
    this.refreshSignal,
  });

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  // ── State ──
  NoteStorage get _storage => widget.storage;
  NoteService get _noteService => widget.noteService;
  List<Note> _allNotes = [];
  Note? _selectedNote;
  DateTime _displayedMonth = DateTime.now();
  DateTime? _selectedDate;
  bool _sidebarOpen = true;
  bool _calendarExpanded = true;
  bool _weeklyViewActive = false;
  bool _isLoading = true;
  Timer? _saveDebounce;
  bool _isSyncing = false;
  bool _savePending = false;
  int _currentPage = 0;
  double _sidebarWidth = AppDimensions.sidebarDefaultWidth;

  @override
  void initState() {
    super.initState();
    _loadNotes();
    widget.refreshSignal?.addListener(_onRefreshSignal);
  }

  @override
  void didUpdateWidget(covariant DocumentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSignal != widget.refreshSignal) {
      oldWidget.refreshSignal?.removeListener(_onRefreshSignal);
      widget.refreshSignal?.addListener(_onRefreshSignal);
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    widget.refreshSignal?.removeListener(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      await _loadNotes();
    } finally {
      _isSyncing = false;
      if (_savePending) {
        _savePending = false;
        for (final note in _allNotes) {
          if (note.isDirty) {
            await _storage.saveNote(note);
            note.isDirty = false;
          }
        }
      }
    }
  }

  Future<void> _loadNotes() async {
    // Load all notes from storage (GitHub or local, depending on wiring).
    final now = DateTime.now();
    final currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final dates = await _storage.listDates(currentMonth);
    final notes = <Note>[];
    for (final date in dates) {
      final dayNotes = await _storage.listNotes(date);
      notes.addAll(dayNotes);
    }
    // Also load previous month if we're in the first week.
    if (now.day <= 7) {
      final prev = DateTime(now.year, now.month - 1);
      final prevMonth = '${prev.year}-${prev.month.toString().padLeft(2, '0')}';
      final prevDates = await _storage.listDates(prevMonth);
      for (final date in prevDates) {
        final dayNotes = await _storage.listNotes(date);
        notes.addAll(dayNotes);
      }
    }
    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (!mounted) return;
    final previousSelectedId = _selectedNote?.id;

    // Merge remote notes with local dirty notes to prevent overwriting
    // unsaved edits during sync.
    final dirtyById = <String, Note>{};
    for (final local in _allNotes) {
      if (local.isDirty) {
        dirtyById[local.id] = local;
      }
    }
    if (dirtyById.isNotEmpty) {
      // For each remote note, keep local version if it has unsaved edits.
      for (var i = 0; i < notes.length; i++) {
        final dirty = dirtyById.remove(notes[i].id);
        if (dirty != null) {
          notes[i] = dirty;
        }
      }
      // Keep dirty notes that don't exist on remote yet (newly created).
      notes.addAll(dirtyById.values);
      notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }

    setState(() {
      _allNotes = notes;
      _isLoading = false;
      _selectedDate ??= DateTime(now.year, now.month, now.day);
      // Preserve selected note if it still exists after refresh.
      if (previousSelectedId != null) {
        final match = notes.where((n) => n.id == previousSelectedId);
        _selectedNote = match.isNotEmpty ? match.first : null;
      }
      if (_selectedNote == null) {
        final todayNotes = _notesForSelectedDate;
        if (todayNotes.isNotEmpty) {
          _selectedNote = todayNotes.first;
        }
      }
    });
  }

  // ── Derived data ──

  Set<DateTime> get _datesWithNotes {
    return _allNotes
        .map((n) => DateTime(n.noteDate.year, n.noteDate.month, n.noteDate.day))
        .toSet();
  }

  List<Note> get _notesForSelectedDate {
    if (_selectedDate == null) return [];
    return _allNotes.where((n) {
      return n.noteDate.year == _selectedDate!.year &&
          n.noteDate.month == _selectedDate!.month &&
          n.noteDate.day == _selectedDate!.day;
    }).toList()
      ..sort((a, b) {
        if (a.isDefault && !b.isDefault) return -1;
        if (!a.isDefault && b.isDefault) return 1;
        return a.createdAt.compareTo(b.createdAt);
      });
  }

  List<Note> get _paginatedNotes {
    final notes = _notesForSelectedDate;
    final start = _currentPage * AppDimensions.notesPerPage;
    final end = (start + AppDimensions.notesPerPage).clamp(0, notes.length);
    if (start >= notes.length) return [];
    return notes.sublist(start, end);
  }

  int get _totalPages {
    final count = _notesForSelectedDate.length;
    return (count / AppDimensions.notesPerPage).ceil().clamp(1, 999);
  }

  DateTime get _weekStart {
    final date = _selectedDate ?? DateTime.now();
    final weekday = date.weekday;
    return DateTime(date.year, date.month, date.day - (weekday - 1));
  }

  List<Note> get _weekNotes {
    final start = _weekStart;
    final end = start.add(const Duration(days: 7));
    return _allNotes.where((n) {
      final d = DateTime(n.noteDate.year, n.noteDate.month, n.noteDate.day);
      return !d.isBefore(start) && d.isBefore(end);
    }).toList()
      ..sort((a, b) {
        final cmp = a.noteDate.compareTo(b.noteDate);
        if (cmp != 0) return cmp;
        return a.createdAt.compareTo(b.createdAt);
      });
  }

  // ── Sidebar resize ──

  double _clampSidebarWidth(double width, double screenWidth) {
    final maxWidth = screenWidth * AppDimensions.sidebarMaxRatio;
    return width.clamp(0.0, maxWidth);
  }

  void _onResizeUpdate(DragUpdateDetails details, double screenWidth) {
    setState(() {
      final newWidth = _sidebarWidth + details.delta.dx;
      final maxWidth = screenWidth * AppDimensions.sidebarMaxRatio;

      if (newWidth < AppDimensions.sidebarCollapseThreshold) {
        // Auto-collapse
        _sidebarOpen = false;
        _sidebarWidth = AppDimensions.sidebarDefaultWidth; // remember for re-open
      } else {
        _sidebarOpen = true;
        _sidebarWidth = newWidth.clamp(AppDimensions.sidebarMinWidth, maxWidth);
      }
    });
  }

  void _toggleSidebar() {
    setState(() {
      _sidebarOpen = !_sidebarOpen;
      if (_sidebarOpen && _sidebarWidth < AppDimensions.sidebarMinWidth) {
        _sidebarWidth = AppDimensions.sidebarDefaultWidth;
      }
    });
  }

  // ── Actions ──

  void _onDateSelected(DateTime date) {
    setState(() {
      _selectedDate = date;
      _currentPage = 0;
      if (!_weeklyViewActive) {
        final notes = _notesForSelectedDate;
        _selectedNote = notes.isNotEmpty ? notes.first : null;
      }
    });
  }

  void _onNoteSelected(Note note) {
    setState(() {
      _selectedNote = note;
      _weeklyViewActive = false;
    });
  }

  void _onNoteChanged(Note updatedNote) {
    setState(() {
      final idx = _allNotes.indexWhere((n) => n.id == updatedNote.id);
      if (idx != -1) {
        _allNotes[idx] = updatedNote;
        _selectedNote = updatedNote;
      }
    });
    // Debounce: 타이핑이 멈춘 후 2초 뒤에 저장하여 커밋 폭주 방지.
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 2), () async {
      if (_isSyncing) {
        _savePending = true;
        return;
      }
      await _storage.saveNote(updatedNote);
    });
  }

  Future<void> _createNote() async {
    if (_selectedDate == null) return;
    final existingNotes = _notesForSelectedDate;
    final isDefault = existingNotes.isEmpty;
    final now = DateTime.now();
    final newNote = Note(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      noteDate: _selectedDate!,
      title: '',
      content: '',
      isDefault: isDefault,
      tags: [],
      createdAt: now,
      updatedAt: now,
    );
    await _storage.saveNote(newNote);
    setState(() {
      _allNotes.add(newNote);
      _selectedNote = newNote;
      _weeklyViewActive = false;
    });
  }

  void _previousMonth() {
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month - 1,
      );
    });
  }

  void _nextMonth() {
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month + 1,
      );
    });
  }

  Future<void> _deleteNote(Note note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = ctx.colors;
        return AlertDialog(
          backgroundColor: c.surface,
          title: Text('노트 삭제',
              style: TextStyle(color: c.textPrimary, fontSize: 16)),
          content: Text(
            "'${note.title.isEmpty ? 'Untitled' : note.title}' 노트를 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.",
            style: TextStyle(color: c.textSecondary, fontSize: 13),
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
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _storage.deleteNote(note);
      setState(() {
        _allNotes.removeWhere((n) => n.id == note.id);
        if (_selectedNote?.id == note.id) {
          final remaining = _notesForSelectedDate;
          _selectedNote = remaining.isNotEmpty ? remaining.first : null;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 실패: $e')),
        );
      }
    }
  }

  void _toggleWeeklyView() {
    setState(() => _weeklyViewActive = !_weeklyViewActive);
  }

  void _onWeeklyNoteTap(Note note) {
    setState(() {
      _selectedNote = note;
      _selectedDate = DateTime(
        note.noteDate.year,
        note.noteDate.month,
        note.noteDate.day,
      );
      _weeklyViewActive = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final screenWidth = MediaQuery.of(context).size.width;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: c.scaffold,
        body: Center(
          child: CircularProgressIndicator(color: c.accent),
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.scaffold,
      body: Column(
        children: [
          _buildTitleBar(c),
          Divider(height: 1, color: c.border),
          Expanded(
            child: Row(
              children: [
                // Sidebar
                if (_sidebarOpen)
                  SizedBox(
                    width: _clampSidebarWidth(_sidebarWidth, screenWidth),
                    child: _buildSidebarContent(c),
                  ),
                // Resize handle
                _ResizeHandle(
                  isVisible: _sidebarOpen,
                  onDragUpdate: (details) =>
                      _onResizeUpdate(details, screenWidth),
                ),
                // Right panel
                Expanded(child: _buildRightPanel()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel() {
    if (_weeklyViewActive) {
      return WeeklyViewPanel(
        weekStart: _weekStart,
        weekNotes: _weekNotes,
        onNoteTap: _onWeeklyNoteTap,
      );
    }
    return EditorPanel(
      note: _selectedNote,
      onNoteChanged: _onNoteChanged,
      selectedDate: _selectedNote == null ? _selectedDate : null,
      onCreateNote: _createNote,
    );
  }

  Widget _buildTitleBar(AppColorsExtension c) {
    final isDark = SimSyncApp.of(context).themeMode == ThemeMode.dark;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingMd),
      color: c.surface,
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              _sidebarOpen ? Icons.menu_open_rounded : Icons.menu_rounded,
              size: 18,
              color: _sidebarOpen ? c.accent : c.textSecondary,
            ),
            onPressed: _toggleSidebar,
            tooltip: _sidebarOpen ? 'Hide sidebar' : 'Show sidebar',
            splashRadius: 16,
          ),
          const SizedBox(width: AppDimensions.spacingSm),
          Text(
            'SimSync',
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              size: 18,
              color: c.textSecondary,
            ),
            onPressed: () => SimSyncApp.of(context).toggleTheme(),
            tooltip: isDark ? 'Light mode' : 'Dark mode',
            splashRadius: 16,
          ),
          const SizedBox(width: AppDimensions.spacingXs),
          TextButton.icon(
            onPressed: () async => widget.onLogout(),
            icon: const Icon(Icons.logout_rounded, size: 14),
            label: const Text('Logout'),
            style: TextButton.styleFrom(
              foregroundColor: c.textMuted,
              textStyle: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: AppDimensions.spacingXs),
          CircleAvatar(
            radius: 16,
            backgroundImage: widget.avatarUrl != null
                ? NetworkImage(widget.avatarUrl!)
                : null,
            child: widget.avatarUrl == null
                ? const Icon(Icons.person, size: 16)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarContent(AppColorsExtension c) {
    return Container(
      color: c.surface,
      child: Column(
        children: [
          CalendarSection(
            displayedMonth: _displayedMonth,
            selectedDate: _selectedDate,
            datesWithNotes: _datesWithNotes,
            isExpanded: _calendarExpanded,
            onToggleExpand: () =>
                setState(() => _calendarExpanded = !_calendarExpanded),
            onDateSelected: _onDateSelected,
            onPreviousMonth: _previousMonth,
            onNextMonth: _nextMonth,
          ),
          _WeeklyViewButton(
            isActive: _weeklyViewActive,
            onTap: _toggleWeeklyView,
          ),
          Divider(height: 1, color: c.border),
          Expanded(
            child: NoteListSection(
              notes: _paginatedNotes,
              selectedNoteId: _weeklyViewActive ? null : _selectedNote?.id,
              currentPage: _currentPage,
              totalPages: _totalPages,
              totalCount: _notesForSelectedDate.length,
              onNoteSelected: _onNoteSelected,
              onCreateNote: _createNote,
              onPageChanged: (page) => setState(() => _currentPage = page),
              onDeleteNote: _deleteNote,
            ),
          ),
        ],
      ),
    );
  }
}

/// Draggable handle between sidebar and editor for resizing.
class _ResizeHandle extends StatefulWidget {
  final bool isVisible;
  final ValueChanged<DragUpdateDetails> onDragUpdate;

  const _ResizeHandle({
    required this.isVisible,
    required this.onDragUpdate,
  });

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _isHovered = false;
  bool _isDragging = false;

  bool get _showHighlight => _isHovered || _isDragging;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onHorizontalDragStart: (_) => setState(() => _isDragging = true),
        onHorizontalDragUpdate: widget.onDragUpdate,
        onHorizontalDragEnd: (_) => setState(() => _isDragging = false),
        child: AnimatedContainer(
          duration: AppDimensions.animFast,
          width: AppDimensions.resizeHandleWidth,
          color: _showHighlight
              ? c.accent.withValues(alpha: 0.5)
              : c.border,
        ),
      ),
    );
  }
}

/// Weekly view toggle button placed between calendar and note list.
class _WeeklyViewButton extends StatefulWidget {
  final bool isActive;
  final VoidCallback onTap;

  const _WeeklyViewButton({required this.isActive, required this.onTap});

  @override
  State<_WeeklyViewButton> createState() => _WeeklyViewButtonState();
}

class _WeeklyViewButtonState extends State<_WeeklyViewButton> {
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
          margin: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingMd,
            vertical: AppDimensions.spacingSm,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingMd,
            vertical: AppDimensions.spacingSm,
          ),
          decoration: BoxDecoration(
            color: widget.isActive
                ? c.accentMuted
                : _isHovered
                    ? c.surfaceHover
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
            border: Border.all(
              color: widget.isActive
                  ? c.accent.withValues(alpha: 0.4)
                  : _isHovered
                      ? c.border
                      : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.calendar_view_week_rounded,
                size: 14,
                color: widget.isActive ? c.accent : c.textMuted,
              ),
              const SizedBox(width: AppDimensions.spacingSm),
              Text(
                'Weekly View',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: widget.isActive ? c.accent : c.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
