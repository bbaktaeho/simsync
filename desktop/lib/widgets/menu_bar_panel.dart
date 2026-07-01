import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';
import 'app_logo_mark.dart';

/// The compact popover shown from the macOS menu bar.
///
/// Phase 2 renders the panel chrome only; the calendar, per-date note list
/// (with memo tab), right-click add, and editor overlay arrive in Phase 3.
class MenuBarPanel extends StatelessWidget {
  const MenuBarPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(),
          Divider(height: 1, color: c.border),
          Expanded(
            child: Center(
              child: Text(
                'SimSync',
                style: AppTextStyles.microMedium.copyWith(color: c.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingMd),
      color: c.surface,
      child: Row(
        children: [
          const AppLogoMark(size: 20),
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
