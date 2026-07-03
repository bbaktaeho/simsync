import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simsync/screens/settings_screen.dart';
import 'package:simsync/settings/app_settings.dart';
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
    // Desktop-sized surface so all navigation items are comfortably visible.
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
    expect(find.text('Shortcuts'), findsOneWidget);
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

    // AI pane (above the fold — no nav scrolling needed).
    await tester.tap(find.text('AI'));
    await tester.pumpAndSettle();
    expect(find.text('AI review'), findsOneWidget);

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
    expect(
      find.byKey(const ValueKey('settings-nav-selected-shortcuts')),
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
    expect(
      find.byKey(const ValueKey('settings-nav-selected-shortcuts')),
      findsNothing,
    );
  });

  testWidgets('AI pane toggles integration and switches provider', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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

    await tester.tap(find.text('AI'));
    await tester.pumpAndSettle();

    // One pane carries the provider card and both instruction editors.
    expect(find.text('AI review'), findsOneWidget);
    expect(find.text('AI 요약 연동'), findsOneWidget);
    expect(find.text('위클리 지침'), findsOneWidget);
    expect(find.text('먼슬리 지침'), findsOneWidget);

    // Provider fields only appear once integration is enabled.
    expect(find.text('Anthropic API'), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(controller.value.aiEnabled, isTrue);
    // Default provider is the Anthropic API: provider chips + model field shown.
    expect(find.text('Anthropic API'), findsWidgets);
    expect(find.text('Claude Code CLI'), findsWidgets);
    expect(find.text('Codex CLI'), findsWidgets);
    expect(find.text('모델'), findsOneWidget);
    expect(find.textContaining('console.anthropic.com'), findsOneWidget);

    // Switch to the Claude CLI provider — model field gone, CLI help shown.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Claude Code CLI'));
    await tester.pumpAndSettle();

    expect(controller.value.aiProvider, AppSettings.providerCli);
    expect(find.text('모델'), findsNothing);
    expect(find.textContaining('claude --print'), findsOneWidget);

    // Switch to the Codex CLI provider — codex help shown instead.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Codex CLI'));
    await tester.pumpAndSettle();

    expect(controller.value.aiProvider, AppSettings.providerCodex);
    expect(find.text('모델'), findsNothing);
    expect(find.textContaining('codex exec'), findsOneWidget);
    expect(find.textContaining('claude --print'), findsNothing);
  });
}
