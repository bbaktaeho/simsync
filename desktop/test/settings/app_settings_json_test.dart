import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simsync/settings/app_settings.dart';
import 'package:simsync/settings/app_settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSettings.toSyncJson', () {
    test('includes portable fields and excludes secrets / device paths', () {
      const settings = AppSettings(
        localNotePath: '/Users/me/notes',
        contentScale: 1.2,
        syncIntervalSeconds: 30,
        syncEnabled: true,
        weeklyInstruction: 'do it',
        anthropicApiKey: 'sk-ant-SECRET',
        claudeCliPath: '/opt/homebrew/bin/claude',
        codexCliPath: '/opt/homebrew/bin/codex',
      );
      final json = settings.toSyncJson();

      // Secrets / device-specific paths must never be exported.
      expect(json.containsKey('anthropicApiKey'), isFalse);
      expect(json.containsKey('localNotePath'), isFalse);
      expect(json.containsKey('claudeCliPath'), isFalse);
      expect(json.containsKey('codexCliPath'), isFalse);
      expect(jsonEncode(json).contains('SECRET'), isFalse);

      // Portable fields are present.
      expect(json['contentScale'], 1.2);
      expect(json['weeklyInstruction'], 'do it');
      expect(json.keys.toSet(), AppSettings.syncJsonKeys.toSet());
    });
  });

  group('AppSettingsController JSON', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('export then import round-trips portable settings', () async {
      final a = AppSettingsController(defaultLocalNotePath: '/x');
      await a.load();
      await a.setContentScale(1.4);
      await a.setSearchContextLines(5);
      await a.setAiProvider(AppSettings.providerCodex);
      final json = a.exportSyncJson();

      SharedPreferences.setMockInitialValues({});
      final b = AppSettingsController(defaultLocalNotePath: '/y');
      await b.load();
      await b.importSyncJson(jsonDecode(json) as Map<String, Object?>);

      expect(b.value.contentScale, closeTo(1.4, 0.001));
      expect(b.value.searchContextLines, 5);
      expect(b.value.aiProvider, AppSettings.providerCodex);
      // The importing device keeps its own local path.
      expect(b.value.localNotePath, '/y');
    });

    test('imports the legacy claude/weekly key names from older exports',
        () async {
      final c = AppSettingsController(defaultLocalNotePath: '/x');
      await c.load();

      final applied = await c.importSyncJson({
        'claudeCodeEnabled': true,
        'weeklyProvider': AppSettings.providerCli,
      });

      expect(c.value.aiEnabled, isTrue);
      expect(c.value.aiProvider, AppSettings.providerCli);
      expect(applied, containsAll(['aiEnabled', 'aiProvider']));
    });

    test('clamps out-of-range values and ignores secret/unknown keys', () async {
      final c = AppSettingsController(defaultLocalNotePath: '/x');
      await c.load();

      final applied = await c.importSyncJson({
        'contentScale': 99.0, // above max → clamp
        'searchContextLines': 0, // below min → clamp
        'aiProvider': 'nonsense', // invalid → falls back to api
        'anthropicApiKey': 'sk-ant-LEAK', // not a portable key → ignored
        'localNotePath': '/evil', // device path → ignored
        'unknownKey': 'x', // ignored
      });

      expect(c.value.contentScale, AppSettings.maxContentScale);
      expect(c.value.searchContextLines, AppSettings.minSearchContextLines);
      expect(c.value.aiProvider, AppSettings.providerApi);
      // Secrets / device paths are untouched by an import.
      expect(c.value.anthropicApiKey, '');
      expect(c.value.localNotePath, '/x');
      expect(applied, isNot(contains('anthropicApiKey')));
      expect(applied, isNot(contains('localNotePath')));
      expect(applied, isNot(contains('unknownKey')));
    });
  });
}
