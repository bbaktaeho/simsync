import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simsync/settings/app_settings.dart';
import 'package:simsync/settings/app_settings_controller.dart';
import 'package:simsync/theme/app_colors.dart';
import 'package:simsync/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dark theme applies the dark palette', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: ThemeMode.dark,
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );

    final theme = Theme.of(ctx);
    expect(theme.brightness, Brightness.dark);
    expect(theme.extension<AppColorsExtension>(), same(AppColorsExtension.dark));
  });

  test('setThemeMode updates, persists, and reloads', () async {
    SharedPreferences.setMockInitialValues({});
    final c = AppSettingsController(defaultLocalNotePath: '/tmp/simsync');
    await c.load();
    expect(c.value.themeMode, AppThemeMode.system); // default follows the OS

    await c.setThemeMode(AppThemeMode.dark);
    expect(c.value.themeMode, AppThemeMode.dark);

    // A fresh controller reads back the persisted preference.
    final c2 = AppSettingsController(defaultLocalNotePath: '/tmp/simsync');
    await c2.load();
    expect(c2.value.themeMode, AppThemeMode.dark);

    c.dispose();
    c2.dispose();
  });

  test('theme preference is device-local (excluded from synced JSON)', () {
    const settings = AppSettings(
      localNotePath: '/x',
      contentScale: 1.0,
      syncIntervalSeconds: 5,
      syncEnabled: true,
      themeMode: AppThemeMode.dark,
    );
    expect(settings.toSyncJson().containsKey('themeMode'), isFalse);
    expect(AppSettings.syncJsonKeys.contains('themeMode'), isFalse);
  });
}
