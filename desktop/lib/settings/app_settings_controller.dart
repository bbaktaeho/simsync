import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'shortcut_binding.dart';

class AppSettingsController extends ChangeNotifier {
  static const Duration _contentScalePersistDelay = Duration(milliseconds: 180);
  static const String localNotePathKey = 'local_note_path';
  static const String contentScaleKey = 'content_scale';
  static const String syncIntervalSecondsKey = 'sync_interval_seconds';
  static const String syncEnabledKey = 'sync_enabled';
  static const String searchContextLinesKey = 'search_context_lines';
  static const String _shortcutPrefix = 'shortcut_';

  AppSettingsController({required String defaultLocalNotePath})
    : _defaultLocalNotePath = defaultLocalNotePath,
      _bindings = List<ShortcutBinding>.from(defaultShortcutBindings),
      _value = AppSettings(
        localNotePath: defaultLocalNotePath,
        contentScale: 1.0,
        syncIntervalSeconds: 5,
        syncEnabled: true,
      );

  final String _defaultLocalNotePath;
  AppSettings _value;
  List<ShortcutBinding> _bindings;
  Timer? _contentScalePersistTimer;

  AppSettings get value => _value;
  List<ShortcutBinding> get bindings => List.unmodifiable(_bindings);

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
      syncEnabled: prefs.getBool(syncEnabledKey) ?? true,
      searchContextLines: (prefs.getInt(searchContextLinesKey) ??
              AppSettings.defaultSearchContextLines)
          .clamp(
        AppSettings.minSearchContextLines,
        AppSettings.maxSearchContextLines,
      ),
    );
    _bindings = _loadBindings(prefs);
    notifyListeners();
  }

  List<ShortcutBinding> _loadBindings(SharedPreferences prefs) {
    final result = <ShortcutBinding>[];
    for (final def in defaultShortcutBindings) {
      final raw = prefs.getString('$_shortcutPrefix${def.action.name}');
      if (raw != null && !def.isFixed) {
        final parsed =
            ShortcutBinding.deserialize(raw, def.action, isFixed: false);
        result.add(parsed ?? def);
      } else {
        result.add(def);
      }
    }
    return result;
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

  Future<void> setSearchContextLines(int value) async {
    final clamped = value.clamp(
      AppSettings.minSearchContextLines,
      AppSettings.maxSearchContextLines,
    );
    _value = _value.copyWith(searchContextLines: clamped);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(searchContextLinesKey, clamped);
  }

  Future<void> setSyncEnabled(bool value) async {
    _value = _value.copyWith(syncEnabled: value);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(syncEnabledKey, value);
  }

  Future<void> setShortcutBinding(ShortcutBinding binding) async {
    if (binding.isFixed) return;
    final index = _bindings.indexWhere((b) => b.action == binding.action);
    if (index == -1) return;
    _bindings[index] = binding;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_shortcutPrefix${binding.action.name}',
      binding.serialize(),
    );
  }

  /// Look up the current binding for the given action.
  ShortcutBinding bindingFor(ShortcutAction action) {
    return _bindings.firstWhere((b) => b.action == action);
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
