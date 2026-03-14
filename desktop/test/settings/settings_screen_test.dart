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

  test('resolveDirectoryPickerInitialPath returns null for missing path', () {
    expect(resolveDirectoryPickerInitialPath(''), isNull);
    expect(
      resolveDirectoryPickerInitialPath('/tmp/simsync-missing-directory'),
      isNull,
    );
  });

  testWidgets('renders distinct settings navigation and pane headings', (
    WidgetTester tester,
  ) async {
    final controller = AppSettingsController(
      defaultLocalNotePath: '/tmp/default-notes',
    );
    await controller.load();
    var selectedRepo = '';

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColorsExtension.light]),
        home: Scaffold(
          body: SettingsScreen(
            settingsController: controller,
            activeRepo: RepoEntry(owner: 'octocat', repo: 'notes'),
            loadCachedRepos: () async => [
              RepoEntry(owner: 'octocat', repo: 'notes'),
              RepoEntry(owner: 'octocat', repo: 'archive'),
            ],
            onCreateRepo: (name) async =>
                RepoEntry(owner: 'octocat', repo: name),
            onConnectRepo: (owner, repo) async =>
                RepoEntry(owner: owner, repo: repo),
            onRepoSelected: (entry) async => selectedRepo = entry.fullName,
            onPickLocalNotePath: (currentPath) async => '/tmp/updated-notes',
            onLocalNotePathChanged: controller.setLocalNotePath,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Storage'), findsOneWidget);
    expect(find.text('Editor & Preview'), findsOneWidget);
    expect(find.text('Sync'), findsOneWidget);
    expect(find.text('Workspace storage'), findsOneWidget);
    expect(find.text('/tmp/default-notes'), findsOneWidget);
    expect(find.text('octocat/notes'), findsOneWidget);
    expect(find.text('Change...'), findsWidgets);

    await tester.tap(find.text('Editor & Preview'));
    await tester.pumpAndSettle();

    expect(find.text('Editor & Preview'), findsOneWidget);
    expect(find.text('Reading & zoom'), findsOneWidget);
    expect(find.text('Content zoom'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);

    await tester.tap(find.text('Sync'));
    await tester.pumpAndSettle();

    expect(find.text('Sync'), findsOneWidget);
    expect(find.text('Background sync'), findsOneWidget);
    expect(find.text('GitHub sync interval'), findsOneWidget);
    expect(find.text('5s'), findsOneWidget);

    await tester.tap(find.text('Storage').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('octocat/archive'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('octocat/archive'));
    await tester.pumpAndSettle();

    expect(selectedRepo, 'octocat/archive');
  });

  testWidgets('updates local note path and toggles background sync', (
    WidgetTester tester,
  ) async {
    final controller = AppSettingsController(
      defaultLocalNotePath: '/tmp/default-notes',
    );
    await controller.load();
    bool? syncEnabledCallbackValue;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColorsExtension.light]),
        home: Scaffold(
          body: SettingsScreen(
            settingsController: controller,
            onPickLocalNotePath: (currentPath) async => '/tmp/updated-notes',
            onLocalNotePathChanged: controller.setLocalNotePath,
            onSyncEnabledChanged: (value) => syncEnabledCallbackValue = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Change...').first);
    await tester.pumpAndSettle();

    expect(controller.value.localNotePath, '/tmp/updated-notes');
    expect(find.text('/tmp/updated-notes'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(controller.value.syncEnabled, false);
    expect(syncEnabledCallbackValue, false);
  });

  testWidgets('shows a single selected navigation indicator at a time', (
    WidgetTester tester,
  ) async {
    final controller = AppSettingsController(
      defaultLocalNotePath: '/tmp/default-notes',
    );
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppColorsExtension.light]),
        home: Scaffold(body: SettingsScreen(settingsController: controller)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings-nav-selected-storage')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-nav-selected-editor')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('settings-nav-selected-sync')),
      findsNothing,
    );

    await tester.tap(find.text('Editor & Preview'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings-nav-selected-storage')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('settings-nav-selected-editor')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-nav-selected-sync')),
      findsNothing,
    );
  });
}
