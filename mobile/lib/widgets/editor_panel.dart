import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';

/// Editor content area for the mobile editor screen.
///
/// Provides a borderless title field, an expanding multiline monospace content
/// field, and a [Transform.scale] wrapper for pinch-zoom support.
class EditorPanel extends StatefulWidget {
  final TextEditingController titleController;
  final TextEditingController contentController;
  final double contentScale;
  final VoidCallback? onChanged;

  const EditorPanel({
    super.key,
    required this.titleController,
    required this.contentController,
    this.contentScale = 1.0,
    this.onChanged,
  });

  @override
  State<EditorPanel> createState() => _EditorPanelState();
}

class _EditorPanelState extends State<EditorPanel> {
  void _handleChange() {
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Column(
      children: [
        // Title field.
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingLg,
            vertical: AppDimensions.spacingMd,
          ),
          child: TextField(
            controller: widget.titleController,
            onChanged: (_) => _handleChange(),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: c.textPrimary),
            decoration: InputDecoration(
              hintText: 'Untitled',
              hintStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(color: c.textMuted),
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

        // Content field (expanded, monospace, scalable).
        Expanded(
          child: Transform.scale(
            scale: widget.contentScale,
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(AppDimensions.spacingLg),
              child: TextField(
                controller: widget.contentController,
                onChanged: (_) => _handleChange(),
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: AppTextStyles.codeMonoBody(1.0).copyWith(color: c.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Start writing in markdown...',
                  hintStyle: AppTextStyles.codeMono(size: 14).copyWith(color: c.textMuted),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
