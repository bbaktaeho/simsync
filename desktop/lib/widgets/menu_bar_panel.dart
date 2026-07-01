import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/note.dart';
import '../services/menu_bar_controller.dart';
import '../settings/app_settings_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';
import 'app_logo_mark.dart';
import 'calendar_section.dart';
import 'editor_panel.dart';

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

  MenuBarController get _c => widget.controller;

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
    final c = context.colors;
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
        ),
        Divider(height: 1, color: c.border),
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
          _AddButton(
            onTap: () => _c.createNote(memo: _c.memoTabActive),
            tooltip: _c.memoTabActive ? '메모 추가' : '노트 추가',
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
        return _NoteRow(note: note, onTap: () => _c.openNote(note));
      },
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final c = context.colors;
    final isMemo = _c.memoTabActive;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isMemo ? Icons.sticky_note_2_outlined : Icons.event_note_outlined,
              size: 28,
              color: c.textMuted,
            ),
            const SizedBox(height: AppDimensions.spacingSm),
            Text(
              isMemo ? '메모가 없습니다' : '이 날짜에 노트가 없습니다',
              style: AppTextStyles.microMedium.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: AppDimensions.spacingXs),
            Text(
              '날짜를 우클릭하거나 + 로 추가',
              style: AppTextStyles.nanoSemibold.copyWith(color: c.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
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
              child: EditorPanel(
                note: note,
                onNoteChanged: _c.updateNote,
                contentScale: widget.settings.value.contentScale,
                onIncreaseContentScale: widget.settings.increaseContentScale,
                onDecreaseContentScale: widget.settings.decreaseContentScale,
                onSetContentScale: widget.settings.setContentScale,
              ),
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

  Future<void> _showAddMenu(DateTime date, Offset globalPosition) async {
    _c.selectDate(date);
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
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
    if (memo != null) await _c.createNote(memo: memo);
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
            color: active ? c.accent : c.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap, required this.tooltip});

  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return IconButton(
      icon: Icon(Icons.add_rounded, size: 18, color: c.textSecondary),
      onPressed: onTap,
      tooltip: tooltip,
      splashRadius: 16,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _NoteRow extends StatefulWidget {
  const _NoteRow({required this.note, required this.onTap});

  final Note note;
  final VoidCallback onTap;

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
