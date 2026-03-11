# SimSync 개선 및 기능 추가 구현 계획

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 마크다운 프리뷰 개선, 동기화 버그 수정, 노트 삭제, 로컬 전용 노트 기능을 구현한다.

**Architecture:** 기존 `NoteStorage` 인터페이스를 재사용하여 `LocalNoteStorage`를 추가하고, `StorageBundle`을 확장한다. 마크다운은 `flutter_highlight`를 code block builder로 연결한다. 동기화 보호는 dirty flag + mutex lock 패턴을 적용한다.

**Tech Stack:** Flutter, flutter_markdown, flutter_highlight, file_picker, shared_preferences, path_provider

---

## Task 1: 마크다운 코드 하이라이팅

**Files:**
- Modify: `desktop/pubspec.yaml`
- Modify: `desktop/lib/widgets/markdown_preview.dart`

**Step 1: flutter_highlight 의존성 추가**

`desktop/pubspec.yaml`의 dependencies에 추가:

```yaml
  flutter_highlight: ^0.7.0
  highlight: ^0.7.0
```

**Step 2: pub get 실행**

Run: `cd desktop && flutter pub get`
Expected: 의존성 설치 성공

**Step 3: 코드 블록 빌더 구현**

`desktop/lib/widgets/markdown_preview.dart`를 수정한다.

기존 import 아래에 추가:
```dart
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/github-dark.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
```

`MarkdownPreviewWidget` 클래스에 code block builder를 추가:

```dart
class _CodeBlockBuilder extends MarkdownElementBuilder {
  final bool isDark;
  final AppColorsExtension colors;

  _CodeBlockBuilder({required this.isDark, required this.colors});

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    // Extract language from fence info string
    String? language;
    if (element.attributes['class'] != null) {
      language = element.attributes['class']!.replaceFirst('language-', '');
    }

    final code = element.textContent.trimRight();
    final theme = isDark ? githubDarkTheme : githubTheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surfaceLight,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(12),
      child: HighlightView(
        code,
        language: language ?? 'plaintext',
        theme: theme,
        padding: EdgeInsets.zero,
        textStyle: GoogleFonts.jetBrainsMono(fontSize: 13, height: 1.5),
      ),
    );
  }
}
```

`Markdown` 위젯에 builders를 추가:

```dart
return Markdown(
  data: content,
  selectable: true,
  padding: EdgeInsets.zero,
  styleSheet: _buildStyleSheet(c),
  builders: {
    'pre': _CodeBlockBuilder(isDark: isDark, colors: c),
  },
);
```

`isDark`는 빌드 시 `Theme.of(context).brightness == Brightness.dark`로 판단한다.

**Step 4: flutter analyze 실행**

Run: `cd desktop && flutter analyze`
Expected: No issues found

**Step 5: 커밋**

```bash
git add desktop/pubspec.yaml desktop/lib/widgets/markdown_preview.dart
git commit -m "feat: add syntax highlighting to markdown code blocks"
```

---

## Task 2: 마크다운 헤더 간격 개선

**Files:**
- Modify: `desktop/lib/widgets/markdown_preview.dart`

**Step 1: MarkdownStyleSheet 헤더 패딩 수정**

`_buildStyleSheet` 메서드에서 기존 h1~h4 스타일에 패딩을 추가한다. `MarkdownStyleSheet`의 `h1Padding`, `h2Padding` 등을 활용한다.

```dart
MarkdownStyleSheet(
  // 기존 h1~h4 스타일 유지
  h1Padding: const EdgeInsets.only(top: 24, bottom: 16),
  h2Padding: const EdgeInsets.only(top: 24, bottom: 16),
  h3Padding: const EdgeInsets.only(top: 24, bottom: 16),
  h4Padding: const EdgeInsets.only(top: 16, bottom: 8),
  // H1, H2 하단 divider
  h1: GoogleFonts.manrope(
    fontSize: 26, fontWeight: FontWeight.w700, color: c.textPrimary, height: 1.4,
    decoration: TextDecoration.none,
  ),
  h2: GoogleFonts.manrope(
    fontSize: 21, fontWeight: FontWeight.w600, color: c.textPrimary, height: 1.4,
    decoration: TextDecoration.none,
  ),
  // ... 나머지 기존 스타일 유지
)
```

H1/H2의 하단 divider는 `MarkdownStyleSheet`에서 직접 지원하지 않으므로, `blockSpacing`을 적절히 조정하거나 heading builder를 커스텀으로 작성한다.

H1/H2 divider 구현 방법:
```dart
class _HeadingBuilder extends MarkdownElementBuilder {
  final AppColorsExtension colors;
  final TextStyle style;

  _HeadingBuilder({required this.colors, required this.style});

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border, width: 1)),
      ),
      child: SelectableText(
        element.textContent,
        style: style,
      ),
    );
  }
}
```

builders에 추가:
```dart
builders: {
  'pre': _CodeBlockBuilder(isDark: isDark, colors: c),
  'h1': _HeadingBuilder(colors: c, style: h1Style),
  'h2': _HeadingBuilder(colors: c, style: h2Style),
},
```

**Step 2: flutter analyze 실행**

Run: `cd desktop && flutter analyze`
Expected: No issues found

**Step 3: 커밋**

```bash
git add desktop/lib/widgets/markdown_preview.dart
git commit -m "feat: improve markdown heading spacing with GitHub-style dividers"
```

---

## Task 3: 동기화 버그 수정 — Dirty Flag 보호

**Files:**
- Modify: `desktop/lib/models/note.dart`
- Modify: `desktop/lib/widgets/editor_panel.dart`
- Modify: `desktop/lib/screens/document_screen.dart`

**Step 1: Note 모델에 isDirty 추가**

`desktop/lib/models/note.dart`에 런타임 전용 필드 추가:

```dart
class Note {
  // 기존 필드 유지...

  /// Runtime-only flag: true when local edits exist that haven't been saved to storage.
  /// Not serialized.
  bool isDirty;

  Note({
    required this.id,
    required this.noteDate,
    required this.title,
    required this.content,
    required this.isDefault,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
    this.isDirty = false,
  });

  Note copyWith({
    String? title,
    String? content,
    List<String>? tags,
    DateTime? updatedAt,
    bool? isDirty,
  }) {
    return Note(
      id: id,
      noteDate: noteDate,
      title: title ?? this.title,
      content: content ?? this.content,
      isDefault: isDefault,
      tags: tags ?? List.from(this.tags),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDirty: isDirty ?? this.isDirty,
    );
  }
}
```

**Step 2: EditorPanel에서 dirty 마킹**

`desktop/lib/widgets/editor_panel.dart`의 `_onContentChanged` 수정:

```dart
void _onContentChanged() {
  // Mark as dirty immediately on user input.
  if (widget.note != null) {
    widget.note!.isDirty = true;
  }
  _autoSaveTimer?.cancel();
  _autoSaveTimer = Timer(_autoSaveDelay, _save);
}
```

`_save` 메서드에서 dirty 해제:

```dart
void _save() {
  if (widget.note == null) return;
  final now = DateTime.now();
  final updated = widget.note!.copyWith(
    title: _titleController.text,
    content: _contentController.text,
    updatedAt: now,
    isDirty: false,
  );
  widget.onNoteChanged?.call(updated);
  setState(() => _lastSaved = now);
}
```

**Step 3: DocumentScreen에서 dirty 노트 보호**

`desktop/lib/screens/document_screen.dart`의 `_loadNotes`에 dirty 보호 로직 추가:

```dart
Future<void> _loadNotes() async {
  final now = DateTime.now();
  final currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
  final dates = await _storage.listDates(currentMonth);
  final remoteNotes = <Note>[];
  for (final date in dates) {
    final dayNotes = await _storage.listNotes(date);
    remoteNotes.addAll(dayNotes);
  }
  if (now.day <= 7) {
    final prev = DateTime(now.year, now.month - 1);
    final prevMonth = '${prev.year}-${prev.month.toString().padLeft(2, '0')}';
    final prevDates = await _storage.listDates(prevMonth);
    for (final date in prevDates) {
      final dayNotes = await _storage.listNotes(date);
      remoteNotes.addAll(dayNotes);
    }
  }

  if (!mounted) return;

  // Merge: preserve dirty local notes, update non-dirty from remote.
  final dirtyNotes = <String, Note>{};
  for (final n in _allNotes) {
    if (n.isDirty) dirtyNotes[n.id] = n;
  }

  final merged = <Note>[];
  final seen = <String>{};
  for (final remote in remoteNotes) {
    if (dirtyNotes.containsKey(remote.id)) {
      merged.add(dirtyNotes[remote.id]!);
    } else {
      merged.add(remote);
    }
    seen.add(remote.id);
  }
  // Keep dirty notes that don't exist on remote yet (newly created).
  for (final entry in dirtyNotes.entries) {
    if (!seen.contains(entry.key)) merged.add(entry.value);
  }

  merged.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  final previousSelectedId = _selectedNote?.id;
  setState(() {
    _allNotes = merged;
    _isLoading = false;
    _selectedDate ??= DateTime(now.year, now.month, now.day);
    if (previousSelectedId != null) {
      final match = merged.where((n) => n.id == previousSelectedId);
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
```

**Step 4: Save와 Sync 간 mutex 추가**

`_DocumentScreenState`에 간단한 lock 추가:

```dart
bool _isSyncing = false;
bool _savePending = false;

void _onNoteChanged(Note updatedNote) {
  setState(() {
    final idx = _allNotes.indexWhere((n) => n.id == updatedNote.id);
    if (idx != -1) {
      _allNotes[idx] = updatedNote;
      _selectedNote = updatedNote;
    }
  });
  _saveDebounce?.cancel();
  _saveDebounce = Timer(const Duration(seconds: 2), () async {
    if (_isSyncing) {
      _savePending = true;
      return;
    }
    await _storage.saveNote(updatedNote);
  });
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
      // Flush any pending dirty notes.
      for (final note in _allNotes) {
        if (note.isDirty) {
          await _storage.saveNote(note);
          note.isDirty = false;
        }
      }
    }
  }
}
```

**Step 5: flutter analyze 실행**

Run: `cd desktop && flutter analyze`
Expected: No issues found

**Step 6: 커밋**

```bash
git add desktop/lib/models/note.dart desktop/lib/widgets/editor_panel.dart desktop/lib/screens/document_screen.dart
git commit -m "fix: protect dirty notes from being overwritten during remote sync"
```

---

## Task 4: 노트 삭제 기능

**Files:**
- Modify: `desktop/lib/widgets/note_list_section.dart`
- Modify: `desktop/lib/screens/document_screen.dart`

**Step 1: NoteListSection에 삭제 콜백 추가**

`NoteListSection` 위젯에 `onDeleteNote` 콜백 추가:

```dart
class NoteListSection extends StatelessWidget {
  // 기존 필드...
  final Future<void> Function(Note note)? onDeleteNote;  // 추가

  const NoteListSection({
    // 기존 파라미터...
    this.onDeleteNote,
  });
```

**Step 2: _NoteListItem에 우클릭 컨텍스트 메뉴 추가**

`_NoteListItem`에 `onDelete` 콜백 추가하고, `GestureDetector`를 감싸 우클릭 처리:

```dart
class _NoteListItem extends StatefulWidget {
  final Note note;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;  // 추가

  const _NoteListItem({
    required this.note,
    required this.isSelected,
    required this.onTap,
    this.onDelete,
  });
```

빌드 메서드에서 `GestureDetector`에 `onSecondaryTapUp` 추가:

```dart
GestureDetector(
  onTap: widget.onTap,
  onSecondaryTapUp: (details) => _showContextMenu(context, details.globalPosition),
  child: AnimatedContainer(/* ... */),
)
```

컨텍스트 메뉴:

```dart
void _showContextMenu(BuildContext context, Offset position) {
  final c = context.colors;
  showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
    items: [
      PopupMenuItem(
        value: 'delete',
        child: Row(
          children: [
            Icon(Icons.delete_outline_rounded, size: 16, color: c.error),
            const SizedBox(width: 8),
            Text('삭제', style: TextStyle(color: c.error, fontSize: 13)),
          ],
        ),
      ),
    ],
  ).then((value) {
    if (value == 'delete') widget.onDelete?.call();
  });
}
```

**Step 3: 삭제 확인 다이얼로그 + DocumentScreen 핸들러**

`DocumentScreen`에 삭제 핸들러 추가:

```dart
Future<void> _deleteNote(Note note) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final c = ctx.colors;
      return AlertDialog(
        backgroundColor: c.surface,
        title: Text('노트 삭제', style: TextStyle(color: c.textPrimary, fontSize: 16)),
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
```

`NoteListSection`에 `onDeleteNote` 연결:

```dart
NoteListSection(
  // 기존 파라미터...
  onDeleteNote: _deleteNote,
)
```

**Step 4: flutter analyze 실행**

Run: `cd desktop && flutter analyze`
Expected: No issues found

**Step 5: 커밋**

```bash
git add desktop/lib/widgets/note_list_section.dart desktop/lib/screens/document_screen.dart
git commit -m "feat: add note deletion with context menu and confirmation dialog"
```

---

## Task 5: Note 모델에 StorageType 추가

**Files:**
- Modify: `desktop/lib/models/note.dart`

**Step 1: StorageType enum 및 Note 필드 추가**

```dart
/// Whether a note is synced to remote or stored locally.
enum StorageType { synced, local }

class Note {
  final String id;
  final DateTime noteDate;
  String title;
  String content;
  final bool isDefault;
  List<String> tags;
  final DateTime createdAt;
  DateTime updatedAt;
  bool isDirty;
  final StorageType storageType;  // 추가

  Note({
    required this.id,
    required this.noteDate,
    required this.title,
    required this.content,
    required this.isDefault,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
    this.isDirty = false,
    this.storageType = StorageType.synced,
  });

  Note copyWith({
    String? title,
    String? content,
    List<String>? tags,
    DateTime? updatedAt,
    bool? isDirty,
  }) {
    return Note(
      id: id,
      noteDate: noteDate,
      title: title ?? this.title,
      content: content ?? this.content,
      isDefault: isDefault,
      tags: tags ?? List.from(this.tags),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDirty: isDirty ?? this.isDirty,
      storageType: storageType,
    );
  }
}
```

**Step 2: flutter analyze 실행**

Run: `cd desktop && flutter analyze`
Expected: No issues found

**Step 3: 커밋**

```bash
git add desktop/lib/models/note.dart
git commit -m "feat: add StorageType enum to Note model"
```

---

## Task 6: LocalNoteStorage 구현

**Files:**
- Create: `desktop/lib/storage/local/local_note_storage.dart`

**Step 1: LocalNoteStorage 클래스 작성**

```dart
import 'dart:io';

import 'package:yaml/yaml.dart';

import '../../models/note.dart';
import '../note_storage.dart';
import '../github/github_note_storage.dart'; // parseNote, serializeNote 재사용

/// NoteStorage implementation backed by the local file system.
///
/// Notes are stored as markdown files with YAML frontmatter at:
///   `{basePath}/notes/{YYYY-MM}/{DD}/{title}.md`
class LocalNoteStorage implements NoteStorage {
  final String basePath;

  /// In-memory cache: file path → Note.
  final Map<String, Note> _noteCache = {};

  /// ID-to-path index for fast lookups.
  final Map<String, String> _idToPath = {};

  LocalNoteStorage({required this.basePath});

  // --- Path helpers ---

  String _sanitizeTitle(String title) {
    return title.replaceAll(RegExp(r'[/\\:*?"<>|]'), '');
  }

  String _buildPath(Note note) {
    final yearMonth =
        '${note.noteDate.year}-${note.noteDate.month.toString().padLeft(2, '0')}';
    final day = note.noteDate.day.toString().padLeft(2, '0');
    final sanitized = _sanitizeTitle(note.title);
    final filename = sanitized.isEmpty ? note.id : sanitized;
    return '$basePath/notes/$yearMonth/$day/$filename.md';
  }

  String _dayDirPath(DateTime date) {
    final yearMonth =
        '${date.year}-${date.month.toString().padLeft(2, '0')}';
    final day = date.day.toString().padLeft(2, '0');
    return '$basePath/notes/$yearMonth/$day';
  }

  String _monthDirPath(String yearMonth) {
    return '$basePath/notes/$yearMonth';
  }

  // --- NoteStorage implementation ---

  @override
  Future<List<Note>> listNotes(DateTime date) async {
    final dirPath = _dayDirPath(date);
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];

    final notes = <Note>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.md')) continue;

      // Use cache if available.
      if (_noteCache.containsKey(entity.path)) {
        notes.add(_noteCache[entity.path]!);
        continue;
      }

      final content = await entity.readAsString();
      final note = GitHubNoteStorage.parseNote(content);
      if (note != null) {
        // Override storageType to local.
        final localNote = Note(
          id: note.id,
          noteDate: note.noteDate,
          title: note.title,
          content: note.content,
          isDefault: note.isDefault,
          tags: note.tags,
          createdAt: note.createdAt,
          updatedAt: note.updatedAt,
          storageType: StorageType.local,
        );
        notes.add(localNote);
        _noteCache[entity.path] = localNote;
        _idToPath[localNote.id] = entity.path;
      }
    }
    return notes;
  }

  @override
  Future<List<DateTime>> listDates(String yearMonth) async {
    final dirPath = _monthDirPath(yearMonth);
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];

    final parts = yearMonth.split('-');
    if (parts.length != 2) return [];
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null) return [];

    final dates = <DateTime>[];
    await for (final entity in dir.list()) {
      if (entity is! Directory) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      final day = int.tryParse(name);
      if (day == null) continue;
      dates.add(DateTime(year, month, day));
    }
    dates.sort((a, b) => a.compareTo(b));
    return dates;
  }

  @override
  Future<Note?> getNote(String noteId, DateTime noteDate) async {
    final cachedPath = _idToPath[noteId];
    if (cachedPath != null && _noteCache.containsKey(cachedPath)) {
      return _noteCache[cachedPath];
    }

    final notes = await listNotes(noteDate);
    return notes.where((n) => n.id == noteId).isEmpty
        ? null
        : notes.firstWhere((n) => n.id == noteId);
  }

  @override
  Future<void> saveNote(Note note) async {
    final path = _buildPath(note);

    // Handle title rename: delete old file if path changed.
    final oldPath = _idToPath[note.id];
    if (oldPath != null && oldPath != path) {
      final oldFile = File(oldPath);
      if (await oldFile.exists()) {
        await oldFile.delete();
      }
      _noteCache.remove(oldPath);
      _idToPath.remove(note.id);
    }

    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(GitHubNoteStorage.serializeNote(note));
    _noteCache[path] = note;
    _idToPath[note.id] = path;
  }

  @override
  Future<void> deleteNote(Note note) async {
    final path = _buildPath(note);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    _noteCache.remove(path);
    _idToPath.remove(note.id);
  }
}
```

**Step 2: flutter analyze 실행**

Run: `cd desktop && flutter analyze`
Expected: No issues found

**Step 3: 커밋**

```bash
git add desktop/lib/storage/local/local_note_storage.dart
git commit -m "feat: implement LocalNoteStorage backed by file system"
```

---

## Task 7: 로컬 노트 경로 설정 UI (RepoSelectionScreen)

**Files:**
- Modify: `desktop/pubspec.yaml` (file_picker, shared_preferences 추가)
- Modify: `desktop/lib/screens/repo_selection_screen.dart`

**Step 1: 의존성 추가**

`desktop/pubspec.yaml`의 dependencies에:

```yaml
  file_picker: ^8.0.0
  shared_preferences: ^2.3.0
```

Run: `cd desktop && flutter pub get`

**Step 2: RepoSelectionScreen에 로컬 경로 섹션 추가**

State에 로컬 경로 필드 추가:

```dart
String _localNotePath = '';

@override
void initState() {
  super.initState();
  // ... 기존 코드
  _loadLocalNotePath();
}

Future<void> _loadLocalNotePath() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('local_note_path');
  if (saved != null && saved.isNotEmpty) {
    setState(() => _localNotePath = saved);
  } else {
    // Default path
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    setState(() => _localNotePath = '$home/Documents/SimSync');
  }
}

Future<void> _pickLocalPath() async {
  final result = await FilePicker.platform.getDirectoryPath(
    dialogTitle: '로컬 노트 저장 경로 선택',
    initialDirectory: _localNotePath,
  );
  if (result != null) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('local_note_path', result);
    setState(() => _localNotePath = result);
  }
}
```

`_buildCard`의 children 끝에 로컬 경로 섹션 추가:

```dart
const SizedBox(height: AppDimensions.spacingXl),
_buildLocalPathSection(c),
```

위젯:

```dart
Widget _buildLocalPathSection(AppColorsExtension c) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '로컬 노트 저장 경로',
        style: GoogleFonts.manrope(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: c.textMuted,
          letterSpacing: 0.5,
        ),
      ),
      const SizedBox(height: AppDimensions.spacingSm),
      Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spacingMd,
          vertical: AppDimensions.spacingSm,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
          border: Border.all(color: c.borderSubtle),
        ),
        child: Row(
          children: [
            Icon(Icons.folder_outlined, size: 16, color: c.textSecondary),
            const SizedBox(width: AppDimensions.spacingSm),
            Expanded(
              child: Text(
                _localNotePath,
                style: TextStyle(color: c.textSecondary, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppDimensions.spacingSm),
            InkWell(
              onTap: _isLoading ? null : _pickLocalPath,
              borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: c.surfaceLight,
                  borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
                  border: Border.all(color: c.border),
                ),
                child: Text(
                  '변경',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: c.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
```

**Step 3: onRepoSelected에 로컬 경로 전달**

`RepoSelectionScreen`의 콜백 시그니처는 변경하지 않는다. 로컬 경로는 `SharedPreferences`에 저장되어 있으므로, `_AppShell`에서 `StorageBundle` 생성 시 `SharedPreferences`에서 읽어 `LocalNoteStorage`를 초기화한다.

**Step 4: flutter analyze 실행**

Run: `cd desktop && flutter analyze`
Expected: No issues found

**Step 5: 커밋**

```bash
git add desktop/pubspec.yaml desktop/lib/screens/repo_selection_screen.dart
git commit -m "feat: add local note path selection to repo selection screen"
```

---

## Task 8: StorageBundle 확장 및 통합

**Files:**
- Modify: `desktop/lib/main.dart`
- Modify: `desktop/lib/screens/document_screen.dart`

**Step 1: StorageBundle에 localStorage 추가**

`desktop/lib/main.dart`:

```dart
class StorageBundle {
  final NoteStorage storage;         // GitHub (remote)
  final NoteStorage? localStorage;   // Local file system
  final NoteService noteService;
  final GitHubSyncEngine? syncEngine;

  const StorageBundle({
    required this.storage,
    required this.noteService,
    this.localStorage,
    this.syncEngine,
  });
}
```

`_defaultStorageFactory`에서 `LocalNoteStorage` 생성 추가:

```dart
Future<StorageBundle> _defaultStorageFactory(
  String accessToken, {
  required String owner,
  required String repo,
  required String branch,
  Future<void> Function()? onRemoteChanged,
}) async {
  final localService = NoteService();
  final apiClient = GitHubApiClient(
    token: accessToken,
    owner: owner,
    repo: repo,
  );

  // Load local note path from SharedPreferences.
  final prefs = await SharedPreferences.getInstance();
  final localPath = prefs.getString('local_note_path');
  final effectivePath = localPath ?? _defaultLocalNotePath();

  return StorageBundle(
    storage: GitHubNoteStorage(apiClient),
    localStorage: LocalNoteStorage(basePath: effectivePath),
    noteService: localService,
    syncEngine: GitHubSyncEngine(
      token: accessToken,
      owner: owner,
      repo: repo,
      branch: branch,
      interval: const Duration(seconds: 5),
      onRemoteChanged: onRemoteChanged,
    ),
  );
}

String _defaultLocalNotePath() {
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  return '$home/Documents/SimSync';
}
```

import 추가:
```dart
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'storage/local/local_note_storage.dart';
```

**Step 2: DocumentScreen에 localStorage 전달**

`DocumentScreen`에 `localStorage` 파라미터 추가:

```dart
class DocumentScreen extends StatefulWidget {
  // 기존 필드...
  final NoteStorage? localStorage;  // 추가

  const DocumentScreen({
    // 기존 파라미터...
    this.localStorage,
  });
```

`_AppShell`의 build에서:

```dart
return DocumentScreen(
  onLogout: _handleLogout,
  storage: _bundle!.storage,
  localStorage: _bundle!.localStorage,
  noteService: _bundle!.noteService,
  refreshSignal: _refreshSignal,
  avatarUrl: _session?.user.avatarUrl,
);
```

**Step 3: DocumentScreen의 _loadNotes에서 두 storage 통합**

```dart
Future<void> _loadNotes() async {
  final now = DateTime.now();
  final currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';

  // Load remote notes.
  final dates = await _storage.listDates(currentMonth);
  final remoteNotes = <Note>[];
  for (final date in dates) {
    final dayNotes = await _storage.listNotes(date);
    remoteNotes.addAll(dayNotes);
  }
  if (now.day <= 7) {
    final prev = DateTime(now.year, now.month - 1);
    final prevMonth = '${prev.year}-${prev.month.toString().padLeft(2, '0')}';
    final prevDates = await _storage.listDates(prevMonth);
    for (final date in prevDates) {
      remoteNotes.addAll(await _storage.listNotes(date));
    }
  }

  // Load local notes.
  final localNotes = <Note>[];
  if (widget.localStorage != null) {
    final localDates = await widget.localStorage!.listDates(currentMonth);
    for (final date in localDates) {
      localNotes.addAll(await widget.localStorage!.listNotes(date));
    }
    if (now.day <= 7) {
      final prev = DateTime(now.year, now.month - 1);
      final prevMonth = '${prev.year}-${prev.month.toString().padLeft(2, '0')}';
      final prevLocalDates = await widget.localStorage!.listDates(prevMonth);
      for (final date in prevLocalDates) {
        localNotes.addAll(await widget.localStorage!.listNotes(date));
      }
    }
  }

  if (!mounted) return;

  // Merge with dirty protection.
  final dirtyNotes = <String, Note>{};
  for (final n in _allNotes) {
    if (n.isDirty) dirtyNotes[n.id] = n;
  }

  final merged = <Note>[];
  final seen = <String>{};
  for (final remote in remoteNotes) {
    if (dirtyNotes.containsKey(remote.id)) {
      merged.add(dirtyNotes[remote.id]!);
    } else {
      merged.add(remote);
    }
    seen.add(remote.id);
  }
  for (final local in localNotes) {
    if (!seen.contains(local.id)) {
      if (dirtyNotes.containsKey(local.id)) {
        merged.add(dirtyNotes[local.id]!);
      } else {
        merged.add(local);
      }
      seen.add(local.id);
    }
  }
  for (final entry in dirtyNotes.entries) {
    if (!seen.contains(entry.key)) merged.add(entry.value);
  }

  merged.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  final previousSelectedId = _selectedNote?.id;
  setState(() {
    _allNotes = merged;
    _isLoading = false;
    _selectedDate ??= DateTime(now.year, now.month, now.day);
    if (previousSelectedId != null) {
      final match = merged.where((n) => n.id == previousSelectedId);
      _selectedNote = match.isNotEmpty ? match.first : null;
    }
    if (_selectedNote == null) {
      final todayNotes = _notesForSelectedDate;
      if (todayNotes.isNotEmpty) _selectedNote = todayNotes.first;
    }
  });
}
```

save 시 storage 분기:

```dart
NoteStorage _storageFor(Note note) {
  if (note.storageType == StorageType.local && widget.localStorage != null) {
    return widget.localStorage!;
  }
  return _storage;
}
```

`_onNoteChanged`의 save와 `_deleteNote`에서 `_storageFor(note)` 사용.

**Step 4: flutter analyze 실행**

Run: `cd desktop && flutter analyze`
Expected: No issues found

**Step 5: 커밋**

```bash
git add desktop/lib/main.dart desktop/lib/screens/document_screen.dart
git commit -m "feat: integrate LocalNoteStorage into StorageBundle and DocumentScreen"
```

---

## Task 9: 노트 생성 분기 (동기화 / 로컬)

**Files:**
- Modify: `desktop/lib/screens/document_screen.dart`
- Modify: `desktop/lib/widgets/note_list_section.dart`

**Step 1: _AddNoteButton을 팝업 메뉴로 변경**

`NoteListSection`의 `onCreateNote`를 두 콜백으로 분리:

```dart
class NoteListSection extends StatelessWidget {
  // 기존 필드...
  final VoidCallback onCreateSyncNote;
  final VoidCallback? onCreateLocalNote;
  final Future<void> Function(Note note)? onDeleteNote;
```

`_AddNoteButton`을 팝업 메뉴로:

```dart
class _AddNoteButton extends StatelessWidget {
  final VoidCallback onCreateSync;
  final VoidCallback? onCreateLocal;

  const _AddNoteButton({required this.onCreateSync, this.onCreateLocal});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'sync') onCreateSync();
        if (value == 'local') onCreateLocal?.call();
      },
      offset: const Offset(0, 28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
        side: BorderSide(color: c.border),
      ),
      color: c.surface,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'sync',
          child: Row(
            children: [
              Icon(Icons.cloud_outlined, size: 14, color: c.accent),
              const SizedBox(width: 8),
              Text('동기화 노트', style: GoogleFonts.manrope(fontSize: 12, color: c.textPrimary)),
            ],
          ),
        ),
        if (onCreateLocal != null)
          PopupMenuItem(
            value: 'local',
            child: Row(
              children: [
                Icon(Icons.folder_outlined, size: 14, color: Color(0xFFD97706)),
                const SizedBox(width: 8),
                Text('로컬 노트', style: GoogleFonts.manrope(fontSize: 12, color: c.textPrimary)),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: c.accentSubtle,
          borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
        ),
        child: Icon(Icons.add_rounded, size: 14, color: c.accent),
      ),
    );
  }
}
```

**Step 2: DocumentScreen에 로컬 노트 생성 메서드 추가**

```dart
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
    _selectedNote = newNote;
    _weeklyViewActive = false;
  });
}
```

**Step 3: flutter analyze 실행**

Run: `cd desktop && flutter analyze`
Expected: No issues found

**Step 4: 커밋**

```bash
git add desktop/lib/screens/document_screen.dart desktop/lib/widgets/note_list_section.dart
git commit -m "feat: split note creation into sync and local options"
```

---

## Task 10: 노트 목록 로컬 노트 색상 구분

**Files:**
- Modify: `desktop/lib/theme/app_colors.dart`
- Modify: `desktop/lib/widgets/note_list_section.dart`

**Step 1: AppColorsExtension에 localAccent 색상 추가**

`desktop/lib/theme/app_colors.dart`:

```dart
final Color localAccent;  // 로컬 노트 인디케이터 색상
```

Dark theme:
```dart
localAccent: Color(0xFFD97706),  // amber-600
```

Light theme:
```dart
localAccent: Color(0xFFB45309),  // amber-700
```

`copyWith`, `lerp`, 생성자에도 추가.

**Step 2: _NoteListItem에서 storageType 기반 색상 분기**

좌측 선택 바 색상을 `storageType`에 따라 변경:

```dart
// 기존
color: c.accent,

// 변경
color: widget.note.storageType == StorageType.local ? c.localAccent : c.accent,
```

선택/hover border도 동일 패턴 적용:

```dart
border: widget.isSelected
    ? Border.all(color: (widget.note.storageType == StorageType.local
        ? c.localAccent
        : c.accent).withValues(alpha: 0.3))
    : null,
```

**Step 3: flutter analyze 실행**

Run: `cd desktop && flutter analyze`
Expected: No issues found

**Step 4: 커밋**

```bash
git add desktop/lib/theme/app_colors.dart desktop/lib/widgets/note_list_section.dart
git commit -m "feat: distinguish local notes with amber accent color in note list"
```

---

## Task 11: 최종 통합 검증

**Step 1: flutter analyze**

Run: `cd desktop && flutter analyze`
Expected: No issues found

**Step 2: flutter build macos**

Run: `cd desktop && flutter build macos`
Expected: 빌드 성공

**Step 3: 최종 커밋 (필요시)**

변경사항이 있다면 커밋.

---

## 실행 순서 요약

| Task | 내용 | 의존성 |
|------|------|--------|
| 1 | 코드 하이라이팅 | 없음 |
| 2 | 헤더 간격 | Task 1 |
| 3 | 동기화 dirty flag | 없음 |
| 4 | 노트 삭제 | 없음 |
| 5 | StorageType 모델 | Task 3 (isDirty) |
| 6 | LocalNoteStorage | Task 5 |
| 7 | 경로 설정 UI | 없음 |
| 8 | StorageBundle 통합 | Task 5, 6, 7 |
| 9 | 노트 생성 분기 | Task 8 |
| 10 | 로컬 노트 색상 | Task 5, 9 |
| 11 | 최종 검증 | 전체 |

병렬 실행 가능: Task 1-2 | Task 3 | Task 4 | Task 7 (서로 독립)
