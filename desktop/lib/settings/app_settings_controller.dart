import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';

class AppSettingsController extends ChangeNotifier {
  static const Duration _contentScalePersistDelay = Duration(milliseconds: 180);
  static const String localNotePathKey = 'local_note_path';
  static const String contentScaleKey = 'content_scale';
  static const String syncIntervalSecondsKey = 'sync_interval_seconds';

  AppSettingsController({required String defaultLocalNotePath})
    : _defaultLocalNotePath = defaultLocalNotePath,
      _value = AppSettings(
        localNotePath: defaultLocalNotePath,
        contentScale: 1.0,
        syncIntervalSeconds: 5,
      );

  final String _defaultLocalNotePath;
  AppSettings _value;
  Timer? _contentScalePersistTimer;

  AppSettings get value => _value;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _value = AppSettings(
      localNotePath: prefs.getString(localNotePathKey) ?? _defaultLocalNotePath,
      contentScale: (prefs.getDouble(contentScaleKey) ?? 1.0).clamp(
        AppSettings.minContentScale,
        AppSettings.maxContentScale,
      ),
      syncIntervalSeconds: (prefs.getInt(syncIntervalSecondsKey) ?? 5).clamp(
        AppSettings.minSyncIntervalSeconds,
        AppSettings.maxSyncIntervalSeconds,
      ),
    );
    notifyListeners();
  }

  Future<void> setContentScale(double value) async {
    final clamped = value.clamp(
      AppSettings.minContentScale,
      AppSettings.maxContentScale,
    );
    _value = _value.copyWith(contentScale: clamped);
    notifyListeners();
    _contentScalePersistTimer?.cancel();
    _contentScalePersistTimer = Timer(_contentScalePersistDelay, () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(contentScaleKey, clamped);
    });
  }

  Future<void> setSyncIntervalSeconds(int value) async {
    final clamped = value.clamp(
      AppSettings.minSyncIntervalSeconds,
      AppSettings.maxSyncIntervalSeconds,
    );
    _value = _value.copyWith(syncIntervalSeconds: clamped);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(syncIntervalSecondsKey, clamped);
  }

  Future<void> setLocalNotePath(String value) async {
    if (value.isEmpty) return;
    _value = _value.copyWith(localNotePath: value);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(localNotePathKey, value);
  }

  Future<void> increaseContentScale() async {
    await setContentScale(_value.contentScale + 0.1);
  }

  Future<void> decreaseContentScale() async {
    await setContentScale(_value.contentScale - 0.1);
  }

  @override
  void dispose() {
    _contentScalePersistTimer?.cancel();
    super.dispose();
  }
}
