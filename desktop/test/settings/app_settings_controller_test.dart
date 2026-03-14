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
}
