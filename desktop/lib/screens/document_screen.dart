import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/note.dart';
import '../search/note_search_index.dart';
import '../search/note_search_query.dart';
import '../search/search_result.dart';
import '../settings/app_settings.dart';
import '../settings/app_settings_controller.dart';
import '../settings/shortcut_binding.dart';
import '../services/anthropic_api_service.dart';
import '../services/claude_code_service.dart';
import '../services/note_service.dart';
import '../services/review_controller.dart';
import '../services/review_outline.dart';
import '../services/review_paths.dart';
import '../services/review_service.dart';
import '../storage/github/github_sync_engine.dart';
import '../storage/github/repo_cache.dart';
import '../storage/note_storage.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';
import '../widgets/calendar_section.dart';
import '../widgets/editor_panel.dart';
import '../widgets/editor_tab_bar.dart';
import '../widgets/note_list_section.dart';
import '../widgets/note_search_section.dart';
import '../widgets/search_filter_panel.dart';
import '../widgets/search_results_panel.dart';
import '../widgets/weekly_view_panel.dart';
import 'settings_screen.dart';

class DocumentScreen extends StatefulWidget {
  final Future<void> Function() onLogout;
  final NoteStorage storage;
  final NoteStorage? localStorage;
  final NoteService noteService;
  final String? avatarUrl;
  final RepoEntry? activeRepo;
  final AppSettingsController settingsController;
  final GitHubSyncEngine? syncEngine;
  final Future<List<RepoEntry>> Function()? loadCachedRepos;
  final Future<void> Function(String path)? onLocalNotePathChanged;
  final ValueChanged<bool>? onSyncEnabledChanged;
  final Future<void> Function(RepoEntry entry)? onRepoSelected;
  final Future<RepoEntry> Function(String name)? onCreateRepo;
  final Future<RepoEntry> Function(String owner, String repo)? onConnectRepo;

  /// Optional notifier that signals when remote data has changed.
  /// Each value change triggers a full reload of notes from storage.
  final ValueNotifier<int>? refreshSignal;

  const DocumentScreen({
    super.key,
    required this.onLogout,
    required this.storage,
    required this.noteService,
    this.localStorage,
    this.avatarUrl,
    this.refreshSignal,
    required this.settingsController,
    this.activeRepo,
    this.syncEngine,
    this.loadCachedRepos,
    this.onLocalNotePathChanged,
    this.onSyncEnabledChanged,
    this.onRepoSelected,
    this.onCreateRepo,
    this.onConnectRepo,
  });

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  // ── State ──
  NoteStorage get _storage => widget.storage;

  /// Returns the appropriate storage for the given note based on its storageType.
  NoteStorage _storageFor(Note note) {
    if (note.storageType == StorageType.local && widget.localStorage != null) {
      return widget.localStorage!;
    }
    return _storage;
  }

  /// Storage wrapper for AI review files (synced store + optional local mirror).
  /// Rebuilt each access so it tracks a changed local path.
  ReviewService get _reviewService =>
      ReviewService(storage: _storage, localStorage: widget.localStorage);

  List<Note> _allNotes = [];
  Note? _selectedNote;

  /// Open editor tabs, in display order, identified by note id. The active tab
  /// is [_selectedNote] (whose id is always present here, unless the list is
  /// empty in which case the editor shows the create screen).
  final List<String> _openTabIds = [];
  static const int _maxTabs = 10;

  /// True once the initial date's note has been auto-opened on first load, so
  /// later reloads never reopen a tab the user deliberately closed.
  bool _didInitialTabOpen = false;

  DateTime _displayedMonth = DateTime.now();
  DateTime? _selectedDate;
  bool _sidebarOpen = true;
  bool _calendarExpanded = true;
  bool _weeklyViewActive = false;
  bool _monthlyViewActive = false;
  bool _memoTabActive = false;
  bool _isLoading = true;
  Timer? _saveDebounce;
  bool _isSyncing = false;
  bool _savePending = false;
  int _currentPage = 0;
  double _sidebarWidth = AppDimensions.sidebarDefaultWidth;
  late final TextEditingController _searchController;
  final FocusNode _searchFocusNode = FocusNode();
  final NoteSearchIndex _searchIndex = NoteSearchIndex();
  final ClaudeCodeService _claudeService = ClaudeCodeService();
  final AnthropicApiService _anthropicService = AnthropicApiService();
  // Owns weekly/monthly review generation state so it survives the weekly panel
  // being closed or another note being opened (background generation).
  final ReviewController _reviewController = ReviewController();
  NoteSearchQuery _searchQuery = const NoteSearchQuery();
  List<SearchResult> _searchResults = [];
  Timer? _searchDebounce;
  final LayerLink _filterLink = LayerLink();
  OverlayEntry? _filterOverlay;
  int _loadGeneration = 0;

  void _handleSettingsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _loadNotes();
    widget.refreshSignal?.addListener(_onRefreshSignal);
    widget.settingsController.addListener(_handleSettingsChanged);
    HardwareKeyboard.instance.addHandler(_handleHardwareKeyEvent);
  }

  @override
  void didUpdateWidget(covariant DocumentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSignal != widget.refreshSignal) {
      oldWidget.refreshSignal?.removeListener(_onRefreshSignal);
      widget.refreshSignal?.addListener(_onRefreshSignal);
    }
    if (oldWidget.settingsController != widget.settingsController) {
      oldWidget.settingsController.removeListener(_handleSettingsChanged);
      widget.settingsController.addListener(_handleSettingsChanged);
    }
    if (oldWidget.storage != widget.storage ||
        oldWidget.localStorage != widget.localStorage) {
      // Immediately remove stale local notes before async reload so the UI
      // never shows notes from the previous local path.
      if (oldWidget.localStorage != widget.localStorage) {
        setState(() {
          _allNotes = _allNotes
              .where((n) => n.storageType != StorageType.local)
              .toList();
          if (_selectedNote?.storageType == StorageType.local) {
            _selectedNote = null;
          }
        });
      }
      unawaited(_loadNotes());
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _searchDebounce?.cancel();
    _filterOverlay?.remove();
    _searchController.dispose();
    _searchFocusNode.dispose();
    widget.refreshSignal?.removeListener(_onRefreshSignal);
    widget.settingsController.removeListener(_handleSettingsChanged);
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeyEvent);
    _reviewController.dispose();
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
        final dirtyNotes = _allNotes.where((n) => n.isDirty).toList();
        for (final note in dirtyNotes) {
          await _storageFor(note).saveNote(note);
          note.isDirty = false;
        }
      }
    }
  }

  Future<void> _loadNotes() async {
    final loadGeneration = ++_loadGeneration;

    // Single call per backend. GitHubNoteStorage.listAllNotes hits the tree
    // endpoint once and fans the missing blob fetches out in parallel via its
    // worker pool — that work used to be serialized day-by-day here. Running
    // synced + local concurrently also halves the wall-clock wait when both
    // are present.
    final now = DateTime.now();
    final futures = <Future<List<Note>>>[
      _storage.listAllNotes(),
      if (widget.localStorage != null) widget.localStorage!.listAllNotes(),
    ];
    final results = await Future.wait(futures);
    final notes = <Note>[
      for (final list in results) ...list,
    ];

    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (!mounted || loadGeneration != _loadGeneration) return;
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

      // Drop tabs whose notes no longer exist (deleted locally or remotely).
      final liveIds = notes.map((n) => n.id).toSet();
      _openTabIds.removeWhere((id) => !liveIds.contains(id));

      // Preserve the active note if it still exists after refresh.
      if (previousSelectedId != null) {
        final match = notes.where((n) => n.id == previousSelectedId);
        _selectedNote = match.isNotEmpty ? match.first : null;
      }

      // First load only: open the selected date's first note in a tab so the
      // app starts with content. Closed tabs are never reopened afterwards.
      if (!_didInitialTabOpen) {
        _didInitialTabOpen = true;
        final dateNotes = _notesForSelectedDate;
        if (dateNotes.isNotEmpty) {
          final first = dateNotes.first;
          if (!_openTabIds.contains(first.id)) _openTabIds.add(first.id);
          _selectedNote = first;
        }
      }

      // Keep the active note consistent with the open tab set.
      if (_selectedNote != null && !_openTabIds.contains(_selectedNote!.id)) {
        _selectedNote = _activeNoteForOpenTabs();
      } else if (_selectedNote == null && _openTabIds.isNotEmpty) {
        _selectedNote = _activeNoteForOpenTabs();
      }
    });

    unawaited(_rebuildSearchIndex());
  }

  /// Resolves an open-tab id to its current [Note], or null if none remain.
  Note? _noteForId(String id) =>
      _allNotes.where((n) => n.id == id).firstOrNull;

  /// The notes backing the currently open tabs, in tab order.
  List<Note> get _openTabNotes {
    final result = <Note>[];
    for (final id in _openTabIds) {
      final note = _noteForId(id);
      if (note != null) result.add(note);
    }
    return result;
  }

  /// Picks a sensible active note from the open tabs (the last one), or null.
  Note? _activeNoteForOpenTabs() {
    for (final id in _openTabIds.reversed) {
      final note = _noteForId(id);
      if (note != null) return note;
    }
    return null;
  }

  /// Opens [note] in a tab and makes it active. Activates the existing tab if
  /// already open; appends a new tab while under [_maxTabs]; otherwise replaces
  /// the active tab so navigation stays within the cap.
  void _openNote(Note note) {
    setState(() {
      _weeklyViewActive = false;
      _monthlyViewActive = false;
      final existing = _openTabIds.indexOf(note.id);
      if (existing == -1) {
        if (_openTabIds.length >= _maxTabs) {
          final activeIndex =
              _selectedNote == null ? -1 : _openTabIds.indexOf(_selectedNote!.id);
          _openTabIds[activeIndex == -1 ? _openTabIds.length - 1 : activeIndex] =
              note.id;
        } else {
          _openTabIds.add(note.id);
        }
      }
      _selectedNote = note;
    });
  }

  /// Activates an already-open tab without moving the calendar date.
  void _activateTab(Note note) {
    if (_selectedNote?.id == note.id) return;
    setState(() => _selectedNote = note);
  }

  /// Closes the tab for [id]. When the active tab is closed, the neighbouring
  /// tab becomes active; closing the last tab returns to the create screen.
  void _closeTab(String id) {
    setState(() {
      final index = _openTabIds.indexOf(id);
      if (index == -1) return;
      _openTabIds.removeAt(index);
      if (_selectedNote?.id == id) {
        if (_openTabIds.isEmpty) {
          _selectedNote = null;
        } else {
          final neighbour = index.clamp(0, _openTabIds.length - 1);
          _selectedNote = _noteForId(_openTabIds[neighbour]);
        }
      }
    });
  }

  bool get _syncEnabled => widget.settingsController.value.syncEnabled;

  bool _canMutateNote(Note note) {
    return note.storageType == StorageType.local || _syncEnabled;
  }

  void _showSyncDisabledMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Derived data ──

  bool get _isSearchActive => !_searchQuery.isEmpty;

  Set<DateTime> get _datesWithNotes {
    return _allNotes
        .map((n) => DateTime(n.noteDate.year, n.noteDate.month, n.noteDate.day))
        .toSet();
  }

  List<Note> get _notesForSelectedDate {
    if (_selectedDate == null) return [];
    return _allNotes.where((n) {
      if (n.isMemo) return false;
      return n.noteDate.year == _selectedDate!.year &&
          n.noteDate.month == _selectedDate!.month &&
          n.noteDate.day == _selectedDate!.day;
    }).toList()..sort((a, b) {
      if (a.isDefault && !b.isDefault) return -1;
      if (!a.isDefault && b.isDefault) return 1;
      return a.createdAt.compareTo(b.createdAt);
    });
  }

  List<Note> get _memoNotes {
    return _allNotes.where((n) => n.isMemo).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  List<Note> get _visibleNotes {
    if (_isSearchActive) return _searchResults.map((r) => r.note).toList();
    if (_memoTabActive) return _memoNotes;
    return _notesForSelectedDate;
  }

  List<Note> get _paginatedNotes {
    final notes = _visibleNotes;
    final start = _currentPage * AppDimensions.notesPerPage;
    final end = (start + AppDimensions.notesPerPage).clamp(0, notes.length);
    if (start >= notes.length) return [];
    return notes.sublist(start, end);
  }

  int get _totalPages {
    final count = _visibleNotes.length;
    return (count / AppDimensions.notesPerPage).ceil().clamp(1, 999);
  }

  DateTime get _weekStart {
    final date = _selectedDate ?? DateTime.now();
    final weekday = date.weekday;
    return DateTime(date.year, date.month, date.day - (weekday - 1));
  }

  List<Note> _weekNotesFor(DateTime weekStart) {
    final end = weekStart.add(const Duration(days: 7));
    return _allNotes.where((n) {
      final d = DateTime(n.noteDate.year, n.noteDate.month, n.noteDate.day);
      return !d.isBefore(weekStart) && d.isBefore(end);
    }).toList()
      ..sort((a, b) {
        final cmp = a.noteDate.compareTo(b.noteDate);
        if (cmp != 0) return cmp;
        return a.createdAt.compareTo(b.createdAt);
      });
  }

  List<Note> get _weekNotes => _weekNotesFor(_weekStart);

  /// First day of the month of the selected date (the monthly review's month).
  DateTime get _monthStart {
    final d = _selectedDate ?? DateTime.now();
    return DateTime(d.year, d.month, 1);
  }

  List<Note> get _monthNotes {
    final start = _monthStart;
    final end = DateTime(start.year, start.month + 1, 1);
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
        _sidebarWidth =
            AppDimensions.sidebarDefaultWidth; // remember for re-open
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
      if (_memoTabActive) {
        _memoTabActive = false;
        _currentPage = 0;
      }
      if (!_weeklyViewActive && !_isSearchActive) {
        _currentPage = 0;
      }
    });
    // When viewing the weekly panel, switching dates may move to another week —
    // load that week's saved review.
    if (_weeklyViewActive) unawaited(_loadWeeklyReview(_weekStart));
    if (_monthlyViewActive) unawaited(_loadMonthlyReview(_monthStart));
    // Date-oriented one-click flow: open the date's default note in a tab.
    // Existing tabs stay open (revisiting a date just re-activates its tab),
    // and an empty date leaves the current tabs untouched — the user creates a
    // note from the list "+". The cap is enforced inside [_openNote].
    if (!_weeklyViewActive && !_isSearchActive) {
      final notes = _notesForSelectedDate;
      if (notes.isNotEmpty) {
        _openNote(notes.first);
      }
    }
  }

  void _onNoteSelected(Note note) {
    // Memos are date-independent quick notes. Selecting one must NOT move the
    // daily calendar date, so switching back to the daily tab restores the
    // date the user was viewing before opening the memo.
    if (!note.isMemo) {
      _selectedDate = DateTime(
        note.noteDate.year,
        note.noteDate.month,
        note.noteDate.day,
      );
    }
    _openNote(note);
  }

  void _onNoteChanged(Note updatedNote) {
    if (!_canMutateNote(updatedNote)) {
      _showSyncDisabledMessage('동기화가 꺼져 있어 현재 동기화 노트는 읽기 전용입니다.');
      return;
    }

    setState(() {
      final idx = _allNotes.indexWhere((n) => n.id == updatedNote.id);
      if (idx != -1) {
        _allNotes[idx] = updatedNote;
        // Only keep it active if it still IS the active tab. A deferred flush of
        // a note the user just switched away from (or closed) must not steal
        // focus back from the now-active tab.
        if (_selectedNote?.id == updatedNote.id) {
          _selectedNote = updatedNote;
        }
      }
    });
    _searchIndex.upsert(updatedNote);
    _applySearchQuery(_searchQuery, resetPage: false);
    // Debounce: 타이핑이 멈춘 후 2초 뒤에 저장하여 커밋 폭주 방지.
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 2), () async {
      if (_isSyncing) {
        _savePending = true;
        return;
      }
      final latest = _allNotes.where((n) => n.id == updatedNote.id).firstOrNull;
      if (latest != null) {
        await _storageFor(latest).saveNote(latest);
        setState(() {
          latest.isDirty = false;
        });
      }
    });
  }

  Future<void> _createNote() async {
    if (_selectedDate == null) return;
    if (!_syncEnabled) {
      _showSyncDisabledMessage('동기화가 꺼져 있어 동기화 노트를 생성할 수 없습니다.');
      return;
    }
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
      _memoTabActive = false;
    });
    _openNote(newNote);
    _searchIndex.upsert(newNote);
    _applySearchQuery(_searchQuery, resetPage: false);
  }

  Future<void> _createLocalNote() async {
    if (_selectedDate == null || widget.localStorage == null) return;
    final now = DateTime.now();
    final newNote = Note(
      id: now.millisecondsSinceEpoch.toString(),
      noteDate: _selectedDate!,
      title: '',
      content: '',
      isDefault: false,
      tags: [],
      createdAt: now,
      updatedAt: now,
      storageType: StorageType.local,
    );
    await widget.localStorage!.saveNote(newNote);
    setState(() {
      _allNotes.add(newNote);
      _memoTabActive = false;
    });
    _openNote(newNote);
    _searchIndex.upsert(newNote);
    _applySearchQuery(_searchQuery, resetPage: false);
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
    if (!_canMutateNote(note)) {
      _showSyncDisabledMessage('동기화가 꺼져 있어 동기화 노트를 삭제할 수 없습니다.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = ctx.colors;
        return AlertDialog(
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
            side: BorderSide(color: c.border),
          ),
          titlePadding: const EdgeInsets.fromLTRB(AppDimensions.spacingLg, 14, AppDimensions.spacingLg, 0),
          contentPadding: const EdgeInsets.fromLTRB(AppDimensions.spacingLg, AppDimensions.spacingSm, AppDimensions.spacingLg, 0),
          actionsPadding: const EdgeInsets.fromLTRB(AppDimensions.spacingMd, AppDimensions.spacingSm, AppDimensions.spacingMd, AppDimensions.spacingMd),
          title: Text(
            '노트 삭제',
            style: Theme.of(ctx).textTheme.titleSmall!.copyWith(fontWeight: FontWeight.w600, color: c.textPrimary),
          ),
          content: Text(
            "'${note.title.isEmpty ? 'Untitled' : note.title}' 노트를 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.",
            style: AppTextStyles.captionThin.copyWith(color: c.textSecondary),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: c.textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: AppTextStyles.captionMedium,
              ),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: c.error,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: AppTextStyles.captionSemibold,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _storageFor(note).deleteNote(note);
      setState(() {
        _allNotes.removeWhere((n) => n.id == note.id);
        final tabIndex = _openTabIds.indexOf(note.id);
        if (tabIndex != -1) _openTabIds.removeAt(tabIndex);
        if (_selectedNote?.id == note.id) {
          // Prefer the neighbouring tab; fall back to the create screen.
          if (_openTabIds.isEmpty) {
            _selectedNote = null;
          } else {
            final neighbour = tabIndex.clamp(0, _openTabIds.length - 1);
            _selectedNote = _noteForId(_openTabIds[neighbour]);
          }
        }
      });
      _searchIndex.remove(note.id);
      _applySearchQuery(_searchQuery, resetPage: false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
      }
    }
  }

  void _toggleWeeklyView() {
    setState(() {
      _weeklyViewActive = !_weeklyViewActive;
      if (_weeklyViewActive) {
        _memoTabActive = false;
        _monthlyViewActive = false;
      }
    });
    if (_weeklyViewActive) unawaited(_loadWeeklyReview(_weekStart));
  }

  /// Loads any saved outline + review for [weekStart] into the controller so the
  /// panel shows both stages. Skips a stage whose generation is already running.
  Future<void> _loadWeeklyReview(DateTime weekStart) async {
    final outline = await _reviewService.loadWeeklyOutline(weekStart);
    final review = await _reviewService.loadWeekly(weekStart);
    if (!mounted) return;
    _reviewController.setLoadedWeeklyOutline(weekStart, outline);
    _reviewController.setLoadedWeeklyReview(weekStart, review);
  }

  /// Formats [notes] as the markdown context fed to the summary model.
  String _buildNotesContext(List<Note> notes) {
    final buffer = StringBuffer();
    for (final note in notes) {
      final date = _formatDate(note.noteDate);
      final title = note.title.trim().isEmpty ? 'Untitled' : note.title.trim();
      buffer.writeln('## $date · $title');
      if (note.tags.isNotEmpty) {
        buffer.writeln('tags: ${note.tags.join(', ')}');
      }
      final content = note.content.trim();
      buffer.writeln(content.isEmpty ? '(내용 없음)' : content);
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  /// Runs one AI pass with [instruction] (system prompt) over [context] using
  /// [model], via the configured provider. Stage 1 (outline) passes a fast model
  /// (Haiku); stage 2 (review) passes the user's model (Sonnet by default). For
  /// the API a low reasoning effort is requested when the model supports it
  /// (Haiku does not). Independent of widget state — safe to keep running in the
  /// background after the panel is closed.
  Future<String> _runSummary(
      AppSettings settings, String instruction, String context,
      {required String model}) {
    if (settings.weeklyProvider == AppSettings.providerCli) {
      return _claudeService.summarizeWeek(
        instruction: instruction,
        notesContext: context,
        cliPath: settings.claudeCliPath,
        model: _cliModelAlias(model),
      );
    }
    return _anthropicService.summarizeWeek(
      apiKey: settings.anthropicApiKey,
      instruction: instruction,
      notesContext: context,
      model: model,
      effort: model.contains('haiku') ? null : 'low',
      onModelFallback: _onModelFallback,
    );
  }

  /// Tells the user once when a configured model was unavailable and the review
  /// was generated on the default model instead. Background-safe (guards mount).
  void _onModelFallback(String requested, String used) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("AI 모델 '$requested'을(를) 사용할 수 없어 기본 모델 '$used'로 생성했습니다."),
      ),
    );
  }

  /// Maps an Anthropic API model id to a Claude Code CLI `--model` alias (the
  /// CLI takes short aliases reliably; full ids vary by release).
  String _cliModelAlias(String apiModel) {
    if (apiModel.contains('haiku')) return 'haiku';
    if (apiModel.contains('sonnet')) return 'sonnet';
    if (apiModel.contains('opus')) return 'opus';
    return apiModel;
  }

  /// Stage 1 (outline): distils the current week's notes into a checkbox list of
  /// key items via the fixed system instruction. Explicit-consent, background.
  void _onGenerateWeeklyOutline() {
    final weekStart = _weekStart;
    final settings = widget.settingsController.value;
    final context = _buildNotesContext(_weekNotes);
    unawaited(_reviewController.generateWeeklyOutline(
      weekStart,
      generate: () => _runSummary(
          settings, AppSettings.weeklyOutlineSystemInstruction, context,
          model: AppSettings.outlineModel),
      persist: (content) => _reviewService.saveWeeklyOutline(weekStart, content),
    ));
  }

  /// Stage 2 (review): runs the user instruction over the checked outline items.
  /// No-op until stage 1 has produced at least one checked item.
  void _onGenerateWeeklyReview() {
    final weekStart = _weekStart;
    final settings = widget.settingsController.value;
    final outline = _reviewController.weekly(weekStart).outline.content;
    if (outline == null) return;
    final checked = checkedItemsText(outline);
    if (checked.trim().isEmpty) return;
    unawaited(_reviewController.generateWeeklyReview(
      weekStart,
      generate: () => _runSummary(settings, settings.weeklyInstruction, checked,
          model: settings.anthropicModel),
      persist: (content) => _reviewService.saveWeekly(weekStart, content),
    ));
  }

  /// Toggles a stage-1 checkbox (by source line index) and persists the outline.
  void _onToggleWeeklyOutlineItem(int lineIndex) {
    final weekStart = _weekStart;
    final outline = _reviewController.weekly(weekStart).outline.content;
    if (outline == null) return;
    final updated = toggleOutlineItem(outline, lineIndex);
    _reviewController.setWeeklyOutlineContent(weekStart, updated);
    unawaited(_reviewService.saveWeeklyOutline(weekStart, updated));
  }

  /// Checks or clears every stage-1 weekly checkbox at once and persists it.
  void _onToggleAllWeeklyOutlineItems(bool checked) {
    final weekStart = _weekStart;
    final outline = _reviewController.weekly(weekStart).outline.content;
    if (outline == null) return;
    final updated = setAllOutlineItems(outline, checked);
    _reviewController.setWeeklyOutlineContent(weekStart, updated);
    unawaited(_reviewService.saveWeeklyOutline(weekStart, updated));
  }

  void _toggleMonthlyView() {
    setState(() {
      _monthlyViewActive = !_monthlyViewActive;
      if (_monthlyViewActive) {
        _memoTabActive = false;
        _weeklyViewActive = false;
      }
    });
    if (_monthlyViewActive) unawaited(_loadMonthlyReview(_monthStart));
  }

  /// Loads any saved outline + review for [month] into the controller so the
  /// panel shows both stages. Skips a stage whose generation is already running.
  Future<void> _loadMonthlyReview(DateTime month) async {
    final outline = await _reviewService.loadMonthlyOutline(month);
    final review = await _reviewService.loadMonthly(month);
    if (!mounted) return;
    _reviewController.setLoadedMonthlyOutline(month, outline);
    _reviewController.setLoadedMonthlyReview(month, review);
  }

  /// Stage 1 (monthly outline): for each week of the month, in parallel, reuse a
  /// saved weekly review or build that week's outline from its notes; combine
  /// the per-week results and distil them into a monthly checkbox outline via
  /// the monthly system instruction. Independent of widget state.
  Future<String> _runMonthlyOutline(
      AppSettings settings, DateTime month) async {
    final weekStarts = weekStartsForMonth(month.year, month.month);
    final perWeek = await Future.wait(weekStarts.map((w) async {
      final existing = await _reviewService.loadWeekly(w);
      if (existing != null && existing.trim().isNotEmpty) return existing;
      final notes = _weekNotesFor(w);
      if (notes.isEmpty) return '';
      try {
        return await _runSummary(settings,
            AppSettings.weeklyOutlineSystemInstruction, _buildNotesContext(notes),
            model: AppSettings.outlineModel);
      } catch (_) {
        return '';
      }
    }));
    final parts = perWeek.where((r) => r.trim().isNotEmpty).toList();
    if (parts.isEmpty) {
      throw Exception('이번 달에 요약할 노트가 없습니다.');
    }
    final buffer = StringBuffer();
    for (var i = 0; i < parts.length; i++) {
      buffer.writeln('## ${i + 1}주차');
      buffer.writeln(parts[i].trim());
      buffer.writeln();
    }
    return _runSummary(settings, AppSettings.monthlyOutlineSystemInstruction,
        buffer.toString().trim(), model: AppSettings.outlineModel);
  }

  /// Stage 1 (outline) for the current month — background, explicit consent.
  void _onGenerateMonthlyOutline() {
    final month = _monthStart;
    final settings = widget.settingsController.value;
    unawaited(_reviewController.generateMonthlyOutline(
      month,
      generate: () => _runMonthlyOutline(settings, month),
      persist: (content) => _reviewService.saveMonthlyOutline(month, content),
    ));
  }

  /// Stage 2 (review): runs the user instruction over the checked monthly
  /// outline items. No-op until stage 1 has at least one checked item.
  void _onGenerateMonthlyReview() {
    final month = _monthStart;
    final settings = widget.settingsController.value;
    final outline = _reviewController.monthly(month).outline.content;
    if (outline == null) return;
    final checked = checkedItemsText(outline);
    if (checked.trim().isEmpty) return;
    unawaited(_reviewController.generateMonthlyReview(
      month,
      generate: () => _runSummary(settings, settings.monthlyInstruction, checked,
          model: settings.anthropicModel),
      persist: (content) => _reviewService.saveMonthly(month, content),
    ));
  }

  /// Toggles a stage-1 monthly checkbox and persists the outline.
  void _onToggleMonthlyOutlineItem(int lineIndex) {
    final month = _monthStart;
    final outline = _reviewController.monthly(month).outline.content;
    if (outline == null) return;
    final updated = toggleOutlineItem(outline, lineIndex);
    _reviewController.setMonthlyOutlineContent(month, updated);
    unawaited(_reviewService.saveMonthlyOutline(month, updated));
  }

  /// Checks or clears every stage-1 monthly checkbox at once and persists it.
  void _onToggleAllMonthlyOutlineItems(bool checked) {
    final month = _monthStart;
    final outline = _reviewController.monthly(month).outline.content;
    if (outline == null) return;
    final updated = setAllOutlineItems(outline, checked);
    _reviewController.setMonthlyOutlineContent(month, updated);
    unawaited(_reviewService.saveMonthlyOutline(month, updated));
  }

  void _onMemoTabChanged(bool active) {
    if (_memoTabActive == active) return;
    setState(() {
      _memoTabActive = active;
      _currentPage = 0;
      if (active) {
        _weeklyViewActive = false;
        _monthlyViewActive = false;
      }
      if (_searchController.text.isNotEmpty || !_searchQuery.isEmpty) {
        _searchController.clear();
        _searchQuery = const NoteSearchQuery();
        _searchResults = [];
      }
      // Switching the daily/memo list filter only changes the sidebar list; the
      // open editor tabs and the active document stay put.
    });
  }

  Future<void> _onMoveToMemo(Note note) async {
    await _setMemoFlag(note, true);
  }

  Future<void> _onMoveToDailyNote(Note note) async {
    await _setMemoFlag(note, false);
  }

  Future<void> _setMemoFlag(Note note, bool isMemo) async {
    if (note.isMemo == isMemo) return;
    if (!_canMutateNote(note)) {
      _showSyncDisabledMessage(
        isMemo
            ? '동기화가 꺼져 있어 동기화 노트를 메모로 이동할 수 없습니다.'
            : '동기화가 꺼져 있어 동기화 노트를 daily로 이동할 수 없습니다.',
      );
      return;
    }
    final updated = note.copyWith(
      isMemo: isMemo,
      updatedAt: DateTime.now(),
    );
    try {
      await _storageFor(updated).saveNote(updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이동 실패: $e')),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      final idx = _allNotes.indexWhere((n) => n.id == updated.id);
      if (idx != -1) {
        _allNotes[idx] = updated;
      }
      if (_selectedNote?.id == updated.id) {
        _selectedNote = updated;
      }
    });
    _searchIndex.upsert(updated);
    _applySearchQuery(_searchQuery, resetPage: false);
  }

  Future<void> _openSettings() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return SettingsScreen(
          settingsController: widget.settingsController,
          activeRepo: widget.activeRepo,
          loadCachedRepos: widget.loadCachedRepos,
          onLocalNotePathChanged: widget.onLocalNotePathChanged,
          onSyncEnabledChanged: widget.onSyncEnabledChanged,
          onRepoSelected: widget.onRepoSelected,
          onCreateRepo: widget.onCreateRepo,
          onConnectRepo: widget.onConnectRepo,
          onSyncIntervalChanged: _applySyncInterval,
        );
      },
    );
  }

  Future<void> _increaseContentScale() async {
    await widget.settingsController.increaseContentScale();
  }

  Future<void> _decreaseContentScale() async {
    await widget.settingsController.decreaseContentScale();
  }

  Future<void> _setContentScale(double scale) async {
    await widget.settingsController.setContentScale(scale);
  }

  void _applySyncInterval(int seconds) {
    widget.syncEngine?.updateInterval(Duration(seconds: seconds));
  }

  Future<void> _rebuildSearchIndex() async {
    if (!mounted) return;
    // _allNotes already reflects everything `_loadNotes` fetched (synced +
    // local + dirty merge). Rebuilding from memory avoids a redundant
    // listAllNotes round-trip on every sync tick.
    _searchIndex.replaceAll(_allNotes);
    if (!mounted) return;
    _applySearchQuery(_searchQuery, resetPage: false);
  }

  void _applySearchQuery(NoteSearchQuery query, {bool resetPage = true}) {
    final contextLines =
        widget.settingsController.value.searchContextLines;
    final results = query.isEmpty
        ? <SearchResult>[]
        : _searchIndex.searchWithContext(query, contextLines: contextLines);

    setState(() {
      _searchQuery = query;
      _searchResults = results;

      if (resetPage) {
        _currentPage = 0;
      }

      final maxPage =
          ((_visibleNotes.length / AppDimensions.notesPerPage).ceil().clamp(
            1,
            999,
          )) -
          1;
      if (_currentPage > maxPage) {
        _currentPage = maxPage;
      }
      // Typing a query never opens or switches editor tabs — the open documents
      // stay put. The user taps a search result to open it in a tab.
    });
    // Keep an open filter popover in sync with the latest query + tag list.
    _filterOverlay?.markNeedsBuild();
  }

  void _onSearchTextChanged(String value) {
    // Debounce typing so the index isn't queried on every keystroke; the field
    // still shows the text immediately via its controller.
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      _applySearchQuery(_searchQuery.copyWith(text: value));
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _closeSearchFilters();
    _applySearchQuery(const NoteSearchQuery());
  }

  void _activateSearch() {
    _searchFocusNode.requestFocus();
  }

  void _onSearchResultTap(SearchResult result) {
    if (!result.note.isMemo) {
      _selectedDate = DateTime(
        result.note.noteDate.year,
        result.note.noteDate.month,
        result.note.noteDate.day,
      );
    }
    _openNote(result.note);
  }

  void _openSearchFilters() {
    if (_filterOverlay != null) {
      _closeSearchFilters();
      return;
    }
    final overlay = Overlay.of(context);
    _filterOverlay = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            // Dismiss when tapping outside the panel.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeSearchFilters,
              ),
            ),
            CompositedTransformFollower(
              link: _filterLink,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, AppDimensions.spacingSm),
              child: SearchFilterPanel(
                query: _searchQuery,
                availableTags: _searchIndex.allTags,
                onChanged: _applySearchQuery,
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_filterOverlay!);
    setState(() {});
  }

  void _closeSearchFilters() {
    _filterOverlay?.remove();
    _filterOverlay = null;
    if (mounted) setState(() {});
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '...';

    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  bool _handleHardwareKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final hw = HardwareKeyboard.instance;
    final isMetaPressed = hw.isMetaPressed;
    final isShiftPressed = hw.isShiftPressed;

    for (final binding in widget.settingsController.bindings) {
      if (binding.matches(
        event,
        isMetaPressed: isMetaPressed,
        isShiftPressed: isShiftPressed,
      )) {
        switch (binding.action) {
          case ShortcutAction.openSettings:
            unawaited(_openSettings());
          case ShortcutAction.zoomIn:
            unawaited(_increaseContentScale());
          case ShortcutAction.zoomOut:
            unawaited(_decreaseContentScale());
          case ShortcutAction.search:
            _activateSearch();
          case ShortcutAction.closeTab:
            final activeId = _selectedNote?.id;
            if (activeId != null) _closeTab(activeId);
        }
        return true;
      }
    }

    // Also handle numpad variants for zoom (not configurable).
    if (isMetaPressed) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.numpadAdd) {
        unawaited(_increaseContentScale());
        return true;
      }
      if (key == LogicalKeyboardKey.numpadSubtract) {
        unawaited(_decreaseContentScale());
        return true;
      }
    }

    return false;
  }

  void _onWeeklyNoteTap(Note note) {
    if (!note.isMemo) {
      _selectedDate = DateTime(
        note.noteDate.year,
        note.noteDate.month,
        note.noteDate.day,
      );
    }
    _openNote(note);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final screenWidth = MediaQuery.of(context).size.width;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: c.scaffold,
        body: Center(child: CircularProgressIndicator(color: c.accent)),
      );
    }

    return Focus(
      autofocus: true,
      child: Scaffold(
        backgroundColor: c.scaffold,
        body: Column(
          children: [
            _buildTitleBar(c),
            Divider(height: 1, color: c.border),
            Expanded(
              child: Row(
                children: [
                  if (_sidebarOpen)
                    SizedBox(
                      width: _clampSidebarWidth(_sidebarWidth, screenWidth),
                      child: _buildSidebarContent(c),
                    ),
                  _ResizeHandle(
                    isVisible: _sidebarOpen,
                    onDragUpdate: (details) =>
                        _onResizeUpdate(details, screenWidth),
                  ),
                  Expanded(child: _buildRightPanel()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightPanel() {
    final selectedNoteIsReadOnly =
        _selectedNote != null && !_canMutateNote(_selectedNote!);

    if (_weeklyViewActive) {
      return WeeklyViewPanel(
        weekStart: _weekStart,
        weekNotes: _weekNotes,
        reviewController: _reviewController,
        onNoteTap: _onWeeklyNoteTap,
        claudeEnabled: widget.settingsController.value.claudeCodeEnabled,
        onGenerateOutline: _onGenerateWeeklyOutline,
        onGenerateReview: _onGenerateWeeklyReview,
        onToggleOutlineItem: _onToggleWeeklyOutlineItem,
        onToggleAllOutlineItems: _onToggleAllWeeklyOutlineItems,
        onOpenSettings: () => unawaited(_openSettings()),
      );
    }

    if (_monthlyViewActive) {
      return MonthlyViewPanel(
        month: _monthStart,
        monthNotes: _monthNotes,
        reviewController: _reviewController,
        onNoteTap: _onWeeklyNoteTap,
        claudeEnabled: widget.settingsController.value.claudeCodeEnabled,
        onGenerateOutline: _onGenerateMonthlyOutline,
        onGenerateReview: _onGenerateMonthlyReview,
        onToggleOutlineItem: _onToggleMonthlyOutlineItem,
        onToggleAllOutlineItems: _onToggleAllMonthlyOutlineItems,
        onOpenSettings: () => unawaited(_openSettings()),
      );
    }

    final editor = EditorPanel(
      note: _selectedNote,
      onNoteChanged: _onNoteChanged,
      selectedDate: _selectedNote == null ? _selectedDate : null,
      onCreateNote: _createNote,
      onCreateLocalNote: widget.localStorage != null ? _createLocalNote : null,
      isReadOnly: selectedNoteIsReadOnly,
      readOnlyReason: selectedNoteIsReadOnly
          ? '동기화가 꺼져 있어 현재 동기화 노트는 읽기 전용입니다.'
          : null,
      contentScale: widget.settingsController.value.contentScale,
      onIncreaseContentScale: _increaseContentScale,
      onDecreaseContentScale: _decreaseContentScale,
      onSetContentScale: _setContentScale,
    );

    final openTabs = _openTabNotes;
    final editorWithTabs = Column(
      // Stretch so the tab bar fills the full width and its tabs align to the
      // left edge (the Column otherwise centers a min-width tab strip).
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (openTabs.isNotEmpty)
          EditorTabBar(
            tabs: openTabs,
            activeNoteId: _selectedNote?.id,
            onSelect: _activateTab,
            onClose: (note) => _closeTab(note.id),
          ),
        Expanded(child: editor),
      ],
    );

    if (!_isSearchActive) return editorWithTabs;

    return Row(
      children: [
        SizedBox(
          width: 320,
          child: SearchResultsPanel(
            results: _searchResults,
            query: _searchQuery.text,
            selectedNoteId: _selectedNote?.id,
            onResultTap: _onSearchResultTap,
          ),
        ),
        VerticalDivider(width: 1, thickness: 1, color: context.colors.border),
        Expanded(child: editorWithTabs),
      ],
    );
  }

  Widget _buildTitleBar(AppColorsExtension c) {
    final avatarUrl = widget.avatarUrl?.trim();
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;

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
            style: Theme.of(context).textTheme.titleSmall!.copyWith(fontWeight: FontWeight.w700, color: c.textPrimary, letterSpacing: -0.3),
          ),
          const Spacer(),
          SizedBox(
            width: 320,
            child: NoteSearchSection(
              controller: _searchController,
              focusNode: _searchFocusNode,
              query: _searchQuery.text,
              hasActiveFilters: _searchQuery.hasFilters,
              filterLink: _filterLink,
              onQueryChanged: _onSearchTextChanged,
              onClear: _clearSearch,
              onOpenFilters: _openSearchFilters,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              Icons.settings_outlined,
              size: 18,
              color: c.textSecondary,
            ),
            onPressed: () => unawaited(_openSettings()),
            tooltip: 'Settings',
            splashRadius: 16,
          ),
          const SizedBox(width: AppDimensions.spacingXs),
          TextButton.icon(
            onPressed: () async => widget.onLogout(),
            icon: const Icon(Icons.logout_rounded, size: 14),
            label: const Text('Logout'),
            style: TextButton.styleFrom(
              foregroundColor: c.textMuted,
              textStyle: Theme.of(context).textTheme.labelSmall!.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: AppDimensions.spacingXs),
          CircleAvatar(
            radius: 16,
            backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
            child: !hasAvatar ? const Icon(Icons.person, size: 16) : null,
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
          _ReviewViewButton(
            icon: Icons.calendar_view_week_rounded,
            label: 'Weekly View',
            isActive: _weeklyViewActive,
            onTap: _toggleWeeklyView,
          ),
          _ReviewViewButton(
            icon: Icons.calendar_month_rounded,
            label: 'Monthly View',
            isActive: _monthlyViewActive,
            onTap: _toggleMonthlyView,
          ),
          Divider(height: 1, color: c.border),
          Expanded(
            child: NoteListSection(
              notes: _paginatedNotes,
              selectedNoteId: (_weeklyViewActive || _monthlyViewActive)
                  ? null
                  : _selectedNote?.id,
              currentPage: _currentPage,
              totalPages: _totalPages,
              totalCount: _visibleNotes.length,
              onNoteSelected: _onNoteSelected,
              onCreateSyncNote: _createNote,
              onCreateLocalNote: widget.localStorage != null
                  ? _createLocalNote
                  : null,
              onPageChanged: (page) => setState(() => _currentPage = page),
              onDeleteNote: _deleteNote,
              memoTabActive: _memoTabActive,
              onMemoTabChanged: _onMemoTabChanged,
              onMoveToMemo: _onMoveToMemo,
              onMoveToDailyNote: _onMoveToDailyNote,
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

  const _ResizeHandle({required this.isVisible, required this.onDragUpdate});

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
          color: _showHighlight ? c.accent.withValues(alpha: 0.5) : c.border,
        ),
      ),
    );
  }
}

/// Weekly view toggle button placed between calendar and note list.
class _ReviewViewButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ReviewViewButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_ReviewViewButton> createState() => _ReviewViewButtonState();
}

class _ReviewViewButtonState extends State<_ReviewViewButton> {
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
                widget.icon,
                size: 14,
                color: widget.isActive ? c.accent : c.textMuted,
              ),
              const SizedBox(width: AppDimensions.spacingSm),
              Text(
                widget.label,
                style: AppTextStyles.microSemibold.copyWith(color: widget.isActive ? c.accent : c.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
