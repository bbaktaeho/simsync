import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';

/// Keyboard accessory toolbar that inserts markdown syntax into a
/// [TextEditingController].
///
/// Renders a horizontal scrollable row of grouped buttons separated by
/// vertical dividers.
class MarkdownToolbar extends StatelessWidget {
  final TextEditingController textController;
  final VoidCallback? onChanged;

  const MarkdownToolbar({
    super.key,
    required this.textController,
    this.onChanged,
  });

  // ── Markdown insertion helpers ──

  /// Insert [prefix] at the start of the current line.
  void _insertAtLineStart(String prefix) {
    final text = textController.text;
    final selection = textController.selection;
    final cursorPos = selection.baseOffset.clamp(0, text.length);

    // Find the start of the current line.
    final lineStart = text.lastIndexOf('\n', cursorPos - 1) + 1;

    final newText = text.substring(0, lineStart) +
        prefix +
        text.substring(lineStart);

    textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: cursorPos + prefix.length,
      ),
    );
    onChanged?.call();
  }

  /// Wrap the current selection with [before] and [after].
  /// If nothing is selected, insert both markers and place cursor between them.
  void _wrapSelection(String before, String after) {
    final text = textController.text;
    final selection = textController.selection;

    if (!selection.isValid) {
      // Append at end if no valid selection.
      textController.value = TextEditingValue(
        text: '$text$before$after',
        selection: TextSelection.collapsed(
          offset: text.length + before.length,
        ),
      );
      onChanged?.call();
      return;
    }

    final start = selection.start;
    final end = selection.end;
    final selectedText = text.substring(start, end);

    final newText = text.substring(0, start) +
        before +
        selectedText +
        after +
        text.substring(end);

    textController.value = TextEditingValue(
      text: newText,
      selection: selectedText.isEmpty
          ? TextSelection.collapsed(offset: start + before.length)
          : TextSelection(
              baseOffset: start + before.length,
              extentOffset: start + before.length + selectedText.length,
            ),
    );
    onChanged?.call();
  }

  /// Insert a link template wrapping the selection as `[text](url)`.
  void _insertLink() {
    final text = textController.text;
    final selection = textController.selection;

    if (!selection.isValid || selection.start == selection.end) {
      // No selection -- insert template.
      final cursorPos = selection.isValid
          ? selection.baseOffset.clamp(0, text.length)
          : text.length;
      const linkTemplate = '[text](url)';
      final newText =
          text.substring(0, cursorPos) + linkTemplate + text.substring(cursorPos);
      textController.value = TextEditingValue(
        text: newText,
        // Select "text" portion for easy replacement.
        selection: TextSelection(
          baseOffset: cursorPos + 1,
          extentOffset: cursorPos + 5,
        ),
      );
      onChanged?.call();
      return;
    }

    final start = selection.start;
    final end = selection.end;
    final selectedText = text.substring(start, end);
    final replacement = '[$selectedText](url)';

    final newText =
        text.substring(0, start) + replacement + text.substring(end);
    // Select "url" for easy replacement.
    final urlStart = start + selectedText.length + 3; // after "](""
    textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: urlStart,
        extentOffset: urlStart + 3,
      ),
    );
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      height: AppDimensions.toolbarHeight,
      decoration: BoxDecoration(
        color: c.surfaceLight,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spacingSm,
        ),
        child: Row(
          children: [
            // Group 1: Headings.
            _ToolbarButton(
              label: 'H1',
              isBold: true,
              onTap: () => _insertAtLineStart('# '),
            ),
            _ToolbarButton(
              label: 'H2',
              isBold: true,
              onTap: () => _insertAtLineStart('## '),
            ),
            _ToolbarButton(
              label: 'H3',
              isBold: true,
              onTap: () => _insertAtLineStart('### '),
            ),
            _divider(c),

            // Group 2: Inline formatting.
            _ToolbarButton(
              label: 'B',
              isExtraBold: true,
              onTap: () => _wrapSelection('**', '**'),
            ),
            _ToolbarButton(
              label: 'I',
              isItalic: true,
              onTap: () => _wrapSelection('*', '*'),
            ),
            _ToolbarButton(
              label: 'code',
              isMonospace: true,
              onTap: () => _wrapSelection('`', '`'),
            ),
            _divider(c),

            // Group 3: Block elements.
            _ToolbarButton(
              label: '●', // bullet (●)
              onTap: () => _insertAtLineStart('- '),
            ),
            _ToolbarButton(
              label: '☑', // checkbox (☑)
              onTap: () => _insertAtLineStart('- [ ] '),
            ),
            _ToolbarButton(
              label: '❝', // quote (❝)
              onTap: () => _insertAtLineStart('> '),
            ),
            _ToolbarButton(
              label: '🔗', // link (🔗)
              onTap: _insertLink,
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(AppColorsExtension c) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingXs,
      ),
      child: Container(
        width: 1,
        height: 24,
        color: c.border,
      ),
    );
  }
}

// ── Individual toolbar button ──

class _ToolbarButton extends StatelessWidget {
  final String label;
  final bool isBold;
  final bool isExtraBold;
  final bool isItalic;
  final bool isMonospace;
  final VoidCallback onTap;

  const _ToolbarButton({
    required this.label,
    this.isBold = false,
    this.isExtraBold = false,
    this.isItalic = false,
    this.isMonospace = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    TextStyle textStyle;
    if (isMonospace) {
      textStyle = AppTextStyles.codeMono(
        size: 12,
        weight: FontWeight.w500,
      ).copyWith(color: c.textPrimary);
    } else {
      textStyle = AppTextStyles.captionMedium.copyWith(
        fontWeight: isExtraBold
            ? FontWeight.w900
            : isBold
                ? FontWeight.w700
                : FontWeight.w500,
        fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
        color: c.textPrimary,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 2,
        vertical: AppDimensions.spacingSm,
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 36),
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingSm, vertical: 6),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius:
                BorderRadius.circular(AppDimensions.borderRadius),
            border: Border.all(color: c.borderSubtle),
            boxShadow: AppShadows.card,
          ),
          alignment: Alignment.center,
          child: Text(label, style: textStyle),
        ),
      ),
    );
  }
}
