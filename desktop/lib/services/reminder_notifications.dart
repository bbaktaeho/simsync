import 'dart:io';

import 'package:flutter/services.dart';

import '../settings/app_settings.dart';

/// Daily reminders, delivered by macOS itself: the native side (ReminderChannel
/// in MainFlutterWindow.swift) registers one repeating calendar-triggered
/// UNUserNotification per enabled reminder, so no Dart timer is involved and
/// they fire as long as the app is resident in the menu bar.
class ReminderNotifications {
  static const MethodChannel _channel = MethodChannel('simsync/notifications');

  static bool get isSupported =>
      Platform.isMacOS && !Platform.environment.containsKey('FLUTTER_TEST');

  /// Replaces the OS schedule with the enabled entries of [reminders].
  /// Requests the notification permission on first use; returns false when the
  /// user denied notifications for SimSync.
  static Future<bool> sync(List<Reminder> reminders) async {
    if (!isSupported) return false;
    final ok = await _channel.invokeMethod<bool>('sync', [
      for (final r in reminders)
        if (r.enabled)
          {'id': r.id, 'hour': r.hour, 'minute': r.minute, 'body': r.message},
    ]);
    return ok ?? false;
  }
}
