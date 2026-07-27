import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';

/// 타이틀바에 뜨는 업데이트 알림 pill.
///
/// 다운로드 아이콘 + 새 버전 라벨을 누르면 릴리즈 페이지가 열리고, 오른쪽 X로
/// 닫는다. 앱이 자동 설치까지 하지는 않으므로(서명·공증 없는 DMG 배포) 라벨은
/// "재시작"이 아니라 "업데이트"로 두고, 실제 동작은 릴리즈 페이지 열기다.
class UpdateButton extends StatefulWidget {
  const UpdateButton({
    super.key,
    required this.version,
    required this.onOpen,
    required this.onDismiss,
  });

  /// 표시할 새 버전 태그 (`v0.3.2`).
  final String version;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  State<UpdateButton> createState() => _UpdateButtonState();
}

class _UpdateButtonState extends State<UpdateButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: _hovered ? c.surfaceHover : c.surfaceLight,
        borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: widget.onOpen,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.spacingSm),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.download_rounded, size: 14, color: c.accent),
                    const SizedBox(width: AppDimensions.spacingXs),
                    Text(
                      '업데이트 ${widget.version}',
                      style: AppTextStyles.microSemibold
                          .copyWith(color: c.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 닫기: 같은 버전은 다시 뜨지 않는다 (더 높은 버전이 나오면 다시 뜸).
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onDismiss,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(
                    left: 2, right: AppDimensions.spacingSm),
                child: Tooltip(
                  message: '이 버전 알림 숨기기',
                  child: Icon(Icons.close_rounded, size: 13, color: c.textMuted),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
