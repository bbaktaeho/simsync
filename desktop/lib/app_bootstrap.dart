import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/auth_service.dart';
import 'auth/github_oauth_provider.dart';
import 'auth/session_policy.dart';
import 'auth/session_store.dart';
import 'settings/app_settings.dart';
import 'settings/app_settings_controller.dart';
import 'services/agent_harness.dart';
import 'services/note_service.dart';
import 'storage/github/github_api_client.dart';
import 'storage/github/github_note_cache.dart';
import 'storage/github/github_note_storage.dart';
import 'storage/github/github_sync_engine.dart';
import 'storage/local/local_note_storage.dart';
import 'storage/note_storage.dart';

/// Shared bootstrap for BOTH Flutter engines (the main window and the macOS
/// menu bar popover). Lives outside `main.dart` so the popover entry point
/// does not have to import the app widget tree (which imports the popover
/// back — a circular import).

/// Resolved storage layer after authentication.
class StorageBundle {
  final NoteStorage storage; // GitHub (remote)
  final NoteStorage? localStorage; // Local file system
  final NoteService noteService;
  final GitHubSyncEngine? syncEngine;

  const StorageBundle({
    required this.storage,
    required this.noteService,
    this.localStorage,
    this.syncEngine,
  });
}

/// Signature for a function that creates a [StorageBundle] from a token and
/// repo info.
///
/// The optional [onRemoteChanged] callback is invoked by the sync engine
/// when a new remote commit is detected, allowing the caller to refresh the UI.
typedef StorageFactory =
    Future<StorageBundle> Function(
      String accessToken, {
      required String owner,
      required String repo,
      required String branch,
      Future<void> Function()? onRemoteChanged,
    });

/// Default storage factory: creates GitHub storage from provided repo info.
Future<StorageBundle> defaultStorageFactory(
  String accessToken, {
  required String owner,
  required String repo,
  required String branch,
  Future<void> Function()? onRemoteChanged,
}) async {
  final localService = NoteService();
  final apiClient = GitHubApiClient(
    token: accessToken,
    owner: owner,
    repo: repo,
  );

  // Load local note path from SharedPreferences.
  final prefs = await SharedPreferences.getInstance();
  final localPath =
      prefs.getString(AppSettingsController.localNotePathKey) ??
      defaultLocalNotePath();
  final syncIntervalSeconds =
      prefs.getInt(AppSettingsController.syncIntervalSecondsKey) ?? 5;

  // Persistent storage cache: per-repo file under app support dir. Loading it
  // hydrates _shaCache / _noteCache from disk, so when the recorded commit SHA
  // still matches HEAD the next listAllNotes call needs zero GitHub round-trips.
  final supportDir = await getApplicationSupportDirectory();
  final cacheFile = File(
    '${supportDir.path}/simsync_cache/${owner}__${repo}__$branch.json',
  );
  final cache = GitHubNoteCache(path: cacheFile.path);
  final githubStorage = GitHubNoteStorage(
    apiClient,
    branch: branch,
    cache: cache,
  );
  await githubStorage.loadCache();

  // 노트 스토어에 AI agent 지침 하네스를 보장한다 — 없으면 자동 생성, 신규
  // repo는 생성 직후 이 경로를 지나므로 무조건 심긴다. fire-and-forget:
  // 실패해도 앱 동작에 영향이 없고 다음 시작에서 재시도된다.
  unawaited(ensureAgentHarness(client: apiClient, branch: branch));

  late final GitHubSyncEngine syncEngine;
  syncEngine = GitHubSyncEngine(
    token: accessToken,
    owner: owner,
    repo: repo,
    branch: branch,
    interval: Duration(
      seconds: syncIntervalSeconds.clamp(
        AppSettings.minSyncIntervalSeconds,
        AppSettings.maxSyncIntervalSeconds,
      ),
    ),
    initialCommitSha: githubStorage.lastCommitSha,
    onRemoteChanged: () async {
      // A new commit on the tracked branch: persist the new SHA, drop the tree
      // snapshot so the next listing refetches it, and notify the app.
      githubStorage.setLastCommitSha(syncEngine.lastCommitSha);
      githubStorage.invalidateTreeCache();
      if (onRemoteChanged != null) {
        await onRemoteChanged();
      }
    },
  );

  return StorageBundle(
    storage: githubStorage,
    localStorage: LocalNoteStorage(basePath: localPath),
    noteService: localService,
    syncEngine: syncEngine,
  );
}

String defaultLocalNotePath() {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  return '$home/Documents/SimSync';
}

ThemeMode flutterThemeMode(AppThemeMode mode) {
  switch (mode) {
    case AppThemeMode.light:
      return ThemeMode.light;
    case AppThemeMode.dark:
      return ThemeMode.dark;
    case AppThemeMode.system:
      return ThemeMode.system;
  }
}

AuthService createDefaultAuthService() {
  // Device flow needs only the client id, which is public by design — the
  // official SimSync id is the compiled-in default so release binaries (and
  // source builds without .env.local) sign in out of the box. Forks can point
  // at their own OAuth App with --dart-define=SIMSYNC_GITHUB_CLIENT_ID=...
  const config = GitHubOAuthConfig(
    clientId: String.fromEnvironment(
      'SIMSYNC_GITHUB_CLIENT_ID',
      defaultValue: 'Ov23likpPsGK5U4sCxI5',
    ),
  );

  return DefaultAuthService(
    provider: GitHubOAuthProvider(config: config, httpClient: http.Client()),
    store: FileSessionStore(directoryProvider: getApplicationSupportDirectory),
    policy: const SessionPolicy(maxAge: Duration(hours: 24)),
    nowProvider: DateTime.now,
  );
}
