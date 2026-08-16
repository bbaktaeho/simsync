import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/theme/app_theme.dart';
import 'package:simsync/widgets/markdown_preview.dart';

/// 위클리/먼슬리 리뷰는 자체 스타일시트를 들고 있어서 지정하지 않은 슬롯
/// (굵게/기울임/코드/인용/링크/표)이 기본 검정으로 떨어졌고, 다크 모드에서
/// 글자가 보이지 않았다. 공용 스타일시트로 바꾼 뒤 그 회귀를 막는다.
void main() {
  const sample = '''
일반 문단과 **굵게**, *기울임*, ~~취소선~~, `인라인 코드`.

> 인용문

- 목록 항목
- [링크](https://example.com)

| A | B |
| --- | --- |
| 1 | 2 |
''';

  /// 렌더된 모든 텍스트 조각의 색을 모은다 (RichText의 span 트리까지).
  List<Color> renderedColors(WidgetTester tester) {
    final colors = <Color>[];
    for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
      rich.text.visitChildren((span) {
        if (span is TextSpan && (span.text?.trim().isNotEmpty ?? false)) {
          final color = span.style?.color;
          if (color != null) colors.add(color);
        }
        return true;
      });
    }
    return colors;
  }

  testWidgets('다크 모드에서 모든 마크다운 조각이 밝은 색으로 그려진다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: SingleChildScrollView(
            child: MarkdownBody(
              data: sample,
              styleSheet: buildMarkdownStyleSheet(context),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final colors = renderedColors(tester);
    expect(colors, isNotEmpty);

    // 다크 배경 위이므로 어두운 글자는 사실상 안 보인다.
    final tooDark = colors
        .where((c) => c.computeLuminance() < 0.18 && c.a > 0.5)
        .toList();
    expect(tooDark, isEmpty,
        reason: '다크 모드에서 어두운 글자가 남아 있으면 안 된다: $tooDark');
  });

  testWidgets('라이트 모드에서는 반대로 너무 밝은 글자가 없다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: SingleChildScrollView(
            child: MarkdownBody(
              data: sample,
              styleSheet: buildMarkdownStyleSheet(context),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final tooLight = renderedColors(tester)
        .where((c) => c.computeLuminance() > 0.75 && c.a > 0.5)
        .toList();
    expect(tooLight, isEmpty, reason: '라이트 모드에서 흐린 글자: $tooLight');
  });
}
