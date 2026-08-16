import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pasteboard/pasteboard.dart';

import '../models/note.dart';
import '../settings/shortcut_binding.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';
import '../services/markdown_editing.dart';
import 'editor_block_decorations.dart';
import 'editor_overlay_layout.dart';
import 'hover_builder.dart';
import 'inline_image_view.dart';
import 'inline_table_view.dart';
import 'markdown_editing_controller.dart';
import 'table_editor_dialog.dart';

/// Auto-save debounce duration.
const _autoSaveDelay = Duration(seconds: 1);

/// 엔진(레이아웃)과 TextPainter(캐럿 메트릭) 모두 "스트럿 없음"으로 취급하는
/// 스트럿. 줄 높이 floor가 사라져 접힌 줄(닫힌 details 본문, 테이블 구분선)이
/// 실제 ~0 높이가 되면서도, 캐럿은 실제 글리프 메트릭으로 정상 배치된다.
///
/// 이렇게 우회하는 이유 (전부 실측/소스로 확인):
/// - `StrutStyle.disabled`: EditableText가 `inheritFromTextStyle`로 null
///   fontSize를 본문 폰트로 채워, 엔진이 "폰트 자연 높이"를 floor로 되살린다.
/// - `StrutStyle(fontSize: 0.1)`: 레이아웃 floor는 없지만 TextPainter의
///   `_strutDisabled`가 fontSize == 0.0만 비활성으로 인정하므로 스트럿이
///   "활성"으로 남아, 문서 끝/빈 줄 캐럿의 전체 높이가 스트럿 박스(~0.1px)로
///   계산되고 macOS 캐럿 센터링이 캐럿을 ~12px 위로 밀어낸다.
/// - `StrutStyle(fontSize: 0)`: 생성자 assert(fontSize > 0)로 직접 생성 불가.
///
/// 따라서 getter 재정의로 fontSize 0.0을 보고하고(TextPainter/엔진의 공식
/// "스트럿 비활성" 마커), EditableText의 상속 변환을 무력화한다.
class _DisabledStrutStyle extends StrutStyle {
  const _DisabledStrutStyle() : super(height: 1, leading: 0);

  @override
  double? get fontSize => 0.0;

  @override
  StrutStyle inheritFromTextStyle(TextStyle? other) => this;

  // EditableText가 lineHeightScaleFactorOverride를 merge로 반영하며 스트럿을
  // 재생성한다(assert fontSize > 0에 걸림). 이 에디터는 자체 콘텐츠 줌을
  // 쓰므로 해당 오버라이드를 무시하고 비활성 스트럿을 유지한다.
  @override
  StrutStyle merge(StrutStyle? other) => this;
}

class EditorPanel extends StatefulWidget {
  final Note? note;
  final ValueChanged<Note>? onNoteChanged;
  final DateTime? selectedDate;
  /// 동기화 노트/메모 생성. [memo]가 true면 메모로 만든다.
  final void Function({bool memo})? onCreateNote;

  /// 로컬 노트/메모 생성. null이면 로컬 버튼이 숨는다.
  final void Function({bool memo})? onCreateLocalNote;
  final bool isReadOnly;
  final String? readOnlyReason;
  final double contentScale;
  final Future<void> Function()? onIncreaseContentScale;
  final Future<void> Function()? onDecreaseContentScale;
  final Future<void> Function(double value)? onSetContentScale;

  /// 노트 기준 상대 src('assets/…')의 이미지 바이트 로더. null이면 이미지
  /// 오버레이 비활성(로드 경로가 없는 컨텍스트).
  final Future<Uint8List?> Function(String src)? onLoadImage;

  /// 이미지 바이트를 스토리지에 저장하고 삽입할 src('assets/…')를 돌려준다.
  /// null이면 이미지 첨부 비활성 (읽기 전용 등).
  final Future<String> Function(Uint8List bytes, String extension)?
      onAttachImage;

  const EditorPanel({
    super.key,
    this.note,
    this.onNoteChanged,
    this.selectedDate,
    this.onCreateNote,
    this.onCreateLocalNote,
    this.isReadOnly = false,
    this.readOnlyReason,
    this.contentScale = 1.0,
    this.onIncreaseContentScale,
    this.onDecreaseContentScale,
    this.onSetContentScale,
    this.onLoadImage,
    this.onAttachImage,
  });

  @override
  State<EditorPanel> createState() => EditorPanelState();
}

class EditorPanelState extends State<EditorPanel> {
  late TextEditingController _titleController;
  late MarkdownEditingController _contentController;
  late TextEditingController _tagController;
  late FocusNode _contentFocusNode;
  late ScrollController _contentScrollController;
  Timer? _autoSaveTimer;
  DateTime? _lastSaved;
  String? _loadedNoteId;
  double _panZoomBaseScale = 1.0;

  /// 콘텐츠 TextField의 렌더 트리 진입점. 데코 페인터/오버레이가 미러
  /// TextPainter 대신 실제 RenderEditable을 직접 조회하는 데 쓴다.
  final GlobalKey _fieldKey = GlobalKey();

  /// 접기 거터 폭: 에디터의 기존 왼쪽 여백(spacingLg)을 스택 안으로 옮겨
  /// 거터로 쓴다 — 일반 텍스트 시작 위치는 예전과 동일하고, details 접기
  /// 버튼과 열림 범위 가이드 라인만 이 여백 안에 그려져 본문과 겹치지
  /// 않는다. (노트 전체가 밀리지 않는다.)
  static const double _foldGutterWidth = AppDimensions.spacingLg;

  /// 콘텐츠 TextField 내부의 [RenderEditable]. 아직 붙지 않았으면 null.
  RenderEditable? _renderEditable() {
    RenderEditable? found;
    void visit(RenderObject child) {
      if (found != null) return;
      if (child is RenderEditable) {
        found = child;
        return;
      }
      child.visitChildren(visit);
    }

    final root = _fieldKey.currentContext?.findRenderObject();
    if (root != null) visit(root);
    return found;
  }

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _contentController = MarkdownEditingController();
    _tagController = TextEditingController();
    _contentFocusNode = FocusNode()..addListener(_onContentFocusChanged);
    _contentScrollController = ScrollController();
    _syncControllers();
  }

  /// When the editor gains/loses focus, the controller re-renders so the caret's
  /// line reveals its markdown markers (focused) or everything renders (blurred).
  void _onContentFocusChanged() {
    if (!mounted) return;
    setState(() => _contentController.focused = _contentFocusNode.hasFocus);
  }

  @override
  void didUpdateWidget(EditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.note?.id != _loadedNoteId) {
      // Flush any pending edit for the previous note before swapping the
      // controllers — otherwise the edited text only ever lived in the
      // controllers and would be discarded by `_syncControllers`.
      final previousNote = oldWidget.note;
      if (previousNote != null) {
        _flushPending(previousNote);
      }
      _syncControllers();
    }
  }

  void _syncControllers() {
    final note = widget.note;
    _loadedNoteId = note?.id;
    _titleController.text = note?.title ?? '';
    _contentController.text = note?.content ?? '';
    _tagController.clear();
    _lastSaved = note?.updatedAt;
  }

  /// Flushes the current controller text into [note] via [onNoteChanged] if
  /// the note has unsaved edits. Cancels the pending auto-save timer to avoid
  /// it firing later against a stale note reference.
  ///
  /// The captured text is snapshotted synchronously (before the controllers are
  /// re-synced to the next note), but the parent callback is invoked after the
  /// frame: [didUpdateWidget] runs mid-build when the note prop changes (e.g.
  /// switching or closing a tab), so calling the parent's setState synchronously
  /// here would throw "setState() called during build".
  void _flushPending(Note note) {
    if (widget.isReadOnly || !note.isDirty) return;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    final callback = widget.onNoteChanged;
    if (callback == null) return;
    final updated = note.copyWith(
      title: _titleController.text,
      content: _contentController.text,
      updatedAt: DateTime.now(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => callback(updated));
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    final note = widget.note;
    if (note != null && note.isDirty && !widget.isReadOnly) {
      // Last-chance flush before controllers are torn down.
      final updated = note.copyWith(
        title: _titleController.text,
        content: _contentController.text,
        updatedAt: DateTime.now(),
      );
      widget.onNoteChanged?.call(updated);
    }
    _titleController.dispose();
    _contentController.dispose();
    _tagController.dispose();
    _contentFocusNode.dispose();
    _contentScrollController.dispose();
    super.dispose();
  }

  void _onContentChanged() {
    if (widget.isReadOnly) return;
    widget.note?.isDirty = true;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(_autoSaveDelay, _save);
  }

  void _save() {
    final note = widget.note;
    if (note == null || widget.isReadOnly) return;
    // Guard against a stale timer firing after the user switched notes.
    if (note.id != _loadedNoteId) return;
    final now = DateTime.now();
    final updated = note.copyWith(
      title: _titleController.text,
      content: _contentController.text,
      updatedAt: now,
    );
    widget.onNoteChanged?.call(updated);
    setState(() => _lastSaved = now);
  }

  void _addTag() {
    if (widget.isReadOnly) return;
    final tag = _tagController.text.trim();
    if (tag.isEmpty || widget.note == null) return;
    if (!widget.note!.tags.contains(tag)) {
      setState(() => widget.note!.tags.add(tag));
      _tagController.clear();
      _save();
    }
  }

  void _removeTag(String tag) {
    if (widget.note == null || widget.isReadOnly) return;
    setState(() => widget.note!.tags.remove(tag));
    _save();
  }

  void _renumberList() {
    if (widget.isReadOnly || widget.note == null) return;
    final updated = renumberOrderedListAtCursor(_contentController.value);
    if (updated.text == _contentController.text) return;
    _contentController.value = updated;
    _onContentChanged();
  }

  /// 전역 단축키 핸들러(document_screen)가 포커스 여부를 확인할 때 사용.
  bool get hasEditorFocus => _contentFocusNode.hasFocus;

  /// 전역 단축키의 포맷팅 액션을 에디터에 적용한다. 동작은 툴바와 동일한
  /// _wrapSelection/_toggleLinePrefix를 재사용한다.
  void applyFormat(ShortcutAction action) {
    if (widget.isReadOnly || widget.note == null) return;
    switch (action) {
      case ShortcutAction.formatBold:
        _wrapSelection('**');
      case ShortcutAction.formatItalic:
        _wrapSelection('*');
      case ShortcutAction.formatStrikethrough:
        _wrapSelection('~~');
      case ShortcutAction.formatInlineCode:
        _wrapSelection('`');
      case ShortcutAction.formatHighlight:
        _wrapSelection('==');
      case ShortcutAction.formatCheckbox:
        _toggleLinePrefix('- [ ] ');
      case ShortcutAction.formatLink:
        _insertLink();
      case ShortcutAction.openSettings:
      case ShortcutAction.zoomIn:
      case ShortcutAction.zoomOut:
      case ShortcutAction.search:
      case ShortcutAction.closeTab:
        break;
    }
  }

  /// 선택 영역을 [텍스트]() 링크로 만든다. 선택이 있으면 캐럿을 URL 자리에,
  /// 없으면 빈 링크를 삽입하고 캐럿을 대괄호 안에 둔다.
  void _insertLink() {
    final value = _contentController.value;
    final text = value.text;
    final selection = value.selection;
    if (!selection.isValid) return;
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(0, text.length);
    final selected = text.substring(start, end);
    final replacement = '[$selected]()';
    _contentController.value = TextEditingValue(
      text: text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(
        offset: selected.isEmpty ? start + 1 : start + replacement.length - 1,
      ),
    );
    _onContentChanged();
  }

  /// Inserts [block] at the cursor, ensuring it starts on its own line and is
  /// followed by a trailing newline.
  void _insertBlock(String block) {
    if (widget.isReadOnly || widget.note == null) return;
    final text = _contentController.text;
    final selection = _contentController.selection;
    final start = (selection.isValid ? selection.baseOffset : text.length)
        .clamp(0, text.length);
    final needsLeadingNewline = start > 0 && text[start - 1] != '\n';
    final insertion = '${needsLeadingNewline ? '\n' : ''}$block\n';
    final newText = text.replaceRange(start, start, insertion);
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + insertion.length),
    );
    _onContentChanged();
  }

  /// 삽입 시 기본 표시 폭 (px). 원본이 더 작으면 원본 폭.
  static const int _defaultImageWidth = 480;

  /// 이미지 태그를 캐럿이 있는 줄의 끝 뒤에 삽입한다. 줄 중간에서 붙여넣어도
  /// 줄을 쪼개지 않고, 태그 앞뒤로 빈 줄 하나를 보장해 위/아래 텍스트와
  /// 붙어 보이지 않게 한다 (이미 빈 줄이 있으면 추가하지 않는다).
  void _insertImageBlock(String tag) {
    if (widget.isReadOnly || widget.note == null) return;
    final text = _contentController.text;
    final selection = _contentController.selection;
    final caret = (selection.isValid ? selection.baseOffset : text.length)
        .clamp(0, text.length);
    var lineEnd = text.indexOf('\n', caret);
    if (lineEnd == -1) lineEnd = text.length;
    final insertAt = lineEnd;

    final before = text.substring(0, insertAt);
    final prefix = before.isEmpty || before.endsWith('\n\n')
        ? ''
        : before.endsWith('\n')
            ? '\n'
            : '\n\n';
    final after = text.substring(insertAt);
    // 문서 끝에 삽입할 때 개행을 하나만 붙이면 태그 줄이 문서의 마지막 실제
    // 줄이 되고, 그 뒤의 빈 마지막 줄(고스트 줄)이 태그 줄의 최대 글리프 —
    // 즉 이미지 높이만큼 예약된 글리프 — 를 물려받아 이미지 높이만큼 커진다.
    // 그 줄에 놓인 캐럿은 이미지 한참 아래에 그려지고, 글자를 하나 치면
    // 그제서야 제자리로 올라온다. 빈 줄을 하나 확보해 그 상황을 만들지 않는다.
    final suffix = after.isEmpty
        ? '\n\n'
        : after.startsWith('\n\n')
            ? ''
            : after.startsWith('\n')
                ? '\n'
                : '\n\n';

    final insertion = '$prefix$tag$suffix';
    _contentController.value = TextEditingValue(
      text: text.replaceRange(insertAt, insertAt, insertion),
      // 캐럿은 태그 줄이 아니라 그 다음 줄 머리에 둔다. 태그 줄의 라인 박스는
      // 이미지 높이만큼 예약되어 캐럿이 이미지 밴드 하단에 그려지고, 그대로
      // 타이핑하면 태그 줄이 깨진다. 태그 뒤 개행은 모든 분기에서 보장된다
      // (suffix가 ''인 분기는 기존 '\n\n'을 재사용).
      selection: TextSelection.collapsed(
          offset: insertAt + prefix.length + tag.length + 1),
    );
    _onContentChanged();
  }

  /// 이미지 바이트를 업로드하고 캐럿 위치에 <img> 태그를 삽입한다.
  /// (테스트에서 직접 호출할 수 있게 public)
  Future<void> attachImageBytes(Uint8List bytes, String extension) async {
    final onAttach = widget.onAttachImage;
    final note = widget.note;
    if (onAttach == null || widget.isReadOnly || note == null) return;
    final noteId = note.id;
    try {
      final decoded = await decodeImageFromList(bytes);
      final natW = decoded.width;
      final natH = decoded.height;
      decoded.dispose();
      final src = await onAttach(bytes, extension);
      final w = math.min(natW, _defaultImageWidth);
      final h = (natH * w / natW).round();
      if (!mounted) return;
      // 업로드 중 노트가 바뀌었으면 삽입하지 않는다 (_save의 stale 타이머 가드와
      // 같은 패턴). 파일은 원래 노트의 assets/에 저장돼 있으므로 유실은 없다.
      if (widget.note?.id != noteId || _loadedNoteId != noteId) return;
      _insertImageBlock(serializeImageTag(src, w, h));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미지 첨부에 실패했습니다.')),
      );
    }
  }

  Future<void> _attachImageFromPicker() async {
    if (widget.isReadOnly ||
        widget.note == null ||
        widget.onAttachImage == null) {
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'gif', 'webp'],
      withData: true,
    );
    final file = result?.files.firstOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    await attachImageBytes(bytes, (file.extension ?? 'png').toLowerCase());
  }

  /// cmd+V 인터셉트: 클립보드에 이미지가 있으면 첨부, 아니면 일반 텍스트
  /// 붙여넣기를 수동 수행한다(이벤트를 가로챘으므로). 우클릭 메뉴 Paste는
  /// 이 경로를 타지 않는다 — 텍스트만 붙는 기존 동작 유지 (MVP 한계).
  /// Tab/Shift+Tab은 리스트 들여쓰기로 가로챈다.
  KeyEventResult _onEditorKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      return _handleListIndent();
    }
    if (event.logicalKey != LogicalKeyboardKey.keyV) {
      return KeyEventResult.ignored;
    }
    if (!HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (widget.isReadOnly || widget.note == null || widget.onAttachImage == null) {
      return KeyEventResult.ignored;
    }
    unawaited(_handlePaste());
    return KeyEventResult.handled;
  }

  /// Tab / Shift+Tab: 캐럿이 있는 리스트 줄의 들여쓰기 단계를 올리고 내린다.
  /// 리스트 줄이 아니면 ignored를 돌려 기본 Tab 동작(포커스 이동)을 남긴다.
  KeyEventResult _handleListIndent() {
    if (widget.isReadOnly || widget.note == null) return KeyEventResult.ignored;
    final updated = indentListSelection(
      _contentController.value,
      outdent: HardwareKeyboard.instance.isShiftPressed,
    );
    if (updated == null) return KeyEventResult.ignored;
    if (updated.text != _contentController.text) {
      _contentController.value = updated;
      _onContentChanged();
    }
    return KeyEventResult.handled;
  }

  Future<void> _handlePaste() async {
    Uint8List? image;
    try {
      image = await Pasteboard.image;
    } catch (_) {
      // 클립보드 이미지 조회 실패는 무시하고 일반 텍스트 붙여넣기로 진행한다.
      // (이벤트를 이미 소비했으므로 여기서 끝나면 붙여넣기가 통째로 사라진다.)
      image = null;
    }
    if (image != null) {
      await attachImageBytes(image, 'png');
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text;
    if (t == null || t.isEmpty) return;
    final value = _contentController.value;
    final start = (value.selection.isValid ? value.selection.start : value.text.length)
        .clamp(0, value.text.length);
    final end = (value.selection.isValid ? value.selection.end : start)
        .clamp(start, value.text.length);
    _contentController.value = TextEditingValue(
      text: value.text.replaceRange(start, end, t),
      selection: TextSelection.collapsed(offset: start + t.length),
    );
    _onContentChanged();
  }

  /// Opens the table grid editor. If the caret is inside an existing table it
  /// edits that table in-place; otherwise it inserts a new one. Either way the
  /// user fills cells in a real grid instead of typing pipe syntax.
  Future<void> _insertTable() async {
    if (widget.isReadOnly || widget.note == null) return;
    final selection = _contentController.selection;
    final offset = selection.isValid ? selection.baseOffset : -1;
    final found =
        offset >= 0 ? tableAtOffset(_contentController.text, offset) : null;
    if (found != null) {
      await _editTableAt(found);
      return;
    }
    final markdown = await TableEditorDialog.show(context, initial: null);
    if (markdown == null || !mounted) return;
    _insertBlock(markdown);
  }

  Future<void> _editTableAt(
      ({MarkdownTableData table, int start, int end}) found) async {
    if (widget.isReadOnly || widget.note == null) return;
    final markdown =
        await TableEditorDialog.show(context, initial: found.table);
    if (markdown == null || !mounted) return;
    _replaceRange(found.start, found.end, markdown);
  }

  // Tapping a rendered table moves the caret into it, which marks it active and
  // reveals the +col/+row controls (the table widget hides its raw markdown).
  void _activateTable(TableRegion table) {
    if (widget.isReadOnly) return;
    _contentFocusNode.requestFocus();
    _contentController.selection =
        TextSelection.collapsed(offset: table.start.clamp(0, _contentController.text.length));
  }

  void _addTableRow(TableRegion table) {
    final data = table.table;
    _mutateTable(
      table,
      MarkdownTableData(
        [...data.rows, List.filled(data.columns, '')],
        data.aligns,
      ),
    );
  }

  void _addTableColumn(TableRegion table) {
    final data = table.table;
    _mutateTable(
      table,
      MarkdownTableData(
        [for (final row in data.rows) [...row, '']],
        [...data.aligns, MarkdownTableAlign.left],
      ),
    );
  }

  // Removes one body row. The header row (index 0) is kept so the table stays a
  // valid markdown table even after all data rows are gone.
  void _removeTableRow(TableRegion table, int row) {
    final data = table.table;
    if (row <= 0 || row >= data.rows.length) return;
    _mutateTable(
      table,
      MarkdownTableData(
        [
          for (var i = 0; i < data.rows.length; i++)
            if (i != row) data.rows[i],
        ],
        data.aligns,
      ),
    );
  }

  // Removes one column from every row (and its alignment). Keeps at least one
  // column; use the X control to remove the table entirely.
  void _removeTableColumn(TableRegion table, int col) {
    final data = table.table;
    if (col < 0 || col >= data.columns || data.columns <= 1) return;
    _mutateTable(
      table,
      MarkdownTableData(
        [
          for (final row in data.rows)
            [
              for (var j = 0; j < data.columns; j++)
                if (j != col) (j < row.length ? row[j] : ''),
            ],
        ],
        [
          for (var j = 0; j < data.columns; j++)
            if (j != col) data.aligns[j],
        ],
      ),
    );
  }

  // Writes one cell's text in place (inline cell editing) and re-serializes the
  // table. Keeps the table active so the caret/controls stay put while typing.
  void _setTableCell(TableRegion table, int row, int col, String value) {
    final data = table.table;
    if (row < 0 || row >= data.rows.length || col < 0 || col >= data.columns) {
      return;
    }
    _mutateTable(
      table,
      MarkdownTableData(
        [
          for (var r = 0; r < data.rows.length; r++)
            [
              for (var k = 0; k < data.columns; k++)
                (r == row && k == col)
                    ? value
                    : (k < data.rows[r].length ? data.rows[r][k] : ''),
            ],
        ],
        data.aligns,
      ),
    );
  }

  // Replaces the table's markdown in place and keeps the caret inside it so it
  // stays active (the +col/+row controls remain visible after the change).
  void _mutateTable(TableRegion table, MarkdownTableData next) {
    if (widget.isReadOnly || widget.note == null) return;
    final text = _contentController.text;
    final s = table.start.clamp(0, text.length);
    final e = table.end.clamp(s, text.length);
    _contentController.value = TextEditingValue(
      text: text.replaceRange(s, e, serializeMarkdownTable(next)),
      selection: TextSelection.collapsed(offset: s),
    );
    _onContentChanged();
  }

  // Removes the whole table (the X control). Also drops the table's trailing
  // newline so no blank line is left where it was. Undoable via the editor.
  void _removeTable(TableRegion table) {
    if (widget.isReadOnly || widget.note == null) return;
    final text = _contentController.text;
    final s = table.start.clamp(0, text.length);
    var e = table.end.clamp(s, text.length);
    if (e < text.length && text[e] == '\n') e++;
    _contentController.value = TextEditingValue(
      text: text.replaceRange(s, e, ''),
      selection: TextSelection.collapsed(offset: s),
    );
    _onContentChanged();
  }

  void _replaceRange(int start, int end, String replacement) {
    final text = _contentController.text;
    final s = start.clamp(0, text.length);
    final e = end.clamp(s, text.length);
    _contentController.value = TextEditingValue(
      text: text.replaceRange(s, e, replacement),
      selection: TextSelection.collapsed(offset: s + replacement.length),
    );
    _onContentChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.note == null) {
      return _buildEmptyState(context);
    }

    final c = context.colors;

    return Column(
      children: [
        _buildToolbar(c),
        Divider(height: 1, color: c.border),
        _buildMetaHeader(c),
        Divider(height: 1, color: c.border),
        Expanded(child: _buildEditor(c)),
        _buildStatusBar(c),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final c = context.colors;
    final hasDate = widget.selectedDate != null;
    final dateLabel = hasDate
        ? DateFormat('yyyy. M. d. (E)').format(widget.selectedDate!)
        : null;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasDate ? Icons.note_add_outlined : Icons.edit_document,
            size: 48,
            color: c.textMuted,
          ),
          const SizedBox(height: AppDimensions.spacingLg),
          if (hasDate) ...[
            Text(
              dateLabel!,
              style: Theme.of(context).textTheme.titleSmall!.copyWith(fontWeight: FontWeight.w600, color: c.textSecondary),
            ),
            const SizedBox(height: AppDimensions.spacingSm),
            Text(
              'No notes for this date',
              style: AppTextStyles.caption.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: AppDimensions.spacingXl),
            // 위: 날짜에 매인 노트, 아래: 날짜 무관 메모. 같은 버튼 위젯을
            // 써서 두 줄의 크기가 같다 (라벨 길이도 동일).
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CreateNoteButton(
                  label: '동기화 노트',
                  icon: Icons.cloud_outlined,
                  onTap: () => widget.onCreateNote?.call(memo: false),
                ),
                if (widget.onCreateLocalNote != null) ...[
                  const SizedBox(width: AppDimensions.spacingSm),
                  _CreateNoteButton(
                    label: '로컬 노트',
                    icon: Icons.folder_outlined,
                    useLocalAccent: true,
                    onTap: () => widget.onCreateLocalNote?.call(memo: false),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppDimensions.spacingSm),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CreateNoteButton(
                  label: '동기화 메모',
                  icon: Icons.sticky_note_2_outlined,
                  onTap: () => widget.onCreateNote?.call(memo: true),
                ),
                if (widget.onCreateLocalNote != null) ...[
                  const SizedBox(width: AppDimensions.spacingSm),
                  _CreateNoteButton(
                    label: '로컬 메모',
                    icon: Icons.sticky_note_2_outlined,
                    useLocalAccent: true,
                    onTap: () => widget.onCreateLocalNote?.call(memo: true),
                  ),
                ],
              ],
            ),
          ] else ...[
            Text(
              'Select a note to start editing',
              style: Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w400, color: c.textMuted),
            ),
            const SizedBox(height: AppDimensions.spacingSm),
            Text(
              'or create a new one from the sidebar',
              style: AppTextStyles.caption.copyWith(color: c.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToolbar(AppColorsExtension c) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingLg),
      color: c.surface,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _titleController,
              onChanged: widget.isReadOnly ? null : (_) => _onContentChanged(),
              readOnly: widget.isReadOnly,
              style: Theme.of(context).textTheme.labelLarge!.copyWith(color: c.textPrimary),
              decoration: InputDecoration(
                hintText: 'Untitled',
                hintStyle: Theme.of(context).textTheme.labelLarge!.copyWith(color: c.textMuted),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: AppDimensions.spacingMd),
          if (!widget.isReadOnly) ...[
            _ToolbarIconButton(
              icon: Icons.format_bold_rounded,
              tooltip: 'Bold',
              onTap: () => _wrapSelection('**'),
            ),
            const SizedBox(width: AppDimensions.spacingXs),
            _ToolbarIconButton(
              icon: Icons.format_italic_rounded,
              tooltip: 'Italic',
              onTap: () => _wrapSelection('*'),
            ),
            const SizedBox(width: AppDimensions.spacingXs),
            _ToolbarIconButton(
              icon: Icons.title_rounded,
              tooltip: 'Heading',
              onTap: () => _toggleLinePrefix('# '),
            ),
            const SizedBox(width: AppDimensions.spacingXs),
            _ToolbarIconButton(
              icon: Icons.format_list_bulleted_rounded,
              tooltip: 'Bullet list',
              onTap: () => _toggleLinePrefix('- '),
            ),
            const SizedBox(width: AppDimensions.spacingXs),
            _ToolbarIconButton(
              icon: Icons.checklist_rounded,
              tooltip: 'Checklist',
              onTap: () => _toggleLinePrefix('- [ ] '),
            ),
            const SizedBox(width: AppDimensions.spacingMd),
            _ToolbarIconButton(
              icon: Icons.table_chart_outlined,
              tooltip: '표 삽입 / 편집',
              onTap: () => unawaited(_insertTable()),
            ),
            const SizedBox(width: AppDimensions.spacingXs),
            _ToolbarIconButton(
              icon: Icons.image_outlined,
              tooltip: '이미지 첨부',
              onTap: () => unawaited(_attachImageFromPicker()),
            ),
            const SizedBox(width: AppDimensions.spacingXs),
            _ToolbarIconButton(
              icon: Icons.format_list_numbered_rounded,
              tooltip: 'Renumber list',
              onTap: _renumberList,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetaHeader(AppColorsExtension c) {
    final note = widget.note!;
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(note.updatedAt);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingLg,
        vertical: AppDimensions.spacingSm,
      ),
      color: c.surface,
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ...note.tags.map(
                  (tag) => _EditorTagChip(
                    label: tag,
                    onRemove: widget.isReadOnly ? null : () => _removeTag(tag),
                  ),
                ),
                SizedBox(
                  width: 80,
                  height: 22,
                  child: TextField(
                    controller: _tagController,
                    readOnly: widget.isReadOnly,
                    style: AppTextStyles.micro.copyWith(color: c.textSecondary),
                    decoration: InputDecoration(
                      hintText: '+ tag',
                      hintStyle: AppTextStyles.micro.copyWith(color: c.textMuted),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                    onSubmitted: widget.isReadOnly ? null : (_) => _addTag(),
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.update_rounded, size: 12, color: c.textMuted),
              const SizedBox(width: AppDimensions.spacingXs),
              Text(
                dateStr,
                style: AppTextStyles.micro.copyWith(color: c.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEditor(AppColorsExtension c) {
    // The controller renders markdown styling inline as you type (Notion /
    // Obsidian style) — there is no separate preview pane.
    _contentController.scale = widget.contentScale;
    final baseStyle =
        AppTextStyles.mdBody(widget.contentScale).copyWith(color: c.textPrimary);
    // A Material TextField does not render with the raw `style` we pass — it
    // merges it onto the theme's body style. Mirror that merge so the hint and
    // the inline table cells use the field's effective style.
    final bodyStyle =
        (Theme.of(context).textTheme.bodyLarge ?? const TextStyle())
            .merge(baseStyle);
    // 스트럿 완전 비활성(_DisabledStrutStyle 주석 참조): 접힌 줄은 실제 ~0
    // 높이가 되고, 일반 줄은 자기 폰트 크기로 높이가 정해지며, 캐럿은 실제
    // 글리프 메트릭으로 배치된다. 데코/오버레이 좌표는 미러 TextPainter가
    // 아니라 RenderEditable을 직접 조회하므로 스트럿 정합 문제는 없다.
    const strut = _DisabledStrutStyle();

    final field = TextField(
      key: _fieldKey,
      controller: _contentController,
      focusNode: _contentFocusNode,
      scrollController: _contentScrollController,
      // 선택/밴드 박스를 풀 라인 박스로 만든다. 기본(tight)은 글리프 잉크
      // 경계를 반환해 폰트 메트릭(Inter의 ascent+descent 등)에 따라 라인
      // 박스와 어긋난다 — 이미지 예약 줄처럼 큰 라인에서는 그 오차가
      // 비례해서 커져, 오버레이가 위/아래 줄을 침범했다. max면 밴드가
      // 항상 정확한 라인 경계와 일치한다 (선택 하이라이트도 풀 라인).
      selectionHeightStyle: ui.BoxHeightStyle.max,
      onChanged: widget.isReadOnly ? null : (_) => _onContentChanged(),
      readOnly: widget.isReadOnly,
      inputFormatters: widget.isReadOnly
          ? null
          : [
              MarkdownListInputFormatter(),
              DetailsBlockInputFormatter(),
              CheckboxShorthandInputFormatter(),
            ],
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      cursorColor: c.accent,
      style: bodyStyle,
      strutStyle: strut,
      decoration: InputDecoration(
        hintText: 'Start writing in markdown...',
        hintStyle: bodyStyle.copyWith(color: c.textMuted),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        contentPadding: EdgeInsets.zero,
      ),
    );

    // cmd+V 이미지 붙여넣기를 TextField 기본 paste보다 먼저 가로챈다.
    // 필드는 접기 거터만큼 오른쪽으로 배치 — 거터에는 details 접기 버튼과
    // 가이드 라인이 놓인다. (세로 좌표는 그대로라 RenderEditable 밴드 측정에
    // 영향이 없고, 가로는 leftInset으로 보정한다.)
    final wrappedField = Padding(
      padding: const EdgeInsets.only(left: _foldGutterWidth),
      child: Focus(
        onKeyEvent: _onEditorKeyEvent,
        child: field,
      ),
    );

    // 오버레이(테이블/이미지/chevron)는 CustomMultiChildLayout으로 배치한다.
    // 델리게이트의 performLayout은 Stack 자식 순서상 필드 레이아웃 직후에
    // 돌기 때문에, RenderEditable을 조회하면 이번 프레임의 실제 배치를 얻는다
    // (빌드 시점 미러 측정의 1프레임 지연/발산 문제가 없다).
    final Widget body = Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            // Rebuild the decoration layer on every text/caret change so code
            // boxes (and `---` rules / quote bars) grow and shrink with the
            // content as you type — the rest of the editor does not rebuild.
            child: ListenableBuilder(
              listenable: _contentController,
              builder: (context, _) {
                final allRegions =
                    parseEditorBlockRegions(_contentController.text);
                final tables = findTableRegions(_contentController.text);
                final details = findDetailsRegions(_contentController.text);
                final regions = [
                  ...filterEditorRegions(allRegions, tables, details),
                  // 열린 details 본문 왼쪽의 접기 범위 가이드 라인.
                  ...detailsGuideRegions(details),
                ];
                if (regions.isEmpty) {
                  return const SizedBox.expand();
                }
                return CustomPaint(
                  painter: EditorBlockDecorationPainter(
                    editable: _renderEditable,
                    regions: regions,
                    repaint: _contentScrollController,
                    codeBackground: c.surfaceLight,
                    codeBorder: c.border,
                    ruleColor: c.border,
                    quoteBar: c.textMuted,
                    detailsGuide: c.textMuted.withValues(alpha: 0.35),
                    leftInset: _foldGutterWidth,
                  ),
                );
              },
            ),
          ),
        ),
        wrappedField,
        // Tables render as real, scrollable widgets over their hidden markdown,
        // on top of the field so they can take taps and show the +col/+row
        // controls when the caret is inside them.
        //
        // 각 오버레이 레이어는 ClipRect로 감싼다: CustomMultiChildLayout은
        // 자식 페인트를 클리핑하지 않아서, 스크롤로 밴드가 뷰포트를 벗어나면
        // 오버레이(특히 큰 이미지)가 에디터 영역 밖까지 그려진다.
        Positioned.fill(
          child: ClipRect(child: _buildTableOverlays(c, bodyStyle)),
        ),
        // details 접기/펼치기 chevron — summary 줄 왼쪽 거터에 겹친다.
        Positioned.fill(
          child: ClipRect(child: _buildDetailsToggles(c)),
        ),
        // 작업 목록 체크박스 — 숨겨진 `[x]` 글자 자리에 겹친다.
        Positioned.fill(
          child: ClipRect(child: _buildCheckboxOverlays()),
        ),
        // 인라인 이미지 — 숨겨진 <img> 줄의 예약 밴드 위에 그린다.
        Positioned.fill(
          child: ClipRect(child: _buildImageOverlays(c)),
        ),
      ],
    );

    return _buildZoomAwareSurface(
      Container(
        color: c.scaffold,
        // 왼쪽 여백은 접기 거터(_foldGutterWidth)가 스택 안에서 대신한다.
        padding: const EdgeInsets.fromLTRB(
          0,
          AppDimensions.spacingLg,
          AppDimensions.spacingLg,
          AppDimensions.spacingLg,
        ),
        child: body,
      ),
    );
  }

  /// 오버레이 델리게이트가 공유하는 relayout 트리거: 텍스트/캐럿 변경과 스크롤.
  Listenable get _overlayRelayout =>
      Listenable.merge([_contentController, _contentScrollController]);

  // Positions an [InlineTableView] over each table's hidden markdown. 자식
  // 목록은 텍스트/캐럿 변경 때 재빌드되고, 위치는 델리게이트가 레이아웃
  // 시점에 RenderEditable에서 직접 읽는다.
  Widget _buildTableOverlays(AppColorsExtension c, TextStyle bodyStyle) {
    return ListenableBuilder(
      listenable: _contentController,
      builder: (context, _) {
        final tables = findTableRegions(_contentController.text);
        if (tables.isEmpty) return const SizedBox.shrink();
        final sel = _contentController.selection;
        final caret = sel.isValid ? sel.baseOffset : -1;
        return CustomMultiChildLayout(
          delegate: EditorOverlayLayoutDelegate(
            editable: _renderEditable,
            relayout: _overlayRelayout,
            leftInset: _foldGutterWidth,
            items: [
              for (final t in tables)
                EditorOverlayItem(
                  id: t.start,
                  start: t.start,
                  end: t.end,
                  anchor: EditorOverlayAnchor.band,
                ),
            ],
          ),
          children: [
            for (final t in tables)
              LayoutId(
                id: t.start,
                child: _forwardEditorScroll(
                  child: InlineTableView(
                    key: ValueKey(t.start),
                    data: t.table,
                    active: !widget.isReadOnly &&
                        caret >= t.start &&
                        caret <= t.end,
                    cellStyle: bodyStyle,
                    onActivate: () => _activateTable(t),
                    onAddRow: () => _addTableRow(t),
                    onAddColumn: () => _addTableColumn(t),
                    onRemove: () => _removeTable(t),
                    onCellChanged: (row, col, value) =>
                        _setTableCell(t, row, col, value),
                    onRemoveRow: (row) => _removeTableRow(t, row),
                    onRemoveColumn: (col) => _removeTableColumn(t, col),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // details 접기 chevron을 summary 줄 왼쪽 끝에 겹친다. summary 렌더링이
  // '<summary>' 태그를 투명 인덴트로 남겨두므로 제목과 겹치지 않는다.
  Widget _buildDetailsToggles(AppColorsExtension c) {
    return ListenableBuilder(
      listenable: _contentController,
      builder: (context, _) {
        final details = findDetailsRegions(_contentController.text);
        if (details.isEmpty) return const SizedBox.shrink();
        return CustomMultiChildLayout(
          delegate: EditorOverlayLayoutDelegate(
            editable: _renderEditable,
            relayout: _overlayRelayout,
            items: [
              for (final d in details)
                EditorOverlayItem(
                  id: d.start,
                  start: d.summaryLineRange.start,
                  end: d.summaryLineRange.end,
                  anchor: EditorOverlayAnchor.leadingChevron,
                ),
            ],
          ),
          children: [
            for (final d in details)
              LayoutId(
                id: d.start,
                child: _DetailsToggleButton(
                  open: d.open,
                  onTap: widget.isReadOnly
                      ? null
                      : () => _toggleDetailsOpen(d),
                ),
              ),
          ],
        );
      },
    );
  }

  /// 체크박스 한 변의 크기(px, 콘텐츠 줌 이전). 본문 14px에서 감춘 `[ ]` 세
  /// 글자 폭과 비슷해 텍스트 흐름을 밀지 않는다. 폰트를 바꾸면 조정한다.
  static const double _checkboxSize = 12;

  // 체크박스를 감춰진 `[x]` 글자 자리에 겹친다. 자식 목록은 텍스트 변경 때
  // 재빌드되고, 위치는 델리게이트가 RenderEditable에서 직접 읽는다.
  Widget _buildCheckboxOverlays() {
    return ListenableBuilder(
      listenable: _contentController,
      builder: (context, _) {
        final boxes = findCheckboxRegions(_contentController.text);
        if (boxes.isEmpty) return const SizedBox.shrink();
        return CustomMultiChildLayout(
          delegate: EditorOverlayLayoutDelegate(
            editable: _renderEditable,
            relayout: _overlayRelayout,
            leftInset: _foldGutterWidth,
            items: [
              for (final b in boxes)
                // 앵커는 여는 대괄호 한 글자다. 세 글자(`[x]`)를 쓰면 줄바꿈이
                // 걸리거나 런이 쪼개질 때 박스가 넓게 잡혀 자리가 튄다.
                EditorOverlayItem(
                  id: b.start,
                  start: b.start,
                  end: b.start + 1,
                  anchor: EditorOverlayAnchor.charBox,
                ),
            ],
          ),
          children: [
            for (final b in boxes)
              LayoutId(
                id: b.start,
                child: _forwardEditorScroll(
                  child: _CheckboxToggle(
                    key: ValueKey('checkbox:${b.start}'),
                    checked: b.checked,
                    size: _checkboxSize * widget.contentScale,
                    onTap: widget.isReadOnly ? null : () => _toggleCheckbox(b),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// 체크박스 클릭: `[ ]` ↔ `[x]`. 글자 수가 그대로라 캐럿/선택은 손대지
  /// 않는다. 클릭과 리빌드 사이에 노트가 바뀌었을 수 있으므로 마크 문자를
  /// 다시 확인하고 쓴다.
  void _toggleCheckbox(CheckboxRegion box) {
    if (widget.isReadOnly || widget.note == null) return;
    final text = _contentController.text;
    if (box.end > text.length || !' xX'.contains(text[box.markOffset])) return;
    _contentController.value = _contentController.value.copyWith(
      text: text.replaceRange(
          box.markOffset, box.markOffset + 1, box.checked ? ' ' : 'x'),
    );
    _onContentChanged();
  }

  /// 오버레이(이미지/테이블) 위의 스크롤 입력을 에디터 스크롤로 전달한다.
  ///
  /// 오버레이가 히트 테스트를 가로채면 아래 TextField의 Scrollable이 스크롤
  /// 입력을 받지 못한다. 마우스 휠(PointerScrollEvent)과 트랙패드 두 손가락
  /// 스크롤(PointerPanZoomUpdate)은 서로 다른 이벤트 계열이라 둘 다 다뤄야
  /// 한다 — v0.2.2 수정이 휠만 다뤄 트랙패드에서 여전히 죽어 있었다.
  Widget _forwardEditorScroll({required Widget child}) {
    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) return;
        if (HardwareKeyboard.instance.isMetaPressed) return; // cmd+휠 = 줌
        // 오버레이 내부에 자체 Scrollable(테이블 가로 스크롤)이 있으면 그쪽이
        // 먼저 등록해 이긴다 — resolver 규약을 따라 충돌 없이 공존한다.
        GestureBinding.instance.pointerSignalResolver.register(event, (e) {
          _scrollEditorBy((e as PointerScrollEvent).scrollDelta.dy);
        });
      },
      onPointerPanZoomUpdate: (event) {
        // 트랙패드 두 손가락 스크롤. 핀치 줌(scale 변화)은 조상 줌 Listener가
        // 처리하므로 여기서는 순수 팬만 전달한다. 드래그 방향과 콘텐츠 이동
        // 방향은 반대(콘텐츠가 손가락을 따라감)라 부호를 뒤집는다.
        if (event.scale != 1.0) return;
        _scrollEditorBy(-event.panDelta.dy);
      },
      child: child,
    );
  }

  void _scrollEditorBy(double delta) {
    if (!_contentScrollController.hasClients) return;
    final position = _contentScrollController.position;
    final target = (position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target != position.pixels) {
      position.jumpTo(target);
    }
  }

  Widget _buildImageOverlays(AppColorsExtension c) {
    final onLoad = widget.onLoadImage;
    if (onLoad == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: _contentController,
      builder: (context, _) {
        final images = findImageRegions(_contentController.text);
        if (images.isEmpty) return const SizedBox.shrink();
        final sel = _contentController.selection;
        final caret = sel.isValid ? sel.baseOffset : -1;
        final scale = widget.contentScale;
        return CustomMultiChildLayout(
          delegate: EditorOverlayLayoutDelegate(
            editable: _renderEditable,
            relayout: _overlayRelayout,
            leftInset: _foldGutterWidth,
            items: [
              for (final r in images)
                EditorOverlayItem(
                  id: r.start,
                  start: r.start,
                  end: r.end,
                  anchor: EditorOverlayAnchor.imageBand,
                  childHeight: r.height * scale,
                ),
            ],
          ),
          children: [
            for (final r in images)
              LayoutId(
                id: r.start,
                child: _forwardEditorScroll(
                  child: InlineImageView(
                    key: ValueKey('${r.start}:${r.src}'),
                    src: r.src,
                    width: r.width,
                    height: r.height,
                    scale: scale,
                    active: !widget.isReadOnly &&
                        caret >= r.start &&
                        caret <= r.end,
                    readOnly: widget.isReadOnly,
                    loadImage: onLoad,
                    onActivate: () => _activateImage(r),
                    onResized: (w, h) => _resizeImage(r, w, h),
                    onRemove: () => _removeImage(r),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // 이미지를 클릭하면 캐럿을 (숨겨진) 태그 줄로 옮겨 활성화한다.
  void _activateImage(ImageRegion r) {
    if (widget.isReadOnly) return;
    _contentFocusNode.requestFocus();
    _contentController.selection = TextSelection.collapsed(
        offset: r.start.clamp(0, _contentController.text.length));
  }

  // 리사이즈 결과를 태그의 width/height 속성으로 재기록한다. 드래그 중 매
  // 프레임 호출되므로 [r]의 end는 직전 프레임 기준이라 이미 어긋나 있을 수
  // 있다 — 줄 끝을 현재 텍스트에서 다시 찾아 그 줄만 통째로 교체한다.
  void _resizeImage(ImageRegion r, int w, int h) {
    if (widget.isReadOnly || widget.note == null) return;
    final text = _contentController.text;
    final s = r.start.clamp(0, text.length);
    var e = text.indexOf('\n', s);
    if (e == -1) e = text.length;
    _replaceRange(s, e, serializeImageTag(r.src, w, h));
  }

  // 태그 줄 전체(뒤따르는 개행 포함)를 삭제한다. 파일 정리는 하지 않는다
  // (orphan 허용 — 설계 문서 범위 외 참고).
  void _removeImage(ImageRegion r) {
    if (widget.isReadOnly || widget.note == null) return;
    final text = _contentController.text;
    final s = r.start.clamp(0, text.length);
    var e = r.end.clamp(s, text.length);
    if (e < text.length && text[e] == '\n') e++;
    _contentController.value = TextEditingValue(
      text: text.replaceRange(s, e, ''),
      selection: TextSelection.collapsed(offset: s),
    );
    _onContentChanged();
  }

  /// `<details>` ↔ `<details open>` 토글. 펼침 상태가 파일에 저장되어 GitHub
  /// 웹/다른 디바이스와 공유된다.
  void _toggleDetailsOpen(DetailsRegion d) {
    if (widget.isReadOnly || widget.note == null) return;
    final text = _contentController.text;
    final line =
        text.substring(d.detailsLineRange.start, d.detailsLineRange.end);
    final newLine = d.open
        ? line.replaceFirst('<details open>', '<details>')
        : line.replaceFirst('<details>', '<details open>');
    if (newLine == line) return;
    final delta = newLine.length - line.length;
    final selection = _contentController.selection;
    final caret = selection.isValid ? selection.baseOffset : d.start;
    // 태그 줄(<details>) 뒤에 캐럿이 있으면 줄 길이 변화(±' open')만큼 같이
    // 밀어줘야 캐럿이 같은 글자를 계속 가리킨다. 태그 줄 안/이전이면 그대로 둔다.
    final adjustedCaret =
        caret > d.detailsLineRange.end ? caret + delta : caret;
    final newText = text.replaceRange(
        d.detailsLineRange.start, d.detailsLineRange.end, newLine);
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: adjustedCaret.clamp(0, newText.length),
      ),
    );
    _onContentChanged();
  }

  static final RegExp _leadingIndent = RegExp(r'^[ \t]*');
  static final List<RegExp> _blockPrefixes = [
    RegExp(r'^#{1,6} '), // heading
    RegExp(r'^[-*+] \[[ xX]\] '), // checkbox (before bullet)
    RegExp(r'^[-*+] '), // bullet
    RegExp(r'^\d+[.)] '), // ordered
    RegExp(r'^\| '), // quote (new)
    RegExp(r'^> '), // quote (legacy, 교체 인식용)
  ];

  /// Length of any recognized block prefix at the start of [body] (no indent),
  /// or 0 when the line has no block marker.
  int _blockPrefixLength(String body) {
    for (final pattern in _blockPrefixes) {
      final match = pattern.firstMatch(body);
      if (match != null) return match.end;
    }
    return 0;
  }

  /// Toggles inline [marker] (e.g. `**` for bold) on the selection. An empty
  /// selection inserts the markers with the cursor between them; a selection
  /// already wrapped in [marker] is un-wrapped.
  void _wrapSelection(String marker) {
    if (widget.isReadOnly) return;
    final value = _contentController.value;
    final text = value.text;
    final selection = value.selection;
    if (!selection.isValid) return;
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(0, text.length);
    final selected = text.substring(start, end);

    // Un-wrap if the selection is already exactly wrapped.
    if (selected.length >= marker.length * 2 &&
        selected.startsWith(marker) &&
        selected.endsWith(marker)) {
      final inner =
          selected.substring(marker.length, selected.length - marker.length);
      _contentController.value = TextEditingValue(
        text: text.replaceRange(start, end, inner),
        selection:
            TextSelection(baseOffset: start, extentOffset: start + inner.length),
      );
      _onContentChanged();
      return;
    }

    _contentController.value = TextEditingValue(
      text: text.replaceRange(start, end, '$marker$selected$marker'),
      selection: selected.isEmpty
          ? TextSelection.collapsed(offset: start + marker.length)
          : TextSelection(
              baseOffset: start + marker.length,
              extentOffset: end + marker.length,
            ),
    );
    _onContentChanged();
  }

  /// Toggles a line-level [prefix] (`# `, `- `, `- [ ] `) on the caret's line.
  /// Setting a new block type replaces any existing one (Notion/Obsidian style)
  /// rather than stacking; pressing the same type again clears it. Leading
  /// indentation is preserved.
  void _toggleLinePrefix(String prefix) {
    if (widget.isReadOnly) return;
    final value = _contentController.value;
    final text = value.text;
    final selection = value.selection;
    final caret =
        (selection.isValid ? selection.baseOffset : text.length).clamp(0, text.length);
    final lineStart = caret == 0 ? 0 : text.lastIndexOf('\n', caret - 1) + 1;
    var lineEnd = text.indexOf('\n', caret);
    if (lineEnd == -1) lineEnd = text.length;
    final line = text.substring(lineStart, lineEnd);

    final indent = _leadingIndent.firstMatch(line)!.group(0)!;
    final body = line.substring(indent.length);
    final existingLen = _blockPrefixLength(body);
    final content = body.substring(existingLen);
    // Toggle off only when the existing block prefix is exactly this one;
    // otherwise replace it (e.g. checkbox -> bullet, not strip to plain).
    final toggleOff = body.substring(0, existingLen) == prefix;
    final newPrefixLen = toggleOff ? 0 : prefix.length;
    final newBody = toggleOff ? content : '$prefix$content';
    final newLine = '$indent$newBody';

    final caretInLine = caret - lineStart;
    final contentStart = indent.length + existingLen;
    final newContentStart = indent.length + newPrefixLen;
    final newCaretInLine = caretInLine <= contentStart
        ? newContentStart
        : caretInLine - contentStart + newContentStart;

    final newText = text.replaceRange(lineStart, lineEnd, newLine);
    final newCaret =
        (lineStart + newCaretInLine).clamp(lineStart, lineStart + newLine.length);
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCaret),
    );
    _onContentChanged();
  }

  Widget _buildZoomAwareSurface(Widget child) {
    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent ||
            !HardwareKeyboard.instance.isMetaPressed) {
          return;
        }

        if (event.scrollDelta.dy < 0) {
          unawaited(widget.onIncreaseContentScale?.call());
        } else if (event.scrollDelta.dy > 0) {
          unawaited(widget.onDecreaseContentScale?.call());
        }
      },
      onPointerPanZoomStart: (_) {
        _panZoomBaseScale = widget.contentScale;
      },
      onPointerPanZoomUpdate: (event) {
        unawaited(
          widget.onSetContentScale?.call(_panZoomBaseScale * event.scale),
        );
      },
      child: child,
    );
  }

  Widget _buildStatusBar(AppColorsExtension c) {
    final savedText = _lastSaved != null
        ? 'Saved at ${DateFormat('HH:mm:ss').format(_lastSaved!)}'
        : '';

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingLg),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          if (widget.isReadOnly && widget.readOnlyReason != null) ...[
            Icon(Icons.lock_outline_rounded, size: 12, color: c.textMuted),
            const SizedBox(width: AppDimensions.spacingXs),
            Expanded(
              child: Text(
                widget.readOnlyReason!,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.micro.copyWith(color: c.textMuted),
              ),
            ),
            const SizedBox(width: AppDimensions.spacingMd),
          ],
          if (savedText.isNotEmpty) ...[
            Icon(
              Icons.check_circle_outline_rounded,
              size: 12,
              color: c.success,
            ),
            const SizedBox(width: AppDimensions.spacingXs),
            Text(
              savedText,
              style: AppTextStyles.micro.copyWith(color: c.textMuted),
            ),
          ],
          const Spacer(),
          Text(
            'Markdown ${(widget.contentScale * 100).round()}%',
            style: AppTextStyles.micro.copyWith(color: c.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Compact hover icon button used for editor toolbar actions.
class _ToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Tooltip(
      message: tooltip,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppDimensions.animFast,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: hovered ? c.surfaceHover : c.surfaceLight,
              borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
              border: Border.all(color: c.border),
            ),
            child: Icon(icon, size: 16, color: c.textSecondary),
          ),
        ),
      ),
    );
  }
}

/// details 블록 summary 줄 왼쪽의 접기/펼치기 버튼.
/// 채워진 삼각형 + 본문보다 진한 색으로 접기 지점을 뚜렷하게 보여준다.
class _DetailsToggleButton extends StatelessWidget {
  final bool open;
  final VoidCallback? onTap;

  const _DetailsToggleButton({required this.open, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Icon(
          open ? Icons.arrow_drop_down_rounded : Icons.arrow_right_rounded,
          size: 16,
          color: c.textSecondary,
        ),
      ),
    );
  }
}

/// 작업 목록(`- [ ] `) 체크박스. 감춰진 `[x]` 글자 자리에 겹쳐 그려지고,
/// 클릭하면 원문의 마크 문자를 토글한다.
///
/// [TextFieldTapRegion]으로 감싸는 이유: 데스크톱 TextField는 자기 영역 밖
/// 탭에서 포커스를 놓는다. 체크만 눌렀다고 편집 중이던 캐럿이 사라지면 안 된다.
class _CheckboxToggle extends StatelessWidget {
  final bool checked;
  final double size;
  final VoidCallback? onTap;

  const _CheckboxToggle({
    super.key,
    required this.checked,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TextFieldTapRegion(
      child: MouseRegion(
        cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: checked ? c.accent : Colors.transparent,
              borderRadius:
                  BorderRadius.circular(AppDimensions.borderRadiusSm),
              border: Border.all(
                color: checked ? c.accent : c.textMuted,
                width: 1.2,
              ),
            ),
            child: checked
                ? Icon(Icons.check_rounded,
                    size: size - 2, color: c.textOnAccent)
                : null,
          ),
        ),
      ),
    );
  }
}

class _CreateNoteButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool useLocalAccent;
  final VoidCallback? onTap;

  const _CreateNoteButton({
    required this.label,
    required this.icon,
    this.useLocalAccent = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accentColor = useLocalAccent ? c.localAccent : c.accent;

    return HoverBuilder(
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingLg,
            vertical: AppDimensions.spacingSm,
          ),
          decoration: BoxDecoration(
            color: hovered ? c.surfaceHover : c.surfaceLight,
            borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
            border: Border.all(
              color: hovered ? accentColor.withValues(alpha: 0.3) : c.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: hovered ? accentColor : c.textSecondary,
              ),
              const SizedBox(width: AppDimensions.spacingSm),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall!.copyWith(fontWeight: FontWeight.w500, color: hovered ? accentColor : c.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorTagChip extends StatelessWidget {
  final String label;
  final VoidCallback? onRemove;

  const _EditorTagChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      padding: const EdgeInsets.only(left: AppDimensions.spacingSm, right: 2, top: 2, bottom: 2),
      decoration: BoxDecoration(
        color: c.accentSubtle,
        borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
        border: Border.all(color: c.accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTextStyles.microMedium.copyWith(color: c.accent),
          ),
          if (onRemove != null)
            GestureDetector(
              onTap: onRemove,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  Icons.close_rounded,
                  size: 12,
                  color: c.accent.withValues(alpha: 0.6),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
