import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/theme/app_colors.dart';

/// 읽어야 하는 텍스트가 배경과 충분히 대비되는지 못 박는다.
///
/// `textMuted`(#a39e98)는 DESIGN.md에서 placeholder/disabled용으로 규정된 색이고
/// 밝은 배경에서 2.4~2.7:1밖에 안 된다 — 본문에 쓰면 안 읽힌다. 위클리/먼슬리
/// 패널이 안내 문구와 날짜/시각에 이 색을 쓰고 있었다.
double _ratio(Color fg, Color bg) {
  final a = fg.computeLuminance();
  final b = bg.computeLuminance();
  final hi = a > b ? a : b;
  final lo = a > b ? b : a;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final entry in {
    'light': AppColorsExtension.light,
    'dark': AppColorsExtension.dark,
  }.entries) {
    final mode = entry.key;
    final c = entry.value;

    test('$mode: 본문/보조 텍스트는 WCAG AA(4.5:1)를 넘는다', () {
      for (final bg in {
        'scaffold': c.scaffold,
        'surface': c.surface,
        'surfaceLight': c.surfaceLight,
      }.entries) {
        for (final fg in {
          'textPrimary': c.textPrimary,
          'textSecondary': c.textSecondary,
        }.entries) {
          expect(
            _ratio(fg.value, bg.value),
            greaterThanOrEqualTo(4.5),
            reason: '$mode ${fg.key} on ${bg.key}',
          );
        }
      }
    });

    test('$mode: textMuted는 본문용이 아니다 (대비가 낮다는 사실을 기록)', () {
      // 이 값이 4.5를 넘게 되면 토큰이 바뀐 것이다 — 그때는 위 규칙에 편입하면 된다.
      expect(_ratio(c.textMuted, c.surface), lessThan(4.5));
    });
  }
}
