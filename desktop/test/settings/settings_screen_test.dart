import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simsync/screens/settings_screen.dart';
import 'package:simsync/settings/app_settings_controller.dart';
import 'package:simsync/storage/github/repo_cache.dart';
import 'package:simsync/theme/app_colors.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'renders current storage info and updates zoom and sync interval',
    (WidgetTester tester) async {
      final controller = AppSettingsController(
        defaultLocalNotePath: '/tmp/default-notes',
      );
      await controller.load();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColorsExtension.light]),
          home: Scaffold(
            body: SettingsScreen(
              settingsController: controller,
              activeRepo: RepoEntry(owner: 'octocat', repo: 'notes'),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('octocat/notes'), findsOneWidget);
      expect(find.text('/tmp/default-notes'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('5s'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();

      expect(find.text('110%'), findsOneWidget);
    },
  );

  testWidgets('updates local note path when change action is used', (
    WidgetTester tester,
  ) async {
    final controller = AppSettingsController(
      defaultLocalNotePath: '/tmp/default-notes',
    );
    await controller.load();
    var appliedPath = '';

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColorsExtension.light]),
        home: Scaffold(
          body: SettingsScreen(
            settingsController: controller,
            onPickLocalNotePath: (currentPath) async => '/tmp/updated-notes',
            onLocalNotePathChanged: (path) async {
              appliedPath = path;
              await controller.setLocalNotePath(path);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Change...'));
    await tester.pumpAndSettle();

    expect(appliedPath, '/tmp/updated-notes');
    expect(controller.value.localNotePath, '/tmp/updated-notes');
    expect(find.text('/tmp/updated-notes'), findsOneWidget);
  });
}
