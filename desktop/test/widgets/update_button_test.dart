import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/theme/app_theme.dart';
import 'package:simsync/widgets/update_button.dart';

void main() {
  testWidgets('업데이트 pill 렌더 + 콜백', (tester) async {
    var opened = 0, dismissed = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: Center(
          child: UpdateButton(
            version: 'v0.3.2',
            onOpen: () => opened++,
            onDismiss: () => dismissed++,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('업데이트 v0.3.2'), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.tap(find.text('업데이트 v0.3.2'));
    await tester.pump();
    expect(opened, 1);
    expect(dismissed, 0);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(dismissed, 1);
    expect(opened, 1);
  });
}
