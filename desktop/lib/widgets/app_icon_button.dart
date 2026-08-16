import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import 'hover_builder.dart';

/// 아이콘 하나만 있는 버튼의 공용 구현.
///
/// 이 위젯이 생기기 전에는 화면마다 제 나름의 아이콘 버튼을 들고 있어서 반경이
/// 4/5/8/원형, 아이콘이 14/16/18, 탭 영역이 20~34px로 갈려 있었다. DESIGN.md
/// §5의 "Micro (4px): Buttons, inputs, functional interactive elements"를 따라
/// 반경은 4로 고정하고, 탭 영역과 아이콘 크기도 한 값으로 맞춘다.
///
/// [bordered]는 표면 위에 얹혀 경계가 필요한 경우(에디터 툴바, 설정 스텝퍼)에
/// 배경과 테두리를 준다. 나머지는 호버할 때만 배경이 뜬다.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.bordered = false,
    this.enabled = true,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool bordered;
  final bool enabled;

  /// 탭 영역 한 변 (아이콘 16 + 좌우 여백 4).
  static const double size = 24;
  static const double iconSize = 16;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final button = HoverBuilder(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      builder: (context, hovered) => GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppDimensions.animFast,
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: hovered && enabled
                ? c.surfaceHover
                : bordered
                    ? c.surfaceLight
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
            border: bordered ? Border.all(color: c.border) : null,
          ),
          child: Icon(
            icon,
            size: iconSize,
            color: enabled ? c.textSecondary : c.textMuted,
          ),
        ),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
