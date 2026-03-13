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

  testWidgets('renders master-detail settings layout and switches categories', (
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
    expect(find.text('Storage'), findsWidgets);
    expect(find.text('Editor & Preview'), findsOneWidget);
    expect(find.text('Sync'), findsOneWidget);
    expect(find.text('/tmp/default-notes'), findsOneWidget);
    expect(find.text('octocat/notes'), findsOneWidget);
    expect(find.text('Change...'), findsWidgets);
    expect(find.text('Change Repository...'), findsOneWidget);

    await tester.tap(find.text('Editor & Preview'));
    await tester.pumpAndSettle();

    expect(find.text('Content zoom'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);

    await tester.tap(find.text('Sync'));
    await tester.pumpAndSettle();

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
}
