import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/note.dart';
import '../settings/app_settings_controller.dart';
import '../storage/note_storage.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

class EditorScreen extends StatefulWidget {
  final Note note;
  final NoteStorage storage;
  final AppSettingsController settingsController;
  final void Function(Note updatedNote) onNoteChanged;
  final void Function(Note deletedNote) onNoteDeleted;

  const EditorScreen({
    super.key,
    required this.note,
    required this.storage,
    required this.settingsController,
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
  late TextEditingController _contentController;
  late TextEditingController _tagsController;
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
    _contentController = TextEditingController(text: _note.content);
    _tagsController = TextEditingController(text: _note.tags.join(', '));
    _previewScale = widget.settingsController.value.contentScale;
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _tabController.dispose();
    _titleController.dispose();
    _contentController.dispose();
    _tagsController.dispose();
    // Save any pending changes on exit.
    if (_isDirty) {
      _saveImmediately();
    }
    super.dispose();
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
          "'${_note.title.isEmpty ? 'Untitled' : _note.title}' 노트를 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.",
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

    if (confirmed != true || !mounted) return;

    try {
      await widget.storage.deleteNote(_note);
      widget.onNoteDeleted(_note);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 실패: $e')),
        );
      }
    }
  }

  // ── Markdown toolbar actions ──

  void _insertMarkdown(String before, [String after = '']) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    final start = selection.baseOffset.clamp(0, text.length);
    final end = selection.extentOffset.clamp(0, text.length);
    final selectedText = text.substring(start, end);

    final newText = text.replaceRange(
      start,
      end,
      '$before$selectedText$after',
    );
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: start + before.length + selectedText.length,
      ),
    );
    _onContentChanged(newText);
  }

  void _insertAtLineStart(String prefix) {
    final text = _contentController.text;
    final cursorPos = _contentController.selection.baseOffset.clamp(0, text.length);
    // Find the start of the current line.
    var lineStart = cursorPos;
    while (lineStart > 0 && text[lineStart - 1] != '\n') {
      lineStart--;
    }
    final newText = text.replaceRange(lineStart, lineStart, prefix);
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: cursorPos + prefix.length,
      ),
    );
    _onContentChanged(newText);
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
        style: GoogleFonts.manrope(
          fontSize: 15,
          fontWeight: FontWeight.w600,
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
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: c.textMuted,
                        ),
                      ),
                    ],
                  )
                : Text(
                    _isDirty ? '' : '저장됨',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
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
            borderRadius:
                BorderRadius.circular(AppDimensions.borderRadius),
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
                    style: GoogleFonts.manrope(
                      fontSize: 14,
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
        labelStyle: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
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
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppDimensions.spacingLg),
            child: Column(
              children: [
                // Title field
                TextField(
                  controller: _titleController,
                  onChanged: _onTitleChanged,
                  style: GoogleFonts.manrope(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: '제목',
                    hintStyle: TextStyle(
                      color: c.textMuted,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(height: AppDimensions.spacingSm),
                Divider(height: 1, color: c.borderSubtle),
                const SizedBox(height: AppDimensions.spacingSm),
                // Content field
                TextField(
                  controller: _contentController,
                  onChanged: _onContentChanged,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 14,
                    color: c.textPrimary,
                    height: 1.6,
                  ),
                  decoration: InputDecoration(
                    hintText: '마크다운으로 작성하세요...',
                    hintStyle: TextStyle(
                      color: c.textMuted,
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Markdown toolbar
        _buildMarkdownToolbar(c),
      ],
    );
  }

  Widget _buildMarkdownToolbar(AppColorsExtension c) {
    return Container(
      height: AppDimensions.toolbarHeight,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spacingSm,
        ),
        child: Row(
          children: [
            _ToolbarButton(
              label: 'H1',
              onTap: () => _insertAtLineStart('# '),
              colors: c,
            ),
            _ToolbarButton(
              label: 'H2',
              onTap: () => _insertAtLineStart('## '),
              colors: c,
            ),
            _ToolbarButton(
              label: 'H3',
              onTap: () => _insertAtLineStart('### '),
              colors: c,
            ),
            _ToolbarDivider(colors: c),
            _ToolbarButton(
              label: 'B',
              fontWeight: FontWeight.w800,
              onTap: () => _insertMarkdown('**', '**'),
              colors: c,
            ),
            _ToolbarButton(
              label: 'I',
              fontStyle: FontStyle.italic,
              onTap: () => _insertMarkdown('*', '*'),
              colors: c,
            ),
            _ToolbarButton(
              icon: Icons.code_rounded,
              onTap: () => _insertMarkdown('`', '`'),
              colors: c,
            ),
            _ToolbarDivider(colors: c),
            _ToolbarButton(
              icon: Icons.format_list_bulleted_rounded,
              onTap: () => _insertAtLineStart('- '),
              colors: c,
            ),
            _ToolbarButton(
              icon: Icons.check_box_outlined,
              onTap: () => _insertAtLineStart('- [ ] '),
              colors: c,
            ),
            _ToolbarButton(
              icon: Icons.format_quote_rounded,
              onTap: () => _insertAtLineStart('> '),
              colors: c,
            ),
            _ToolbarButton(
              icon: Icons.link_rounded,
              onTap: () => _insertMarkdown('[', '](url)'),
              colors: c,
            ),
          ],
        ),
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
      child: InteractiveViewer(
        minScale: 0.8,
        maxScale: 2.0,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppDimensions.spacingLg),
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: Markdown(
              data: _note.content.isEmpty
                  ? '_미리보기할 내용이 없습니다_'
                  : _note.content,
              selectable: true,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              styleSheet: MarkdownStyleSheet(
                h1: GoogleFonts.manrope(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
                h2: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
                h3: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
                p: TextStyle(
                  fontSize: 14,
                  color: c.textPrimary,
                  height: 1.6,
                ),
                code: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  color: c.accent,
                  backgroundColor: c.surfaceLight,
                ),
                codeblockDecoration: BoxDecoration(
                  color: c.surfaceLight,
                  borderRadius:
                      BorderRadius.circular(AppDimensions.borderRadius),
                  border: Border.all(color: c.border),
                ),
                blockquoteDecoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: c.accent, width: 3),
                  ),
                ),
                blockquotePadding: const EdgeInsets.only(
                  left: AppDimensions.spacingMd,
                ),
                listBullet: TextStyle(color: c.textSecondary),
                horizontalRuleDecoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: c.border, width: 1),
                  ),
                ),
              ),
            ),
          ),
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
            style: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: AppDimensions.spacingSm),
          Text(
            '쉼표(,)로 태그를 구분하세요',
            style: TextStyle(fontSize: 13, color: c.textMuted),
          ),
          const SizedBox(height: AppDimensions.spacingMd),
          TextField(
            controller: _tagsController,
            onChanged: _onTagsChanged,
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: c.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'work, daily, idea',
              hintStyle: TextStyle(color: c.textMuted),
              prefixIcon:
                  Icon(Icons.tag_rounded, size: 18, color: c.textMuted),
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
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: c.accentSubtle,
                    borderRadius: BorderRadius.circular(
                      AppDimensions.borderRadius,
                    ),
                    border:
                        Border.all(color: c.accent.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '#$tag',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
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

  const _ToolbarButton({
    this.label,
    this.icon,
    required this.onTap,
    required this.colors,
    this.fontWeight,
    this.fontStyle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 36,
        alignment: Alignment.center,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          borderRadius:
              BorderRadius.circular(AppDimensions.borderRadiusSm),
        ),
        child: icon != null
            ? Icon(icon, size: 18, color: colors.textSecondary)
            : Text(
                label ?? '',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: fontWeight ?? FontWeight.w600,
                  fontStyle: fontStyle,
                  color: colors.textSecondary,
                ),
              ),
      ),
    );
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
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: colors.borderSubtle,
    );
  }
}
