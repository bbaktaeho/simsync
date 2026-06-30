/// Pure helpers for the stage-1 review "outline" — a GitHub-style checkbox list
/// (`- [ ] 제목 — 요약`). The user toggles items in the UI; the checked ones
/// become the input context for the stage-2 instruction.
library;

/// One checkbox line parsed from an outline.
class OutlineItem {
  const OutlineItem({
    required this.lineIndex,
    required this.checked,
    required this.label,
  });

  /// Index of this item's line within the outline's split lines (the toggle key).
  final int lineIndex;

  /// Whether the box is checked (`[x]` / `[X]`).
  final bool checked;

  /// Text after the checkbox (the item title + summary).
  final String label;
}

// `- [ ] text` / `* [x] text` — leading bullet, box, optional space, then rest.
final RegExp _checkboxRe = RegExp(r'^(\s*[-*]\s+)\[([ xX])\]\s?(.*)$');

/// Parses every checkbox line from [outline], in order. Non-checkbox lines
/// (headings, blanks, prose) are ignored.
List<OutlineItem> parseOutlineItems(String outline) {
  final items = <OutlineItem>[];
  final lines = outline.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final m = _checkboxRe.firstMatch(lines[i]);
    if (m == null) continue;
    items.add(OutlineItem(
      lineIndex: i,
      checked: m.group(2)!.toLowerCase() == 'x',
      label: m.group(3)!.trim(),
    ));
  }
  return items;
}

/// Returns [outline] with the checkbox on [lineIndex] flipped. If the line is
/// not a checkbox (or [lineIndex] is out of range), returns [outline] unchanged.
String toggleOutlineItem(String outline, int lineIndex) {
  final lines = outline.split('\n');
  if (lineIndex < 0 || lineIndex >= lines.length) return outline;
  final m = _checkboxRe.firstMatch(lines[lineIndex]);
  if (m == null) return outline;
  final nowChecked = m.group(2)!.toLowerCase() != 'x';
  lines[lineIndex] = '${m.group(1)}[${nowChecked ? 'x' : ' '}] ${m.group(3)}';
  return lines.join('\n');
}

/// Whether [outline] has at least one checked item.
bool hasCheckedItems(String outline) =>
    parseOutlineItems(outline).any((it) => it.checked);

/// The checked items rendered as a plain bullet list — the context fed to stage
/// 2. Empty string when nothing is checked.
String checkedItemsText(String outline) => parseOutlineItems(outline)
    .where((it) => it.checked)
    .map((it) => '- ${it.label}')
    .join('\n');
