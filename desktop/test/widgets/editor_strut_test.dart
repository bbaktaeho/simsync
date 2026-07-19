import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 극소 명시 스트럿(fontSize 0.1) 정책 검증 — 에디터 접기(details)와 이미지
/// 높이 예약의 전제 조건이다. 실제 TextField(EditableText)로 측정한다:
/// EditableText는 strut에 inheritFromTextStyle을 적용하므로 순수 TextPainter
/// 측정만으로는 부족하다 (StrutStyle.disabled는 fontSize가 16으로 채워져
/// 줄당 16px floor가 남는 것이 실측으로 확인됨).
class _TinyLineController extends TextEditingController {
  _TinyLineController(String text) : super(text: text);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle(fontSize: 16, height: 1.5);
    final lines = text.split('\n');
    final spans = <TextSpan>[];
    for (var i = 0; i < lines.length; i++) {
      final tiny = lines[i].startsWith('HIDE');
      final lineStyle = tiny
          ? base.copyWith(fontSize: 0.1, height: 1.0, color: Colors.transparent)
          : base;
      spans.add(TextSpan(text: lines[i], style: lineStyle));
      if (i < lines.length - 1) {
        spans.add(TextSpan(text: '\n', style: lineStyle));
      }
    }
    return TextSpan(style: base, children: spans);
  }
}

/// 에디터가 쓰는 극소 스트럿과 같은 값 (editor_panel.dart와 일치해야 한다).
const _tinyStrut = StrutStyle(fontSize: 0.1, height: 1, leading: 0);

Future<double> _fieldHeight(WidgetTester tester, String text) async {
  const style = TextStyle(fontSize: 16, height: 1.5);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          child: TextField(
            controller: _TinyLineController(text),
            maxLines: null,
            style: style,
            strutStyle: _tinyStrut,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              isDense: true,
            ),
          ),
        ),
      ),
    ),
  ));
  return tester.getSize(find.byType(EditableText)).height;
}

void main() {
  testWidgets('극소 폰트 줄은 TextField에서 ~0 높이로 접힌다', (tester) async {
    final plain = await _fieldHeight(tester, 'one\ntwo');
    final withHidden = await _fieldHeight(tester, 'one\nHIDE a\nHIDE b\ntwo');
    expect(withHidden - plain, lessThan(1.5), reason: '숨김 줄 2개가 1px 미만');
  });

  testWidgets('일반 줄과 빈 줄 높이는 불변이다', (tester) async {
    final plain = await _fieldHeight(tester, 'one\ntwo');
    final withEmpty = await _fieldHeight(tester, 'one\n\ntwo');
    expect(plain, 48.0); // 16 * 1.5 * 2줄
    expect(withEmpty - plain, closeTo(24.0, 0.5), reason: '빈 줄은 정상 높이 유지');
  });

  testWidgets('큰 첫 글자는 그 줄 높이를 예약한다 (이미지 높이 예약의 원리)',
      (tester) async {
    // TextPainter 검증으로 충분 (스트럿은 min만 제공, 큰 글자는 위로 키운다).
    const base = TextStyle(fontSize: 16, height: 1.5);
    final span = TextSpan(style: base, children: [
      TextSpan(text: '<', style: base.copyWith(fontSize: 200, height: 1.0)),
      TextSpan(
          text: 'img>\n',
          style: base.copyWith(fontSize: 0.1, height: 1.0)),
      const TextSpan(text: 'after', style: base),
    ]);
    final painter = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      strutStyle: _tinyStrut,
    )..layout(maxWidth: 500);
    final metrics = painter.computeLineMetrics();
    expect(metrics.first.height, closeTo(200, 1));
    painter.dispose();
  });
}
