import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/services/review_outline.dart';

void main() {
  const sample = '- [ ] 첫째 — 요약 A\n'
      '- [x] 둘째 — 요약 B\n'
      '잡담 줄 (체크박스 아님)\n'
      '* [X] 셋째 — 요약 C';

  group('parseOutlineItems', () {
    test('parses only checkbox lines, preserving order and state', () {
      final items = parseOutlineItems(sample);
      expect(items.length, 3);

      expect(items[0].checked, isFalse);
      expect(items[0].label, '첫째 — 요약 A');
      expect(items[0].lineIndex, 0);

      expect(items[1].checked, isTrue);
      expect(items[1].label, '둘째 — 요약 B');
      expect(items[1].lineIndex, 1);

      // The prose line (index 2) is skipped; `* [X]` (index 3) counts as checked.
      expect(items[2].checked, isTrue);
      expect(items[2].label, '셋째 — 요약 C');
      expect(items[2].lineIndex, 3);
    });

    test('empty / no-checkbox input yields no items', () {
      expect(parseOutlineItems(''), isEmpty);
      expect(parseOutlineItems('# 제목\n그냥 글'), isEmpty);
    });
  });

  group('toggleOutlineItem', () {
    test('flips an unchecked box to checked at the given line', () {
      final out = toggleOutlineItem(sample, 0);
      expect(out.split('\n')[0], '- [x] 첫째 — 요약 A');
    });

    test('flips a checked box back to unchecked', () {
      final out = toggleOutlineItem(sample, 1);
      expect(out.split('\n')[1], '- [ ] 둘째 — 요약 B');
    });

    test('a non-checkbox or out-of-range line is left unchanged', () {
      expect(toggleOutlineItem(sample, 2), sample);
      expect(toggleOutlineItem(sample, 99), sample);
      expect(toggleOutlineItem(sample, -1), sample);
    });
  });

  group('hasCheckedItems / checkedItemsText', () {
    test('hasCheckedItems reflects whether any box is checked', () {
      expect(hasCheckedItems(sample), isTrue);
      expect(hasCheckedItems('- [ ] a\n- [ ] b'), isFalse);
      expect(hasCheckedItems(''), isFalse);
    });

    test('checkedItemsText emits only checked labels as a bullet list', () {
      expect(checkedItemsText(sample), '- 둘째 — 요약 B\n- 셋째 — 요약 C');
      expect(checkedItemsText('- [ ] a\n- [ ] b'), '');
    });
  });
}
