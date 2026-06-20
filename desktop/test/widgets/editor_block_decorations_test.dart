import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/widgets/editor_block_decorations.dart';

void main() {
  group('parseEditorBlockRegions', () {
    test('finds a fenced code block spanning both fences', () {
      const text = 'before\n```go\nx := 1\n```\nafter';
      final regions = parseEditorBlockRegions(text);
      expect(regions.length, 1);
      expect(regions.first.isCode, isTrue);
      expect(text.substring(regions.first.start, regions.first.end),
          '```go\nx := 1\n```');
    });

    test('finds a --- thematic break', () {
      const text = 'a\n---\nb';
      final regions = parseEditorBlockRegions(text);
      expect(regions.length, 1);
      expect(regions.first.isCode, isFalse);
      expect(text.substring(regions.first.start, regions.first.end), '---');
    });

    test('treats an unterminated fence as a code block to end of text', () {
      const text = 'a\n```\ncode';
      final regions = parseEditorBlockRegions(text);
      expect(regions.length, 1);
      expect(regions.first.isCode, isTrue);
      expect(text.substring(regions.first.start, regions.first.end), '```\ncode');
    });

    test('--- inside a fence is part of the code block, not a rule', () {
      const text = '```\n---\n```';
      final regions = parseEditorBlockRegions(text);
      expect(regions.length, 1);
      expect(regions.single.isCode, isTrue);
    });

    test('handles multiple blocks and rules', () {
      const text = '# h\n---\n```js\n1\n```\n***\ntext';
      final regions = parseEditorBlockRegions(text);
      expect(regions.where((r) => r.isCode).length, 1);
      expect(regions.where((r) => !r.isCode).length, 2); // --- and ***
    });

    test('empty text yields no regions', () {
      expect(parseEditorBlockRegions(''), isEmpty);
    });
  });
}
