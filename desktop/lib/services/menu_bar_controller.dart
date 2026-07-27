import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/note.dart';
import '../storage/note_storage.dart';
import 'note_conversion.dart';
import 'note_merge.dart';

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
      // copy, and re-add dirty notes storage doesn't have yet — so reopening
      // the popover after a blur never discards an in-flight edit whose
      // debounced save hasn't fired.
      mergeDirtyNotes(loaded: notes, current: _notes);
      notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _notes = notes;

      // Keep the editor bound to the freshest copy of the note it is showing.
      final editing = _editingNote;
      if (editing != null) {
        _editingNote = _noteById(editing.id) ?? editing;
      }
      _isLoading = false;
      notifyListeners();
    } catch (_) {
      // Offline / API failure: keep whatever list we have instead of an
      // eternal spinner, and let the user retry by reopening.
      _isLoading = false;
      _showNotice('노트를 불러오지 못했습니다');
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

  /// [note]가 저장되는 스토리지 (로컬 노트면 로컬, 아니면 synced).
  /// 이미지 자산 입출력 등 패널 쪽 와이어링에도 쓰인다.
  NoteStorage? storageFor(Note note) {
    final local = _localStorage();
    if (note.storageType == StorageType.local && local != null) return local;
    return _storage();
  }

  /// 현재 synced 스토리지 (없으면 null). 디스크 캐시 사용 여부 판단용.
  NoteStorage? get syncedStorage => _storage();

  /// 로컬 스토리지가 연결되어 있는지. 추가/전환 메뉴의 로컬 항목 노출 여부.
  bool get hasLocalStorage => _localStorage() != null;

  /// Creates a note ([memo] = false) or memo ([memo] = true) for the selected
  /// date, persists it, and opens it in the editor overlay. [local] = true 면
  /// 로컬 스토리지에 만들고 (동기화 불필요), 아니면 synced에 만든다 — synced 는
  /// sync가 켜져 있어야 하며 아니면 transient notice를 띄운다.
  Future<void> createNote({required bool memo, bool local = false}) async {
    final storage = local ? _localStorage() : _storage();
    if (storage == null) return;
    if (!local && !_syncEnabled()) {
      _showNotice('동기화가 꺼져 있어 추가할 수 없습니다');
      return;
    }
    final now = DateTime.now();
    // 날짜의 첫 synced 노트만 기본 노트가 된다 (메인 창과 같은 규칙 —
    // 로컬 노트와 메모는 기본 노트가 되지 않는다).
    final isDefault = !local && !memo && notesForSelectedDate.isEmpty;
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
      storageType: local ? StorageType.local : StorageType.synced,
    );
    try {
      await storage.saveNote(note);
    } catch (e) {
      _showNotice('추가 실패: $e');
      return;
    }
    _notes = [..._notes, note];
    _memoTabActive = memo;
    _editingNote = note;
    notifyListeners();
    _onChanged();
  }

  /// 노트를 스토리지에서 삭제한다. 동기화 노트는 GitHub 삭제가 필요하므로
  /// sync가 켜져 있어야 한다. 삭제된 노트를 편집 중이었다면 오버레이를 닫는다.
  Future<void> deleteNote(Note note) async {
    if (note.storageType != StorageType.local && !_syncEnabled()) {
      _showNotice('동기화가 꺼져 있어 삭제할 수 없습니다');
      return;
    }
    final storage = storageFor(note);
    if (storage == null) return;
    // 제목 변경이 디바운스 저장 대기 중이면 파일 경로(제목 유래)가 어긋나
    // 삭제가 조용히 빗나간다 — 먼저 flush해 rename을 확정한다.
    await flushPendingSaves();
    try {
      await storage.deleteNote(note);
    } catch (e) {
      _showNotice('삭제 실패: $e');
      return;
    }
    _notes = _notes.where((n) => n.id != note.id).toList();
    if (_editingNote?.id == note.id) _editingNote = null;
    notifyListeners();
    _onChanged();
  }

  /// 노트를 로컬↔동기화 스토리지 간 전환한다 (방향은 현재 storageType 반대).
  /// 메인 창과 같은 규칙: 양방향 모두 GitHub 쓰기/삭제가 필요하므로 sync가
  /// 켜져 있어야 한다. 전환 전에 진행 중인 저장을 flush해 원본 스토리지로
  /// 다시 쓰이는 레이스를 막는다.
  Future<void> convertNote(Note note) async {
    final synced = _storage();
    final local = _localStorage();
    if (synced == null || local == null) return;
    if (!_syncEnabled()) {
      _showNotice('동기화가 꺼져 있어 전환할 수 없습니다');
      return;
    }
    await flushPendingSaves();
    // flush 후 최신 내용으로 전환한다.
    final current = _noteById(note.id) ?? note;

    NoteConversionResult result;
    try {
      result = current.storageType == StorageType.local
          ? await convertLocalNoteToSynced(
              note: current, local: local, synced: synced)
          : await convertSyncedNoteToLocal(
              note: current, synced: synced, local: local);
    } catch (e) {
      _showNotice('전환 실패: $e');
      return;
    }
    final idx = _notes.indexWhere((n) => n.id == result.note.id);
    if (idx != -1) _notes[idx] = result.note;
    if (_editingNote?.id == result.note.id) _editingNote = result.note;
    final label =
        result.note.storageType == StorageType.local ? '로컬' : '동기화';
    _showNotice(result.failedAssets.isEmpty
        ? '$label 노트로 전환했습니다'
        : '$label 노트로 전환했습니다 (이미지 ${result.failedAssets.length}개 재첨부 필요)');
    _onChanged();
  }

  /// 메모 ↔ daily 이동. 동기화 노트는 sync가 켜져 있어야 한다.
  Future<void> setMemo(Note note, bool isMemo) async {
    if (note.isMemo == isMemo) return;
    if (note.storageType != StorageType.local && !_syncEnabled()) {
      _showNotice('동기화가 꺼져 있어 이동할 수 없습니다');
      return;
    }
    final storage = storageFor(note);
    if (storage == null) return;
    final updated = note.copyWith(isMemo: isMemo, updatedAt: DateTime.now());
    try {
      await storage.saveNote(updated);
    } catch (e) {
      _showNotice('이동 실패: $e');
      return;
    }
    final idx = _notes.indexWhere((n) => n.id == updated.id);
    if (idx != -1) _notes[idx] = updated;
    if (_editingNote?.id == updated.id) _editingNote = updated;
    notifyListeners();
    _onChanged();
  }

  /// Applies an in-place edit from the editor and debounces the persistence.
  void updateNote(Note updated) {
    // Same rule as DocumentScreen._canMutateNote: with sync off, synced notes
    // are read-only everywhere — a popover edit would otherwise still commit
    // to GitHub. (The editor is also rendered read-only; this guards the API.)
    if (updated.storageType != StorageType.local && !_syncEnabled()) {
      _showNotice('동기화가 꺼져 있어 동기화 노트는 읽기 전용입니다');
      return;
    }
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
    final storage = storageFor(note);
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
    unawaited(flushPendingSaves());
  }

  /// Cancels the save debounce and awaits the persistence of the note being
  /// edited. Awaitable so the quit path can hold process exit until the last
  /// edit is committed.
  Future<void> flushPendingSaves() async {
    if (_saveDebounce?.isActive ?? false) {
      _saveDebounce!.cancel();
      final editing = _editingNote;
      if (editing != null) await _persist(editing.id);
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
