import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_text_styles.dart';

import '../models/note.dart';
import '../services/image_asset_service.dart';
import '../services/markdown_editing.dart';
import '../settings/app_settings_controller.dart';
import '../storage/github/github_note_storage.dart';
import '../storage/note_storage.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../widgets/editor_panel.dart';
import '../widgets/markdown_editing_controller.dart';
import '../widgets/markdown_preview.dart';

class EditorScreen extends StatefulWidget {
  final Note note;
  final NoteStorage storage;
  final AppSettingsController settingsController;
  final ValueNotifier<int>? refreshSignal;
  final void Function(Note updatedNote) onNoteChanged;
  final void Function(Note deletedNote) onNoteDeleted;

  const EditorScreen({
    super.key,
    required this.note,
    required this.storage,
    required this.settingsController,
    this.refreshSignal,
    required this.onNoteChanged,
    required this.onNoteDeleted,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _titleController;
  late MarkdownEditingController _contentController;
  late TextEditingController _tagsController;
  final FocusNode _contentFocusNode = FocusNode();

  /// 노트 본문의 상대 src('assets/…') 이미지를 읽는다. 원격(GitHub) 스토리지는
  /// 디스크 캐시를 써서 앱 재시작 후에도 네트워크 재요청 없이 뜬다.
  late final ImageAssetService _imageService = ImageAssetService(
    storage: widget.storage,
    useDiskCache: widget.storage is GitHubNoteStorage,
  );
  late Note _note;
  Timer? _saveDebounce;
  bool _isSaving = false;
  bool _isDirty = false;
  double _previewScale = 1.0;

  static final DateFormat _dateFmt = DateFormat('M월 d일 EEEE', 'ko');

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _tabController = TabController(length: 3, vsync: this);
    _titleController = TextEditingController(text: _note.title);
    _contentController = MarkdownEditingController(text: _note.content);
    _tagsController = TextEditingController(text: _note.tags.join(', '));
    _previewScale = widget.settingsController.value.contentScale;
    widget.refreshSignal?.addListener(_handleRefreshSignal);
  }

  @override
  void didUpdateWidget(covariant EditorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSignal != widget.refreshSignal) {
      oldWidget.refreshSignal?.removeListener(_handleRefreshSignal);
      widget.refreshSignal?.addListener(_handleRefreshSignal);
    }
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_handleRefreshSignal);
    _saveDebounce?.cancel();
    // Save pending changes on exit. Must be dispose-safe: no setState calls
    // (State is unmounting) and snapshots of storage/note/callback so the
    // in-flight save survives teardown. _saveImmediately is unsafe here because
    // it calls setState in its body and after await.
    if (_isDirty) {
      final noteToSave = _note;
      final storage = widget.storage;
      final notify = widget.onNoteChanged;
      storage
          .saveNote(noteToSave)
          .then((_) => notify(noteToSave))
          .catchError((_) {
        // Silent: widget unmounted; persisted state remains in-memory and on
        // the next mount the note will be reloaded from storage.
      });
    }
    _tabController.dispose();
    _contentFocusNode.dispose();
    _titleController.dispose();
    _contentController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _handleRefreshSignal() async {
    if (_isDirty || _isSaving) return;

    final latestNotes = await widget.storage.listNotes(_note.noteDate);
    final matches = latestNotes.where((note) => note.id == _note.id);
    if (matches.isEmpty || !mounted) return;

    final latest = matches.first;
    if (latest.title == _note.title &&
        latest.content == _note.content &&
        latest.tags.join(',') == _note.tags.join(',')) {
      return;
    }

    setState(() {
      _note = latest;
      _titleController.text = latest.title;
      _contentController.text = latest.content;
      _tagsController.text = latest.tags.join(', ');
    });
  }

  void _onTitleChanged(String value) {
    _note.title = value;
    _note.updatedAt = DateTime.now();
    _isDirty = true;
    _scheduleSave();
  }

  void _onContentChanged(String value) {
    _note.content = value;
    _note.updatedAt = DateTime.now();
    _isDirty = true;
    _scheduleSave();
  }

  void _onTagsChanged(String value) {
    final tags = value
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    _note.tags = tags;
    _note.updatedAt = DateTime.now();
    _isDirty = true;
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 1), () {
      _saveImmediately();
    });
  }

  Future<void> _saveImmediately() async {
    if (!_isDirty) return;
    setState(() => _isSaving = true);
    try {
      await widget.storage.saveNote(_note);
      _isDirty = false;
      widget.onNoteChanged(_note);
    } catch (_) {
      // Silently fail; note stays dirty.
    }
    if (mounted) {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteNote() async {
    final c = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusComfortable),
          side: BorderSide(color: c.border),
        ),
        title: Text(
          '노트 삭제',
          style: Theme.of(context).textTheme.labelLarge!.copyWith(
            color: c.textPrimary,
          ),
        ),
        content: Text(
          "'${_note.title.isEmpty ? 'Untitled' : _note.title}' 노트를 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.",
          style: Theme.of(context).textTheme.bodySmall!.copyWith(
            color: c.textSecondary,
          ),
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

    if (confirmed != true || !mounted) return;

    try {
      await widget.storage.deleteNote(_note);
      widget.onNoteDeleted(_note);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
      }
    }
  }

  // ── Markdown toolbar actions ──
  //
  // 모바일은 타이핑이 비싸다. 자주 쓰는 문법은 전부 버튼으로 만들고, 데스크탑의
  // Tab 들여쓰기도 버튼으로 대신한다. 편집 연산은 데스크탑과 같은 서비스 함수를
  // 쓰므로 두 플랫폼의 동작이 어긋나지 않는다.

  void _apply(TextEditingValue updated) {
    if (updated == _contentController.value) return;
    _contentController.value = updated;
    _onContentChanged(_contentController.text);
  }

  /// 줄 머리 블록 프리픽스 토글 (같은 것 다시 누르면 해제, 다른 종류면 교체).
  void _toggleLinePrefix(String prefix) =>
      _apply(toggleLinePrefix(_contentController.value, prefix));

  /// 선택을 인라인 마커로 감싸거나 벗긴다.
  void _wrapSelection(String marker) =>
      _apply(wrapSelection(_contentController.value, marker));

  /// 리스트 들여쓰기/내어쓰기 — 데스크탑 Tab / Shift+Tab의 모바일 대체.
  void _indent({required bool outdent}) {
    final updated =
        indentListSelection(_contentController.value, outdent: outdent);
    if (updated == null) return; // 리스트 줄이 아니면 무시
    _apply(updated);
  }

  /// 앞뒤 문자열이 다른 삽입 (링크처럼). 선택이 있으면 그것을 감싼다.
  void _wrapSelection2(String before, String after) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    if (!selection.isValid) return;
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(start, text.length);
    final selected = text.substring(start, end);
    _apply(TextEditingValue(
      text: text.replaceRange(start, end, '$before$selected$after'),
      selection: TextSelection.collapsed(
        offset: selected.isEmpty
            ? start + before.length
            : start + before.length + selected.length + after.length,
      ),
    ));
  }

  /// 캐럿이 있는 줄 뒤에 블록을 통째로 삽입한다 (표, 구분선, 코드 펜스).
  void _insertBlock(String block) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    final caret =
        (selection.isValid ? selection.baseOffset : text.length).clamp(0, text.length);
    final needsLeadingNewline = caret > 0 && text[caret - 1] != '\n';
    final insertion = '${needsLeadingNewline ? '\n' : ''}$block\n';
    _apply(TextEditingValue(
      text: text.replaceRange(caret, caret, insertion),
      selection: TextSelection.collapsed(offset: caret + insertion.length),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.scaffold,
      appBar: _buildAppBar(c),
      body: Column(
        children: [
          _buildTabBar(c),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildEditorTab(c),
                _buildPreviewTab(c),
                _buildTagsTab(c),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(AppColorsExtension c) {
    return AppBar(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_rounded, color: c.textPrimary),
        onPressed: () {
          if (_isDirty) {
            _saveImmediately();
          }
          Navigator.pop(context);
        },
      ),
      title: Text(
        _dateFmt.format(_note.noteDate),
        style: Theme.of(context).textTheme.titleMedium!.copyWith(
          color: c.textPrimary,
        ),
      ),
      actions: [
        // Save status
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingSm,
          ),
          child: Center(
            child: _isSaving
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: c.accent,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '저장 중...',
                        style: Theme.of(context).textTheme.labelSmall!.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  )
                : Text(
                    _isDirty ? '' : '저장됨',
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      color: c.success,
                    ),
                  ),
          ),
        ),
        // More menu
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, color: c.textSecondary),
          color: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
            side: BorderSide(color: c.border),
          ),
          onSelected: (value) {
            if (value == 'delete') {
              _deleteNote();
            }
          },
          itemBuilder: (ctx) => [
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline_rounded, size: 18, color: c.error),
                  const SizedBox(width: AppDimensions.spacingSm),
                  Text(
                    '삭제',
                    style: Theme.of(ctx).textTheme.bodySmall!.copyWith(
                      color: c.error,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTabBar(AppColorsExtension c) {
    return Container(
      color: c.surface,
      child: TabBar(
        controller: _tabController,
        labelColor: c.accent,
        unselectedLabelColor: c.textMuted,
        indicatorColor: c.accent,
        indicatorWeight: 2,
        labelStyle: Theme.of(context).textTheme.labelLarge,
        unselectedLabelStyle: Theme.of(context).textTheme.titleSmall,
        tabs: const [
          Tab(text: 'Editor'),
          Tab(text: 'Preview'),
          Tab(text: 'Tags'),
        ],
      ),
    );
  }

  Widget _buildEditorTab(AppColorsExtension c) {
    return Column(
      children: [
        // 제목은 고정 헤더 (데스크탑과 같은 배치). 본문만 스크롤한다.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimensions.spacingLg,
            AppDimensions.spacingLg,
            AppDimensions.spacingLg,
            AppDimensions.spacingSm,
          ),
          child: TextField(
            controller: _titleController,
            onChanged: _onTitleChanged,
            style: Theme.of(context).textTheme.titleLarge!.copyWith(
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: '제목',
              hintStyle: Theme.of(context).textTheme.titleLarge!.copyWith(
                fontWeight: FontWeight.w700,
                color: c.textMuted,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.zero,
              isDense: true,
            ),
          ),
        ),
        Divider(height: 1, color: c.borderSubtle),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppDimensions.spacingLg),
            // 설정의 콘텐츠 배율을 즉시 반영한다 (구독하지 않으면 다른 이유로
            // 리빌드될 때까지 옛 배율로 남는다).
            child: ListenableBuilder(
              listenable: widget.settingsController,
              builder: (context, _) => EditorPanel(
                controller: _contentController,
                focusNode: _contentFocusNode,
                contentScale: widget.settingsController.value.contentScale,
                onChanged: () => _onContentChanged(_contentController.text),
                onLoadImage: (src) => _imageService.loadImage(
                  noteDate: _note.noteDate,
                  src: src,
                ),
              ),
            ),
          ),
        ),
        // Markdown toolbar
        _buildMarkdownToolbar(c),
      ],
    );
  }

  /// 하단 마크다운 툴바. 자주 쓰는 순서로 배치하고 가로 스크롤한다.
  /// (모바일에는 Tab이 없으므로 들여쓰기/내어쓰기도 여기 둔다.)
  Widget _buildMarkdownToolbar(AppColorsExtension c) {
    return Container(
      height: AppDimensions.toolbarHeight,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.spacingSm,
              ),
              child: Row(
                children: [
                  // 가장 자주 쓰는 것부터: 할 일 → 불릿 → 번호
                  _ToolbarButton(
                    icon: Icons.check_box_outlined,
                    tooltip: '할 일',
                    onTap: () => _toggleLinePrefix('- [ ] '),
                    colors: c,
                  ),
                  _ToolbarButton(
                    icon: Icons.format_list_bulleted_rounded,
                    tooltip: '목록',
                    onTap: () => _toggleLinePrefix('- '),
                    colors: c,
                  ),
                  _ToolbarButton(
                    icon: Icons.format_list_numbered_rounded,
                    tooltip: '번호 목록',
                    onTap: () => _toggleLinePrefix('1. '),
                    colors: c,
                  ),
                  _ToolbarDivider(colors: c),
                  // Tab 대체
                  _ToolbarButton(
                    icon: Icons.format_indent_decrease_rounded,
                    tooltip: '내어쓰기',
                    onTap: () => _indent(outdent: true),
                    colors: c,
                  ),
                  _ToolbarButton(
                    icon: Icons.format_indent_increase_rounded,
                    tooltip: '들여쓰기',
                    onTap: () => _indent(outdent: false),
                    colors: c,
                  ),
                  _ToolbarDivider(colors: c),
                  _ToolbarButton(
                    label: 'H1',
                    onTap: () => _toggleLinePrefix('# '),
                    colors: c,
                  ),
                  _ToolbarButton(
                    label: 'H2',
                    onTap: () => _toggleLinePrefix('## '),
                    colors: c,
                  ),
                  _ToolbarButton(
                    label: 'H3',
                    onTap: () => _toggleLinePrefix('### '),
                    colors: c,
                  ),
                  _ToolbarDivider(colors: c),
                  _ToolbarButton(
                    label: 'B',
                    fontWeight: FontWeight.w800,
                    onTap: () => _wrapSelection('**'),
                    colors: c,
                  ),
                  _ToolbarButton(
                    label: 'I',
                    fontStyle: FontStyle.italic,
                    onTap: () => _wrapSelection('*'),
                    colors: c,
                  ),
                  _ToolbarButton(
                    icon: Icons.format_strikethrough_rounded,
                    tooltip: '취소선',
                    onTap: () => _wrapSelection('~~'),
                    colors: c,
                  ),
                  _ToolbarButton(
                    icon: Icons.format_color_fill_rounded,
                    tooltip: '형광펜',
                    onTap: () => _wrapSelection('=='),
                    colors: c,
                  ),
                  _ToolbarButton(
                    icon: Icons.code_rounded,
                    tooltip: '인라인 코드',
                    onTap: () => _wrapSelection('`'),
                    colors: c,
                  ),
                  _ToolbarDivider(colors: c),
                  // 이 앱의 인용문 문법은 `| `다 (`> `는 details 트리거).
                  _ToolbarButton(
                    icon: Icons.format_quote_rounded,
                    tooltip: '인용',
                    onTap: () => _toggleLinePrefix('| '),
                    colors: c,
                  ),
                  _ToolbarButton(
                    icon: Icons.link_rounded,
                    tooltip: '링크',
                    onTap: () => _wrapSelection2('[', '](url)'),
                    colors: c,
                  ),
                  _ToolbarButton(
                    icon: Icons.data_object_rounded,
                    tooltip: '코드 블록',
                    onTap: () => _insertBlock('```\n\n```'),
                    colors: c,
                  ),
                  _ToolbarButton(
                    icon: Icons.table_chart_outlined,
                    tooltip: '표',
                    onTap: () => _insertBlock(
                      '| 항목 | 값 |\n| --- | --- |\n|  |  |',
                    ),
                    colors: c,
                  ),
                  _ToolbarButton(
                    icon: Icons.horizontal_rule_rounded,
                    tooltip: '구분선',
                    onTap: () => _insertBlock('---'),
                    colors: c,
                  ),
                ],
              ),
            ),
          ),
          // 스크롤에 딸려가지 않게 오른쪽에 고정 — 자주 누른다.
          _ToolbarDivider(colors: c),
          _ToolbarButton(
            icon: Icons.keyboard_hide_rounded,
            tooltip: '키보드 닫기',
            onTap: () => _contentFocusNode.unfocus(),
            colors: c,
          ),
          const SizedBox(width: AppDimensions.spacingSm),
        ],
      ),
    );
  }

  Widget _buildPreviewTab(AppColorsExtension c) {
    final scale = _previewScale.clamp(0.8, 2.0);

    return GestureDetector(
      onScaleUpdate: (details) {
        setState(() {
          _previewScale = (_previewScale * details.scale).clamp(0.8, 2.0);
        });
      },
      child: Container(
        width: double.infinity,
        color: c.scaffold,
        child: MarkdownPreview(
          title: _titleController.text.trim(),
          content: _contentController.text.isEmpty
              ? '_미리보기할 내용이 없습니다_'
              : _contentController.text,
          contentScale: scale,
        ),
      ),
    );
  }

  Widget _buildTagsTab(AppColorsExtension c) {
    return Padding(
      padding: const EdgeInsets.all(AppDimensions.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '태그',
            style: Theme.of(context).textTheme.labelLarge!.copyWith(
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: AppDimensions.spacingSm),
          Text(
            '쉼표(,)로 태그를 구분하세요',
            style: AppTextStyles.caption.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: AppDimensions.spacingMd),
          TextField(
            controller: _tagsController,
            onChanged: _onTagsChanged,
            style: Theme.of(context).textTheme.bodySmall!.copyWith(
              color: c.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'work, daily, idea',
              hintStyle: TextStyle(color: c.textMuted),
              prefixIcon: Icon(Icons.tag_rounded, size: 18, color: c.textMuted),
            ),
          ),
          const SizedBox(height: AppDimensions.spacingLg),
          if (_note.tags.isNotEmpty)
            Wrap(
              spacing: AppDimensions.spacingSm,
              runSpacing: AppDimensions.spacingSm,
              children: _note.tags.map((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.spacingMd,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: c.accentSubtle,
                    borderRadius: BorderRadius.circular(
                      AppDimensions.radiusStandard,
                    ),
                    border: Border.all(color: c.accent.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '#$tag',
                    style: AppTextStyles.captionMedium.copyWith(
                      color: c.accent,
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

// ── Toolbar Widgets ──

class _ToolbarButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final AppColorsExtension colors;
  final FontWeight? fontWeight;
  final FontStyle? fontStyle;

  /// 길게 눌렀을 때 뜨는 설명. 아이콘만으로는 뜻이 안 보이는 버튼에 붙인다.
  final String? tooltip;

  const _ToolbarButton({
    this.label,
    this.icon,
    required this.onTap,
    required this.colors,
    this.fontWeight,
    this.fontStyle,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        // 손가락 타깃. 툴바 높이(48) 안에서 최대한 키운다.
        height: 44,
        alignment: Alignment.center,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
        ),
        child: icon != null
            ? Icon(icon, size: 18, color: colors.textSecondary)
            : Text(
                label ?? '',
                style: Theme.of(context).textTheme.labelLarge!.copyWith(
                  fontWeight: fontWeight ?? FontWeight.w600,
                  fontStyle: fontStyle,
                  color: colors.textSecondary,
                ),
              ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

class _ToolbarDivider extends StatelessWidget {
  final AppColorsExtension colors;

  const _ToolbarDivider({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXs),
      color: colors.borderSubtle,
    );
  }
}
