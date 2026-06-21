import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simsync/settings/app_settings.dart';
import 'package:simsync/settings/app_settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('loads default settings when nothing is stored', () async {
    final controller = AppSettingsController(
      defaultLocalNotePath: '/tmp/default-notes',
    );

    await controller.load();

    expect(
      controller.value,
      const AppSettings(
        localNotePath: '/tmp/default-notes',
        contentScale: 1.0,
        syncIntervalSeconds: 5,
        syncEnabled: true,
      ),
    );
  });

  test(
    'persists content scale, sync interval, and sync enabled changes',
    () async {
      final controller = AppSettingsController(
        defaultLocalNotePath: '/tmp/default-notes',
      );
      await controller.load();

      await controller.setContentScale(1.25);
      await controller.setSyncIntervalSeconds(15);
      await controller.setSyncEnabled(false);
      await Future<void>.delayed(const Duration(milliseconds: 250));

      final reloaded = AppSettingsController(
        defaultLocalNotePath: '/tmp/default-notes',
      );
      await reloaded.load();

      expect(reloaded.value.contentScale, 1.25);
      expect(reloaded.value.syncIntervalSeconds, 15);
      expect(reloaded.value.syncEnabled, false);
    },
  );

  test('reuses existing local note path from preferences', () async {
    SharedPreferences.setMockInitialValues({
      AppSettingsController.localNotePathKey: '/tmp/custom-notes',
    });

    final controller = AppSettingsController(
      defaultLocalNotePath: '/tmp/default-notes',
    );
    await controller.load();

    expect(controller.value.localNotePath, '/tmp/custom-notes');
  });

  test('defaults weekly instruction and disabled Claude integration', () async {
    final controller = AppSettingsController(
      defaultLocalNotePath: '/tmp/default-notes',
    );
    await controller.load();

    expect(
      controller.value.weeklyInstruction,
      AppSettings.defaultWeeklyInstruction,
    );
    expect(controller.value.claudeCodeEnabled, isFalse);
    expect(controller.value.claudeCliPath, '');
  });

  test('persists weekly instruction, claude toggle and cli path', () async {
    final controller = AppSettingsController(
      defaultLocalNotePath: '/tmp/default-notes',
    );
    await controller.load();

    await controller.setWeeklyInstruction('내 지침');
    await controller.setClaudeCodeEnabled(true);
    await controller.setClaudeCliPath('/opt/homebrew/bin/claude');

    final reloaded = AppSettingsController(
      defaultLocalNotePath: '/tmp/default-notes',
    );
    await reloaded.load();

    expect(reloaded.value.weeklyInstruction, '내 지침');
    expect(reloaded.value.claudeCodeEnabled, isTrue);
    expect(reloaded.value.claudeCliPath, '/opt/homebrew/bin/claude');
  });

  test('blank weekly instruction falls back to the default', () async {
    final controller = AppSettingsController(
      defaultLocalNotePath: '/tmp/default-notes',
    );
    await controller.load();

    await controller.setWeeklyInstruction('   ');

    expect(
      controller.value.weeklyInstruction,
      AppSettings.defaultWeeklyInstruction,
    );
  });

  test('defaults to the Anthropic API provider with the default model',
      () async {
    final controller = AppSettingsController(
      defaultLocalNotePath: '/tmp/default-notes',
    );
    await controller.load();

    expect(controller.value.weeklyProvider, AppSettings.providerApi);
    expect(controller.value.anthropicApiKey, '');
    expect(controller.value.anthropicModel, AppSettings.defaultAnthropicModel);
  });

  test('persists provider, api key and model', () async {
    final controller = AppSettingsController(
      defaultLocalNotePath: '/tmp/default-notes',
    );
    await controller.load();

    await controller.setWeeklyProvider(AppSettings.providerCli);
    await controller.setAnthropicApiKey('sk-ant-abc');
    await controller.setAnthropicModel('claude-sonnet-4-6');

    final reloaded = AppSettingsController(
      defaultLocalNotePath: '/tmp/default-notes',
    );
    await reloaded.load();

    expect(reloaded.value.weeklyProvider, AppSettings.providerCli);
    expect(reloaded.value.anthropicApiKey, 'sk-ant-abc');
    expect(reloaded.value.anthropicModel, 'claude-sonnet-4-6');
  });

  test('blank model falls back to the default; unknown provider falls to api',
      () async {
    final controller = AppSettingsController(
      defaultLocalNotePath: '/tmp/default-notes',
    );
    await controller.load();

    await controller.setAnthropicModel('  ');
    await controller.setWeeklyProvider('bogus');

    expect(controller.value.anthropicModel, AppSettings.defaultAnthropicModel);
    expect(controller.value.weeklyProvider, AppSettings.providerApi);
  });
}
