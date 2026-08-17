import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/note.dart';
import '../services/image_asset_service.dart';
import '../services/menu_bar_controller.dart';
import '../settings/app_settings_controller.dart';
import '../settings/shortcut_binding.dart';
import '../storage/note_storage.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';
import 'app_logo_mark.dart';
import 'calendar_section.dart';
import 'editor_panel.dart';
import 'note_list_menus.dart';

/// The compact popover shown from the macOS menu bar.
///
/// Top: a calendar with note dots. Tapping a date lists that day's notes below
/// (with a Memo tab); right-clicking a date — or the list "+" — adds a note or
/// memo. Selecting or adding one slides an editor overlay over the panel. All
/// state and persistence live in [MenuBarController], sharing the app's storage.
class MenuBarPanel extends StatefulWidget {
  const MenuBarPanel({
    super.key,
    required this.controller,
    required this.settings,
  });

  final MenuBarController controller;
  final AppSettingsController settings;

  @override
  State<MenuBarPanel> createState() => _MenuBarPanelState();
}

class _MenuBarPanelState extends State<MenuBarPanel> {
  bool _calendarExpanded = true;

  /// 포맷팅 단축키를 팝오버의 에디터로 전달하기 위한 키.
  final GlobalKey<EditorPanelState> _editorKey = GlobalKey<EditorPanelState>();

  /// 스토리지별 이미지 자산 서비스 (메인 창의 document_screen과 동일 정책:
  /// 원격(synced) 스토리지만 디스크 캐시).
  final Map<NoteStorage, ImageAssetService> _imageServices = {};

  ImageAssetService? _imageServiceFor(Note note) {
    final storage = _c.storageFor(note);
    if (storage == null) return null;
    return _imageServices.putIfAbsent(
      storage,
      () => ImageAssetService(
        storage: storage,
        useDiskCache: identical(storage, _c.syncedStorage),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // 팝오버는 별도 엔진이라 메인 창(document_screen)의 전역 단축키 핸들러가
    // 없다 — 포맷팅/확대/축소 단축키를 여기서 동일하게 처리한다.
    HardwareKeyboard.instance.addHandler(_handleHardwareKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeyEvent);
    super.dispose();
  }

  bool _handleHardwareKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final hw = HardwareKeyboard.instance;
    final isMetaPressed = hw.isMetaPressed;
    final isShiftPressed = hw.isShiftPressed;

    for (final binding in widget.settings.bindings) {
      if (binding.matches(
        event,
        isMetaPressed: isMetaPressed,
        isShiftPressed: isShiftPressed,
      )) {
        switch (binding.action) {
          case ShortcutAction.zoomIn:
            unawaited(widget.settings.increaseContentScale());
          case ShortcutAction.zoomOut:
            unawaited(widget.settings.decreaseContentScale());
          case ShortcutAction.formatBold:
          case ShortcutAction.formatItalic:
          case ShortcutAction.formatStrikethrough:
          case ShortcutAction.formatInlineCode:
          case ShortcutAction.formatLink:
          case ShortcutAction.formatCheckbox:
          case ShortcutAction.formatHighlight:
            final editor = _editorKey.currentState;
            if (editor == null || !editor.hasEditorFocus) return false;
            editor.applyFormat(binding.action);
          case ShortcutAction.openSettings:
          case ShortcutAction.search:
          case ShortcutAction.closeTab:
          case ShortcutAction.toggleSidebar:
          case ShortcutAction.toggleDirectoryPanel:
            // 팝오버에는 해당 화면이 없다 — 소비하지 않는다.
            return false;
        }
        return true;
      }
    }

    // 메인 창과 동일한 숫자패드 줌 변형.
    if (isMetaPressed) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.numpadAdd) {
        unawaited(widget.settings.increaseContentScale());
        return true;
      }
      if (key == LogicalKeyboardKey.numpadSubtract) {
        unawaited(widget.settings.decreaseContentScale());
        return true;
      }
    }

    return false;
  }

  // Side length of a calendar day cell; the draggable divider between the
  // calendar and the note list adjusts it (smaller cells => more room for the
  // list). Capped so 7 cells always fit the popover width.
  static const double _minCell = 30;
  static const double _maxCell = 44;
  double _cellSize = _maxCell;

  MenuBarController get _c => widget.controller;

  void _onDividerDrag(double dy) {
    setState(() {
      // Dragging down grows the calendar (bigger cells), up shrinks it.
      _cellSize = (_cellSize + dy / 6).clamp(_minCell, _maxCell);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PanelHeader(),
          Divider(height: 1, color: c.border),
          Expanded(
            child: ListenableBuilder(
              listenable: _c,
              builder: (context, _) => _buildBody(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final c = context.colors;
    if (_c.isLoading) {
      return Center(child: CircularProgressIndicator(color: c.accent));
    }
    final editing = _c.editingNote;
    return Stack(
      children: [
        _buildListView(context),
        if (editing != null)
          Positioned.fill(child: _buildEditorOverlay(context, editing)),
        if (_c.notice != null)
          Positioned(
            left: AppDimensions.spacingMd,
            right: AppDimensions.spacingMd,
            bottom: AppDimensions.spacingMd,
            child: _NoticeBanner(message: _c.notice!),
          ),
      ],
    );
  }

  Widget _buildListView(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CalendarSection(
          displayedMonth: _c.displayedMonth,
          selectedDate: _c.selectedDate,
          datesWithNotes: _c.datesWithNotes,
          isExpanded: _calendarExpanded,
          onToggleExpand: () =>
              setState(() => _calendarExpanded = !_calendarExpanded),
          onDateSelected: _c.selectDate,
          onPreviousMonth: _c.previousMonth,
          onNextMonth: _c.nextMonth,
          onDateSecondaryTap: _showAddMenu,
          squareCellSize: _cellSize,
        ),
        _ResizableDivider(
          key: const ValueKey('calendar-list-divider'),
          onDragDelta: _onDividerDrag,
        ),
        _buildTabs(context),
        Expanded(child: _buildNoteList(context)),
      ],
    );
  }

  Widget _buildTabs(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.spacingMd,
        AppDimensions.spacingSm,
        AppDimensions.spacingSm,
        AppDimensions.spacingSm,
      ),
      child: Row(
        children: [
          _TabChip(
            label: 'Notes',
            active: !_c.memoTabActive,
            onTap: () => _c.setMemoTab(false),
          ),
          const SizedBox(width: AppDimensions.spacingXs),
          _TabChip(
            label: 'Memo',
            active: _c.memoTabActive,
            onTap: () => _c.setMemoTab(true),
          ),
          const Spacer(),
          // 메인 창 리스트 헤더와 같은 추가 메뉴 — 동기화/로컬 × 노트/메모.
          AddNoteMenuButton(
            onCreateSync: ({bool memo = false}) => _c.createNote(memo: memo),
            onCreateLocal: _c.hasLocalStorage
                ? ({bool memo = false}) =>
                    _c.createNote(memo: memo, local: true)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildNoteList(BuildContext context) {
    final notes = _c.visibleNotes;
    if (notes.isEmpty) return _buildEmpty(context);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppDimensions.spacingXs),
      itemCount: notes.length,
      itemBuilder: (context, i) {
        final note = notes[i];
        return _NoteRow(
          key: ValueKey(note.id),
          note: note,
          onTap: () => _c.openNote(note),
          onSecondaryTapUp: (position) =>
              _showNoteMenu(context, note, position),
        );
      },
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final c = context.colors;
    final isMemo = _c.memoTabActive;
    // Center when there's room; scroll when the list area is short (e.g. a
    // 6-week month leaves little space) so the empty state never overflows.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppDimensions.spacingLg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isMemo
                        ? Icons.sticky_note_2_outlined
                        : Icons.event_note_outlined,
                    size: 28,
                    color: c.textMuted,
                  ),
                  const SizedBox(height: AppDimensions.spacingSm),
                  Text(
                    isMemo ? '메모가 없습니다' : '이 날짜에 노트가 없습니다',
                    style:
                        AppTextStyles.microMedium.copyWith(color: c.textSecondary),
                  ),
                  const SizedBox(height: AppDimensions.spacingXs),
                  Text(
                    // Memos are date-independent, so the right-click-a-date hint
                    // only applies to daily notes.
                    isMemo ? '+ 로 메모 추가' : '날짜를 우클릭하거나 + 로 추가',
                    style: AppTextStyles.nanoSemibold.copyWith(color: c.textMuted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditorOverlay(BuildContext context, Note note) {
    final c = context.colors;
    // Entrance polish: fade + a small rise, one-shot on appear. No exit
    // animation (the overlay is simply removed), which keeps the Stack robust.
    return TweenAnimationBuilder<double>(
      key: ValueKey(note.id),
      tween: Tween(begin: 0, end: 1),
      duration: AppDimensions.animFast,
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 8), child: child),
      ),
      child: Material(
        color: c.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildEditorHeader(context, note),
            Divider(height: 1, color: c.border),
            Expanded(
              child: Builder(builder: (context) {
                // Same rule as the document screen: with sync off, synced
                // notes are read-only (editing would still commit to GitHub).
                final isReadOnly = note.storageType != StorageType.local &&
                    !widget.settings.value.syncEnabled;
                final imageService = _imageServiceFor(note);
                return EditorPanel(
                  key: _editorKey,
                  note: note,
                  onNoteChanged: _c.updateNote,
                  isReadOnly: isReadOnly,
                  contentScale: widget.settings.value.contentScale,
                  onIncreaseContentScale: widget.settings.increaseContentScale,
                  onDecreaseContentScale: widget.settings.decreaseContentScale,
                  onSetContentScale: widget.settings.setContentScale,
                  // 메인 창과 동일한 이미지 로드/첨부 와이어링 — 팝오버에서도
                  // 인라인 이미지 표시와 붙여넣기/파일 첨부가 동작한다.
                  onLoadImage: imageService == null
                      ? null
                      : (src) => imageService.loadImage(
                          noteDate: note.noteDate, src: src),
                  onAttachImage: imageService == null || isReadOnly
                      ? null
                      : (Uint8List bytes, String ext) => imageService.saveImage(
                          noteDate: note.noteDate,
                          bytes: bytes,
                          extension: ext),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorHeader(BuildContext context, Note note) {
    final c = context.colors;
    // Just a back affordance + context label. The editable title lives in the
    // EditorPanel toolbar right below, so it is not duplicated here.
    final label = note.isMemo
        ? 'Memo'
        : DateFormat('yyyy-MM-dd').format(note.noteDate);
    return Container(
      height: 44,
      padding: const EdgeInsets.only(right: AppDimensions.spacingMd),
      color: c.surface,
      child: Row(
        children: [
          IconButton(
            icon:
                Icon(Icons.arrow_back_rounded, size: 18, color: c.textSecondary),
            onPressed: _c.closeEditor,
            tooltip: '뒤로',
            splashRadius: 16,
          ),
          const Spacer(),
          Text(
            label,
            style: AppTextStyles.nanoSemibold.copyWith(color: c.textMuted),
          ),
        ],
      ),
    );
  }

  /// 노트 우클릭 메뉴 — 메인 창 사이드바와 같은 항목(전환/이동/삭제)을
  /// 컨트롤러 액션에 연결한다. 로컬 스토리지가 없으면 전환 항목이 숨는다.
  void _showNoteMenu(BuildContext context, Note note, Offset position) {
    final hasLocal = _c.hasLocalStorage;
    showNoteContextMenu(
      context: context,
      position: position,
      note: note,
      onConvertToSynced:
          hasLocal ? () => unawaited(_c.convertNote(note)) : null,
      onConvertToLocal:
          hasLocal ? () => unawaited(_c.convertNote(note)) : null,
      onMoveToMemo: () => unawaited(_c.setMemo(note, true)),
      onMoveToDaily: () => unawaited(_c.setMemo(note, false)),
      onDelete: () => unawaited(_confirmAndDelete(note)),
    );
  }

  Future<void> _confirmAndDelete(Note note) async {
    if (!mounted) return;
    if (!await confirmNoteDelete(context, note)) return;
    await _c.deleteNote(note);
  }

  Future<void> _showAddMenu(DateTime date, Offset globalPosition) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final memo = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem<bool>(value: false, child: Text('노트 추가')),
        PopupMenuItem<bool>(value: true, child: Text('메모 추가')),
      ],
    );
    if (memo == null) return;
    // A note is date-scoped to the right-clicked day; a memo is date-independent,
    // so only re-select the date for the note branch (avoids tab/selection churn).
    if (!memo) _c.selectDate(date);
    await _c.createNote(memo: memo);
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingMd),
      color: c.surface,
      child: Row(
        children: [
          const AppLogoMark(size: 18),
          const SizedBox(width: AppDimensions.spacingSm),
          Text(
            'SimSync',
            style: Theme.of(context).textTheme.titleSmall!.copyWith(
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                  letterSpacing: -0.3,
                ),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spacingSm,
          vertical: AppDimensions.spacingXs,
        ),
        decoration: BoxDecoration(
          color: active ? c.accentSubtle : Colors.transparent,
          borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
        ),
        child: Text(
          label,
          style: AppTextStyles.microSemibold.copyWith(
            // badgeText is the token designed for text on accentSubtle — higher
            // contrast than accent, in both light and dark.
            color: active ? c.badgeText : c.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _NoteRow extends StatefulWidget {
  const _NoteRow({
    super.key,
    required this.note,
    required this.onTap,
    required this.onSecondaryTapUp,
  });

  final Note note;
  final VoidCallback onTap;

  /// 우클릭 시 전역 좌표를 넘긴다 (컨텍스트 메뉴 표시용).
  final ValueChanged<Offset> onSecondaryTapUp;

  @override
  State<_NoteRow> createState() => _NoteRowState();
}

class _NoteRowState extends State<_NoteRow> {
  bool _hovered = false;

  String get _preview {
    for (final line in widget.note.content.split('\n')) {
      final t = line.trim();
      if (t.isNotEmpty) return t;
    }
    return '내용 없음';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final note = widget.note;
    final title = note.title.trim().isEmpty ? 'Untitled' : note.title.trim();
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapUp: (details) =>
            widget.onSecondaryTapUp(details.globalPosition),
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingSm,
            vertical: 1,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingSm,
            vertical: AppDimensions.spacingSm,
          ),
          decoration: BoxDecoration(
            color: _hovered ? c.surfaceHover : Colors.transparent,
            borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (note.isDefault)
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: AppDimensions.spacingXs),
                  child: Icon(Icons.push_pin_rounded, size: 11, color: c.textMuted),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.microSemibold
                          .copyWith(color: c.textPrimary),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.nanoSemibold
                          .copyWith(color: c.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingMd,
        vertical: AppDimensions.spacingSm,
      ),
      decoration: BoxDecoration(
        color: c.textPrimary,
        borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
      ),
      child: Text(
        message,
        style: AppTextStyles.microMedium.copyWith(color: c.surface),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// The line between the calendar and the note list — draggable vertically to
/// resize the calendar (bigger/smaller cells) and give the list more or less
/// room. Highlights on hover / while dragging.
class _ResizableDivider extends StatefulWidget {
  const _ResizableDivider({super.key, required this.onDragDelta});

  final ValueChanged<double> onDragDelta;

  @override
  State<_ResizableDivider> createState() => _ResizableDividerState();
}

class _ResizableDividerState extends State<_ResizableDivider> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = _hovered || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) => setState(() => _dragging = true),
        onVerticalDragUpdate: (d) => widget.onDragDelta(d.delta.dy),
        onVerticalDragEnd: (_) => setState(() => _dragging = false),
        child: SizedBox(
          height: 7,
          child: Center(
            child: AnimatedContainer(
              duration: AppDimensions.animFast,
              height: active ? 2 : 1,
              color: active ? c.accent.withValues(alpha: 0.6) : c.border,
            ),
          ),
        ),
      ),
    );
  }
}
