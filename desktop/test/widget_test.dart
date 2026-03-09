import 'package:flutter_test/flutter_test.dart';

import 'package:simsync/main.dart';

void main() {
  testWidgets('App renders login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const SimSyncApp());
    expect(find.text('SimSync'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });
}
