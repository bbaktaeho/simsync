import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/note.dart';
import '../storage/note_storage.dart';

/// Owns the macOS menu bar popover's state and note data.
///
/// It reuses the *same* storage instances as the main window (read lazily via
/// getters so it always tracks the current bundle), so a note created or edited
/// in the popover is persisted through the shared storage and surfaces in the
/// document screen once [onChanged] fires and the app reloads. Kept deliberately
/// separate from DocumentScreen's large state object — the popover is a small,
/// self-contained read/write surface.
class MenuBarController extends ChangeNotifier {
  MenuBarController({
    required NoteStorage? Function() storage,
    required NoteStorage? Function() localStorage,
    required bool Function() syncEnabled,
    required VoidCallback onChanged,
  })  : _storage = storage,
        _localStorage = localStorage,
        _syncEnabled = syncEnabled,
        _onChanged = onChanged;

  /// Nullable: returns null when there is no authenticated storage bundle, so
  /// callers must guard (e.g. after logout the popover cannot read/write).
  final NoteStorage? Function() _storage;
  final NoteStorage? Function() _localStorage;
  final bool Function() _syncEnabled;

  /// Notifies the host that persisted data changed, so the document screen can
  /// reload (typically bumps the shared refresh signal).
  final VoidCallback _onChanged;

  List<Note> _notes = [];
  bool _isLoading = true;
  bool _loading = false;
  DateTime _displayedMonth = _todayMonth();
  DateTime _selectedDate = _today();
  bool _memoTabActive = false;
  Note? _editingNote;
  String? _notice;
  Timer? _saveDebounce;
  Timer? _noticeTimer;

  bool get isLoading => _isLoading;
  DateTime get displayedMonth => _displayedMonth;
  DateTime get selectedDate => _selectedDate;
  bool get memoTabActive => _memoTabActive;
  Note? get editingNote => _editingNote;
  String? get notice => _notice;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime _todayMonth() {
    final n = DateTime.now();
    return DateTime(n.year, n.month);
  }

  Note? _noteById(String id) {
    for (final n in _notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  // ── Derived data ──

  Set<DateTime> get datesWithNotes => _notes
      .map((n) => DateTime(n.noteDate.year, n.noteDate.month, n.noteDate.day))
      .toSet();

  List<Note> get notesForSelectedDate {
    return _notes.where((n) {
      if (n.isMemo) return false;
      return n.noteDate.year == _selectedDate.year &&
          n.noteDate.month == _selectedDate.month &&
          n.noteDate.day == _selectedDate.day;
    }).toList()
      ..sort((a, b) {
        if (a.isDefault && !b.isDefault) return -1;
        if (!a.isDefault && b.isDefault) return 1;
        return a.createdAt.compareTo(b.createdAt);
      });
  }

  List<Note> get memoNotes => _notes.where((n) => n.isMemo).toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  /// The list shown below the calendar for the current tab.
  List<Note> get visibleNotes =>
      _memoTabActive ? memoNotes : notesForSelectedDate;

  // ── Loading ──

  /// Reloads notes from the shared storage. Called each time the popover is
  /// surfaced so it reflects edits made elsewhere.
  Future<void> load() async {
    if (_loading) return;
    final storage = _storage();
    if (storage == null) {
      // No authenticated bundle (e.g. logged out): show an empty panel instead
      // of a perpetual spinner.
      _isLoading = false;
      notifyListeners();
      return;
    }
    _loading = true;
    try {
      final local = _localStorage();
      final futures = <Future<List<Note>>>[
        storage.listAllNotes(),
        if (local != null) local.listAllNotes(),
      ];
      final results = await Future.wait(futures);
      final notes = <Note>[for (final list in results) ...list];

      // Preserve unsaved edits: keep any in-memory dirty note over its stored
      // copy, and re-add dirty notes storage doesn't have yet. Mirrors
      // DocumentScreen._loadNotes so reopening the popover after a blur never
      // discards an in-flight edit whose debounced save hasn't fired.
      final dirtyById = <String, Note>{
        for (final n in _notes)
          if (n.isDirty) n.id: n,
      };
      if (dirtyById.isNotEmpty) {
        for (var i = 0; i < notes.length; i++) {
          final dirty = dirtyById.remove(notes[i].id);
          if (dirty != null) notes[i] = dirty;
        }
        notes.addAll(dirtyById.values);
      }
      notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _notes = notes;

      // Keep the editor bound to the freshest copy of the note it is showing.
      final editing = _editingNote;
      if (editing != null) {
        _editingNote = _noteById(editing.id) ?? editing;
      }
      _isLoading = false;
      notifyListeners();
    } finally {
      _loading = false;
    }
  }

  // ── Navigation ──

  void selectDate(DateTime date) {
    _selectedDate = DateTime(date.year, date.month, date.day);
    _displayedMonth = DateTime(date.year, date.month);
    _memoTabActive = false;
    notifyListeners();
  }

  /// Re-anchors the calendar to *today* (today's month + today selected). Called
  /// when the popover is (re)opened so it always lands on today — and recomputes
  /// "today" in case the app has been running past midnight.
  void resetToToday() {
    _selectedDate = _today();
    _displayedMonth = _todayMonth();
    _memoTabActive = false;
    notifyListeners();
  }

  void previousMonth() {
    _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month - 1);
    notifyListeners();
  }

  void nextMonth() {
    _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month + 1);
    notifyListeners();
  }

  void setMemoTab(bool active) {
    if (_memoTabActive == active) return;
    _memoTabActive = active;
    notifyListeners();
  }

  // ── Editor overlay ──

  void openNote(Note note) {
    _editingNote = note;
    notifyListeners();
  }

  void closeEditor() {
    // Flush any pending save so an edit is never lost when the overlay closes.
    _flushSave();
    _editingNote = null;
    notifyListeners();
  }

  NoteStorage? _storageFor(Note note) {
    final local = _localStorage();
    if (note.storageType == StorageType.local && local != null) return local;
    return _storage();
  }

  /// Creates a synced date note ([memo] = false) or memo ([memo] = true) for the
  /// selected date, persists it, and opens it in the editor overlay. Requires
  /// sync to be enabled — otherwise shows a transient notice.
  Future<void> createNote({required bool memo}) async {
    final storage = _storage();
    if (storage == null) return;
    if (!_syncEnabled()) {
      _showNotice('동기화가 꺼져 있어 추가할 수 없습니다');
      return;
    }
    final now = DateTime.now();
    final isDefault = !memo && notesForSelectedDate.isEmpty;
    final note = Note(
      id: now.millisecondsSinceEpoch.toString(),
      noteDate: _selectedDate,
      title: '',
      content: '',
      isDefault: isDefault,
      tags: [],
      createdAt: now,
      updatedAt: now,
      isMemo: memo,
    );
    try {
      await storage.saveNote(note);
    } catch (e) {
      _showNotice('추가 실패: $e');
      return;
    }
    _notes = [..._notes, note];
    if (memo) _memoTabActive = true;
    _editingNote = note;
    notifyListeners();
    _onChanged();
  }

  /// Applies an in-place edit from the editor and debounces the persistence.
  void updateNote(Note updated) {
    // Mark dirty so a reload racing the debounce (reopen after blur) preserves
    // the edit instead of overwriting it with the stored copy.
    updated.isDirty = true;
    final idx = _notes.indexWhere((n) => n.id == updated.id);
    if (idx != -1) _notes[idx] = updated;
    if (_editingNote?.id == updated.id) _editingNote = updated;
    notifyListeners();
    _saveDebounce?.cancel();
    _saveDebounce =
        Timer(const Duration(seconds: 1), () => unawaited(_persist(updated.id)));
  }

  Future<void> _persist(String id) async {
    final note = _noteById(id);
    if (note == null) return;
    final storage = _storageFor(note);
    if (storage == null) return;
    try {
      await storage.saveNote(note);
      note.isDirty = false;
      _onChanged();
    } catch (_) {
      // Leave it dirty; a later edit or close will retry.
    }
  }

  void _flushSave() {
    if (_saveDebounce?.isActive ?? false) {
      _saveDebounce!.cancel();
      final editing = _editingNote;
      if (editing != null) unawaited(_persist(editing.id));
    }
  }

  void _showNotice(String message) {
    _notice = message;
    notifyListeners();
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 3), () {
      _notice = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _noticeTimer?.cancel();
    super.dispose();
  }
}
