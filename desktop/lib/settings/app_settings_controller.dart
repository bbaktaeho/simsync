import 'dart:async';
import 'dart:convert';

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
  static const String weeklyInstructionKey = 'weekly_instruction';
  static const String claudeCodeEnabledKey = 'claude_code_enabled';
  static const String claudeCliPathKey = 'claude_cli_path';
  static const String weeklyProviderKey = 'weekly_provider';
  static const String anthropicApiKeyKey = 'anthropic_api_key';
  static const String anthropicModelKey = 'anthropic_model';
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
      weeklyInstruction: prefs.getString(weeklyInstructionKey) ??
          AppSettings.defaultWeeklyInstruction,
      claudeCodeEnabled: prefs.getBool(claudeCodeEnabledKey) ?? false,
      claudeCliPath: prefs.getString(claudeCliPathKey) ?? '',
      weeklyProvider:
          prefs.getString(weeklyProviderKey) ?? AppSettings.providerApi,
      anthropicApiKey: prefs.getString(anthropicApiKeyKey) ?? '',
      anthropicModel: prefs.getString(anthropicModelKey) ??
          AppSettings.defaultAnthropicModel,
    );
    _bindings = _loadBindings(prefs);
    notifyListeners();
  }

  /// The portable settings as pretty JSON — what the JSON editor shows and what
  /// is synced to `settings/settings.json`. Secrets / device paths are excluded.
  String exportSyncJson() =>
      const JsonEncoder.withIndent('  ').convert(_value.toSyncJson());

  /// Applies portable settings from a decoded JSON map, validating/clamping each
  /// known field and persisting it. Unknown keys and any secret/device fields
  /// present in the map are ignored. Returns the keys that were applied.
  Future<List<String>> importSyncJson(Map<String, Object?> json) async {
    final prefs = await SharedPreferences.getInstance();
    var next = _value;
    final applied = <String>[];

    final contentScale = json['contentScale'];
    if (contentScale is num) {
      final v = contentScale.toDouble().clamp(
            AppSettings.minContentScale,
            AppSettings.maxContentScale,
          );
      next = next.copyWith(contentScale: v);
      await prefs.setDouble(contentScaleKey, v);
      applied.add('contentScale');
    }

    final syncInterval = json['syncIntervalSeconds'];
    if (syncInterval is num) {
      final v = syncInterval.toInt().clamp(
            AppSettings.minSyncIntervalSeconds,
            AppSettings.maxSyncIntervalSeconds,
          );
      next = next.copyWith(syncIntervalSeconds: v);
      await prefs.setInt(syncIntervalSecondsKey, v);
      applied.add('syncIntervalSeconds');
    }

    final syncEnabled = json['syncEnabled'];
    if (syncEnabled is bool) {
      next = next.copyWith(syncEnabled: syncEnabled);
      await prefs.setBool(syncEnabledKey, syncEnabled);
      applied.add('syncEnabled');
    }

    final searchLines = json['searchContextLines'];
    if (searchLines is num) {
      final v = searchLines.toInt().clamp(
            AppSettings.minSearchContextLines,
            AppSettings.maxSearchContextLines,
          );
      next = next.copyWith(searchContextLines: v);
      await prefs.setInt(searchContextLinesKey, v);
      applied.add('searchContextLines');
    }

    final weeklyInstruction = json['weeklyInstruction'];
    if (weeklyInstruction is String) {
      final trimmed = weeklyInstruction.trim();
      final v = trimmed.isEmpty
          ? AppSettings.defaultWeeklyInstruction
          : trimmed;
      next = next.copyWith(weeklyInstruction: v);
      await prefs.setString(weeklyInstructionKey, v);
      applied.add('weeklyInstruction');
    }

    final claudeCodeEnabled = json['claudeCodeEnabled'];
    if (claudeCodeEnabled is bool) {
      next = next.copyWith(claudeCodeEnabled: claudeCodeEnabled);
      await prefs.setBool(claudeCodeEnabledKey, claudeCodeEnabled);
      applied.add('claudeCodeEnabled');
    }

    final weeklyProvider = json['weeklyProvider'];
    if (weeklyProvider is String) {
      final v = weeklyProvider == AppSettings.providerCli
          ? AppSettings.providerCli
          : AppSettings.providerApi;
      next = next.copyWith(weeklyProvider: v);
      await prefs.setString(weeklyProviderKey, v);
      applied.add('weeklyProvider');
    }

    final anthropicModel = json['anthropicModel'];
    if (anthropicModel is String) {
      final trimmed = anthropicModel.trim();
      final v = trimmed.isEmpty ? AppSettings.defaultAnthropicModel : trimmed;
      next = next.copyWith(anthropicModel: v);
      await prefs.setString(anthropicModelKey, v);
      applied.add('anthropicModel');
    }

    _value = next;
    notifyListeners();
    return applied;
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

  Future<void> setWeeklyInstruction(String value) async {
    final trimmed = value.trim();
    final next = trimmed.isEmpty
        ? AppSettings.defaultWeeklyInstruction
        : trimmed;
    _value = _value.copyWith(weeklyInstruction: next);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(weeklyInstructionKey, next);
  }

  Future<void> setClaudeCodeEnabled(bool value) async {
    _value = _value.copyWith(claudeCodeEnabled: value);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(claudeCodeEnabledKey, value);
  }

  Future<void> setClaudeCliPath(String value) async {
    final trimmed = value.trim();
    _value = _value.copyWith(claudeCliPath: trimmed);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(claudeCliPathKey, trimmed);
  }

  Future<void> setWeeklyProvider(String value) async {
    final next = value == AppSettings.providerCli
        ? AppSettings.providerCli
        : AppSettings.providerApi;
    _value = _value.copyWith(weeklyProvider: next);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(weeklyProviderKey, next);
  }

  Future<void> setAnthropicApiKey(String value) async {
    final trimmed = value.trim();
    _value = _value.copyWith(anthropicApiKey: trimmed);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(anthropicApiKeyKey, trimmed);
  }

  Future<void> setAnthropicModel(String value) async {
    final trimmed = value.trim();
    final next = trimmed.isEmpty ? AppSettings.defaultAnthropicModel : trimmed;
    _value = _value.copyWith(anthropicModel: next);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(anthropicModelKey, next);
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
