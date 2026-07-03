import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/theme/app_theme.dart';
import 'package:simsync/widgets/markdown_preview.dart';

Future<void> _pump(WidgetTester tester, String content) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(
        body: SizedBox(
          height: 600,
          width: 1000,
          child: MarkdownPreviewWidget(content: content),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders a fenced code block with a known language', (
    tester,
  ) async {
    await _pump(tester, '```go\nfmt.Println("hi")\n```');
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders a fenced code block with NO language', (tester) async {
    await _pump(tester, '```\nplain code\n```');
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders a fenced code block with an unknown language', (
    tester,
  ) async {
    await _pump(tester, '```notalang\nsome code\n```');
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders an indented code block', (tester) async {
    await _pump(tester, '    indented code line\n');
    expect(tester.takeException(), isNull);
  });

  testWidgets('inline code keeps its text and does not crash', (tester) async {
    await _pump(tester, 'Use `flutter test` to run.');
    expect(tester.takeException(), isNull);
    expect(find.textContaining('flutter test'), findsWidgets);
  });

  testWidgets('a code block followed by a paragraph renders both', (
    tester,
  ) async {
    await _pump(tester, '```dart\nvoid main() {}\n```\n\nAfter the block.');
    expect(tester.takeException(), isNull);
    expect(find.textContaining('After the block'), findsWidgets);
  });
}
