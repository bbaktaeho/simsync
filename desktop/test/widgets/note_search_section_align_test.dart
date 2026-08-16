import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/theme/app_theme.dart';
import 'package:simsync/widgets/note_search_section.dart';

/// 검색창은 앱에서 항상 보이는 컨트롤이라 세로 정렬이 어긋나면 바로 눈에 띈다.
void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: NoteSearchSection(
              query: '',
              onQueryChanged: (_) {},
              onClear: () {},
              onOpenFilters: () {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('placeholder가 검색창 세로 중앙에 온다', (tester) async {
    await pump(tester);

    final hint = find.text('Search notes');
    expect(hint, findsOneWidget);

    // 검색창(둥근 배경 컨테이너)의 중앙과 힌트 텍스트의 중앙을 비교한다.
    final fieldBox = find.ancestor(
      of: find.byType(TextField),
      matching: find.byType(Container),
    );
    final fieldCenter = tester.getCenter(fieldBox.first).dy;
    final hintCenter = tester.getCenter(hint).dy;

    expect((hintCenter - fieldCenter).abs(), lessThan(1.0),
        reason: '힌트가 위/아래로 치우치면 안 된다');
  });

  testWidgets('평상시에는 테두리가 없고 포커스에서만 강조된다', (tester) async {
    await pump(tester);

    BoxDecoration decorationOf() {
      final box = tester.widget<Container>(
        find
            .ancestor(
              of: find.byType(TextField),
              matching: find.byType(Container),
            )
            .first,
      );
      return box.decoration! as BoxDecoration;
    }

    expect(decorationOf().border, isNull, reason: '채운 배경만으로 충분하다');

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(decorationOf().border, isNotNull, reason: '포커스는 보여야 한다');
  });
}
