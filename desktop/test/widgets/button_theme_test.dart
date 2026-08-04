import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/theme/app_theme.dart';

/// 나란히 놓이는 Outlined/Elevated 버튼의 크기 일관성 회귀 테스트.
///
/// elevatedButtonTheme만 정의되어 있고 outlinedButtonTheme가 없으면 후자는
/// Material 기본값(더 좁은 padding, 더 작은 폰트)으로 그려진다. 그러면 같은 폭
/// 안에서 라벨이 줄바꿈되는 지점이 서로 달라져, 로그인 다이얼로그의 두 버튼처럼
/// 나란히 둔 버튼의 높이가 어긋난다 (한쪽만 2줄).
void main() {
  // testWidgets인 이유: 테마 생성이 GoogleFonts를 건드리는데, 순수 test()에서는
  // 그 폰트 fetch가 테스트 종료 뒤에 실패하며 스위트를 깨뜨린다 (바인딩이 있어야
  // HTTP가 막히고 fallback으로 넘어간다).
  testWidgets('Outlined/Elevated 버튼 테마의 padding과 textStyle이 같다',
      (tester) async {
    // 두 버튼을 나란히 놓는 화면(로그인 다이얼로그)이 있으므로, 한쪽만 Material
    // 기본값으로 남으면 라벨 줄바꿈 지점이 달라져 높이가 어긋난다.
    for (final theme in [buildLightTheme(), buildDarkTheme()]) {
      final elevated = theme.elevatedButtonTheme.style;
      final outlined = theme.outlinedButtonTheme.style;
      expect(outlined, isNotNull, reason: 'outlinedButtonTheme가 정의돼야 한다');
      expect(outlined!.padding?.resolve({}), elevated!.padding?.resolve({}));
      expect(outlined.textStyle?.resolve({})?.fontSize,
          elevated.textStyle?.resolve({})?.fontSize);
      expect(outlined.textStyle?.resolve({})?.fontWeight,
          elevated.textStyle?.resolve({})?.fontWeight);
    }
  });

  Widget pair(ThemeData theme, double width) => MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy code',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                      label: const Text('Open GitHub',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  for (final name in ['light', 'dark']) {
    testWidgets('$name: 나란한 Outlined/Elevated 버튼의 크기가 같다',
        (tester) async {
      // 테마는 테스트 바인딩이 준비된 뒤에 만든다 (폰트 로딩을 건드린다).
      final theme = name == 'light' ? buildLightTheme() : buildDarkTheme();
      // 로그인 다이얼로그의 버튼 행과 비슷한 폭.
      await tester.pumpWidget(pair(theme, 460));
      await tester.pumpAndSettle();

      final outlined = tester.getSize(find.byType(OutlinedButton));
      final elevated = tester.getSize(find.byType(ElevatedButton));
      expect(outlined.height, elevated.height,
          reason: '두 버튼의 높이가 같아야 한다');
      expect(outlined.width, elevated.width);
    });
  }

  testWidgets('좁은 폭에서도 라벨이 줄바꿈되지 않아 높이가 유지된다', (tester) async {
    final theme = buildLightTheme();
    await tester.pumpWidget(pair(theme, 460));
    await tester.pumpAndSettle();
    final wide = tester.getSize(find.byType(ElevatedButton)).height;

    await tester.pumpWidget(pair(theme, 300));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(ElevatedButton)).height, wide,
        reason: '폭이 줄어도 라벨이 한 줄이라 높이는 그대로여야 한다');
    expect(tester.getSize(find.byType(OutlinedButton)).height, wide);
  });
}
