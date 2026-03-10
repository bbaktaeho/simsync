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
    widget.refreshSignal?.removeListener(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() {
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    final notes = await _noteService.loadAllNotes();
    if (!mounted) return;
    final now = DateTime.now();
    final previousSelectedId = _selectedNote?.id;
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
    _storage.saveNote(updatedNote);
  }

  Future<void> _createNote() async {
    if (_selectedDate == null) return;
    final existingNotes = _notesForSelectedDate;
    final isDefault = existingNotes.isEmpty;
    final newNote = await _noteService.createNote(
      noteDate: _selectedDate!,
      isDefault: isDefault,
    );
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
