import 'package:flutter/material.dart';

import '../models/note.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';

/// 노트 리스트 공용 메뉴 모음 — 메인 창 사이드바와 메뉴바 팝오버가 같은
/// 추가 메뉴 / 우클릭 메뉴 / 삭제 확인을 쓰도록 한 곳에 둔다.

PopupMenuItem<String> _menuItem(
  BuildContext context, {
  required String value,
  required IconData icon,
  required Color iconColor,
  required String label,
  Color? labelColor,
}) {
  final c = context.colors;
  return PopupMenuItem(
    height: 32,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    value: value,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 6),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall!
                .copyWith(color: labelColor ?? c.textPrimary)),
      ],
    ),
  );
}

/// 노트/메모 추가 메뉴 버튼. 동기화/로컬 × 노트/메모 4종을 곧바로 만든다.
/// [onCreateLocal]이 null이면 동기화 항목 2종만 노출된다.
class AddNoteMenuButton extends StatelessWidget {
  const AddNoteMenuButton({
    super.key,
    required this.onCreateSync,
    this.onCreateLocal,
  });

  final void Function({bool memo}) onCreateSync;
  final void Function({bool memo})? onCreateLocal;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return PopupMenuButton<String>(
      onSelected: (value) {
        switch (value) {
          case 'sync':
            onCreateSync(memo: false);
          case 'local':
            onCreateLocal?.call(memo: false);
          case 'sync_memo':
            onCreateSync(memo: true);
          case 'local_memo':
            onCreateLocal?.call(memo: true);
        }
      },
      offset: const Offset(0, 28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
        side: BorderSide(color: c.border),
      ),
      color: c.surface,
      itemBuilder: (context) => [
        _menuItem(context,
            value: 'sync',
            icon: Icons.cloud_outlined,
            iconColor: c.accent,
            label: '동기화 노트'),
        if (onCreateLocal != null)
          _menuItem(context,
              value: 'local',
              icon: Icons.folder_outlined,
              iconColor: c.localAccent,
              label: '로컬 노트'),
        _menuItem(context,
            value: 'sync_memo',
            icon: Icons.sticky_note_2_outlined,
            iconColor: c.accent,
            label: '동기화 메모'),
        if (onCreateLocal != null)
          _menuItem(context,
              value: 'local_memo',
              icon: Icons.sticky_note_2_outlined,
              iconColor: c.localAccent,
              label: '로컬 메모'),
      ],
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: c.accentSubtle,
          borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
        ),
        child: Icon(Icons.add_rounded, size: 14, color: c.accent),
      ),
    );
  }
}

/// 노트 항목 우클릭 컨텍스트 메뉴. 항목은 노트 상태(storageType/isMemo)와
/// 전달된 콜백 유무로 결정된다 — 콜백이 null이면 해당 항목이 숨는다.
Future<void> showNoteContextMenu({
  required BuildContext context,
  required Offset position,
  required Note note,
  VoidCallback? onConvertToSynced,
  VoidCallback? onConvertToLocal,
  VoidCallback? onMoveToMemo,
  VoidCallback? onMoveToDaily,
  VoidCallback? onDelete,
}) async {
  final c = context.colors;
  final items = <PopupMenuEntry<String>>[
    if (note.storageType == StorageType.local && onConvertToSynced != null)
      _menuItem(context,
          value: 'convert_to_synced',
          icon: Icons.cloud_upload_outlined,
          iconColor: c.accent,
          label: '동기화 노트로 전환'),
    if (note.storageType == StorageType.synced && onConvertToLocal != null)
      _menuItem(context,
          value: 'convert_to_local',
          icon: Icons.cloud_download_outlined,
          iconColor: c.localAccent,
          label: '로컬 노트로 전환'),
    if (!note.isMemo && onMoveToMemo != null)
      _menuItem(context,
          value: 'move_to_memo',
          icon: Icons.sticky_note_2_outlined,
          iconColor: c.textSecondary,
          label: '메모로 이동'),
    if (note.isMemo && onMoveToDaily != null)
      _menuItem(context,
          value: 'move_to_daily',
          icon: Icons.calendar_today_outlined,
          iconColor: c.textSecondary,
          label: 'daily로 이동'),
    if (onDelete != null)
      _menuItem(context,
          value: 'delete',
          icon: Icons.delete_outline_rounded,
          iconColor: c.error,
          label: '삭제',
          labelColor: c.error),
  ];
  if (items.isEmpty) return;

  final value = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
        position.dx, position.dy, position.dx, position.dy),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
      side: BorderSide(color: c.border),
    ),
    color: c.surface,
    menuPadding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 120),
    items: items,
  );
  switch (value) {
    case 'convert_to_synced':
      onConvertToSynced?.call();
    case 'convert_to_local':
      onConvertToLocal?.call();
    case 'move_to_memo':
      onMoveToMemo?.call();
    case 'move_to_daily':
      onMoveToDaily?.call();
    case 'delete':
      onDelete?.call();
  }
}

/// 노트 삭제 확인 다이얼로그. true를 돌려주면 삭제를 진행한다.
Future<bool> confirmNoteDelete(BuildContext context, Note note) async {
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
        titlePadding: const EdgeInsets.fromLTRB(
            AppDimensions.spacingLg, 14, AppDimensions.spacingLg, 0),
        contentPadding: const EdgeInsets.fromLTRB(AppDimensions.spacingLg,
            AppDimensions.spacingSm, AppDimensions.spacingLg, 0),
        actionsPadding: const EdgeInsets.fromLTRB(AppDimensions.spacingMd,
            AppDimensions.spacingSm, AppDimensions.spacingMd,
            AppDimensions.spacingMd),
        title: Text(
          '노트 삭제',
          style: Theme.of(ctx)
              .textTheme
              .titleSmall!
              .copyWith(fontWeight: FontWeight.w600, color: c.textPrimary),
        ),
        content: Text(
          "'${note.title.isEmpty ? 'Untitled' : note.title}' 노트를 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.",
          style: AppTextStyles.captionThin.copyWith(color: c.textSecondary),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: c.textSecondary,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: AppTextStyles.captionMedium,
            ),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            // 삭제 확인만 위험 색을 쓴다. 나머지는 filledButtonTheme.
            style: FilledButton.styleFrom(backgroundColor: c.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}
