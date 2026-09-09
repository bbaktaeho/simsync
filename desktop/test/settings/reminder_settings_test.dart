import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simsync/settings/app_settings.dart';
import 'package:simsync/settings/app_settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('no reminders by default; add/update/remove persist and reload',
      () async {
    SharedPreferences.setMockInitialValues({});
    final c = AppSettingsController(defaultLocalNotePath: '/tmp/simsync');
    await c.load();
    expect(c.value.reminders, isEmpty);

    final added = await c.addReminder();
    expect(added.minutes, 18 * 60);
    expect(added.message, Reminder.defaultMessage);
    expect(added.enabled, isTrue);

    await c.updateReminder(
      added.copyWith(minutes: 9 * 60 + 30, message: '회고 쓰기', enabled: false),
    );
    final second = await c.addReminder();

    final c2 = AppSettingsController(defaultLocalNotePath: '/tmp/simsync');
    await c2.load();
    expect(c2.value.reminders.length, 2);
    expect(c2.value.reminders.first.timeLabel, '09:30');
    expect(c2.value.reminders.first.message, '회고 쓰기');
    expect(c2.value.reminders.first.enabled, isFalse);

    await c2.removeReminder(second.id);
    expect(c2.value.reminders.map((r) => r.id), [added.id]);
    c.dispose();
    c2.dispose();
  });

  test('corrupt or partial stored reminders are tolerated', () async {
    SharedPreferences.setMockInitialValues({
      'reminders': '[{"id":"a","minutes":99999,"message":"  "},{"x":1},3]',
    });
    final c = AppSettingsController(defaultLocalNotePath: '/tmp/simsync');
    await c.load();
    expect(c.value.reminders.length, 1);
    expect(c.value.reminders.single.minutes, 24 * 60 - 1);
    expect(c.value.reminders.single.message, Reminder.defaultMessage);
    c.dispose();

    SharedPreferences.setMockInitialValues({'reminders': 'not json'});
    final c2 = AppSettingsController(defaultLocalNotePath: '/tmp/simsync');
    await c2.load();
    expect(c2.value.reminders, isEmpty);
    c2.dispose();
  });

  test('reminders are device-local (excluded from synced JSON)', () {
    const settings = AppSettings(
      localNotePath: '/x',
      contentScale: 1.0,
      syncIntervalSeconds: 5,
      syncEnabled: true,
      reminders: [Reminder(id: 'a')],
    );
    expect(settings.toSyncJson().containsKey('reminders'), isFalse);
  });
}
