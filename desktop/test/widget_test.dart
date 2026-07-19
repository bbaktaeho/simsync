import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:simsync/auth/auth_models.dart';
import 'package:simsync/auth/auth_provider.dart';
import 'package:simsync/auth/auth_service.dart';
import 'package:simsync/main.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/screens/repo_selection_screen.dart';
import 'package:simsync/settings/app_settings_controller.dart';
import 'package:simsync/services/note_service.dart';
import 'package:simsync/storage/github/github_sync_engine.dart';
import 'package:simsync/storage/github/repo_cache.dart';
import 'package:simsync/storage/note_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App renders GitHub login screen when no session exists', (
    WidgetTester tester,
  ) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    await tester.pumpWidget(
      SimSyncApp(
        authService: _FakeAuthService(restoreResult: null),
        storageFactory: _fakeStorageFactory,
        repoCache: RepoCache.withPath(
          '/tmp/simsync_test_nonexistent/repos.json',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SimSync'), findsOneWidget);
    expect(find.text('Continue with GitHub'), findsOneWidget);
    expect(find.text('Email'), findsNothing);
    expect(find.text('Password'), findsNothing);
  });

  testWidgets(
    'App restores session and routes to repo selection when no config exists',
    (WidgetTester tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });

      // Suppress network image errors from RepoSelectionScreen's avatar.
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('NetworkImageLoadException')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      await tester.pumpWidget(
        SimSyncApp(
          authService: _FakeAuthService(restoreResult: _testSession),
          storageFactory: _fakeStorageFactory,
          repoCache: RepoCache.withPath(
            '/tmp/simsync_test_nonexistent/repos.json',
          ),
        ),
      );

      // Allow async _restoreSession + RepoCache.load() to complete.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(RepoSelectionScreen), findsOneWidget);
    },
  );

  testWidgets(
    'Login button shows loading indicator while auth is in progress',
    (WidgetTester tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });

      // Suppress network image errors from RepoSelectionScreen's avatar.
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('NetworkImageLoadException')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      final completer = Completer<AuthSession>();
      final authService = _FakeAuthService(
        restoreResult: null,
        signInHandler: () => completer.future,
      );

      await tester.pumpWidget(
        SimSyncApp(
          authService: authService,
          storageFactory: _fakeStorageFactory,
          repoCache: RepoCache.withPath(
            '/tmp/simsync_test_nonexistent/repos.json',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue with GitHub'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(_testSession);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(RepoSelectionScreen), findsOneWidget);
    },
  );

  testWidgets(
    'App redirects to login screen when background session monitor detects invalid token',
    (WidgetTester tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });

      final repoCache = _InMemoryRepoCache();
      await repoCache.add(
        RepoEntry(
          owner: 'octocat',
          repo: 'notes',
          connectedAt: DateTime.utc(2026, 3, 10, 9),
        ),
      );

      final authService = _FakeAuthService(
        restoreResult: _testSession,
        validationResults: [false],
      );

      await tester.pumpWidget(
        SimSyncApp(
          authService: authService,
          storageFactory: _fakeStorageFactory,
          repoCache: repoCache,
          sessionCheckInterval: const Duration(milliseconds: 20),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pump();

      expect(find.text('Continue with GitHub'), findsOneWidget);
      expect(authService.validateSessionCalls, greaterThanOrEqualTo(1));
      expect(authService.logoutCalls, 1);
    },
  );

  testWidgets(
    'App does not start GitHub sync engine when sync is disabled in settings',
    (WidgetTester tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });

      SharedPreferences.setMockInitialValues({'sync_enabled': false});

      final repoCache = _InMemoryRepoCache();
      await repoCache.add(
        RepoEntry(
          owner: 'octocat',
          repo: 'notes',
          connectedAt: DateTime.utc(2026, 3, 10, 9),
        ),
      );

      final syncEngine = _FakeGitHubSyncEngine();

      Future<StorageBundle> storageFactory(
        String accessToken, {
        required String owner,
        required String repo,
        required String branch,
        Future<void> Function()? onRemoteChanged,
      }) async {
        final storage = _FakeNoteStorage();
        return StorageBundle(
          storage: storage,
          noteService: NoteService(),
          syncEngine: syncEngine,
        );
      }

      await tester.pumpWidget(
        SimSyncApp(
          authService: _FakeAuthService(restoreResult: _testSession),
          storageFactory: storageFactory,
          repoCache: repoCache,
        ),
      );
      await tester.pumpAndSettle();

      expect(syncEngine.startCalls, 0);
      expect(find.byTooltip('Settings'), findsOneWidget);
    },
  );

  testWidgets(
    'App stops GitHub sync engine when background sync is toggled off in settings',
    (WidgetTester tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });

      final repoCache = _InMemoryRepoCache();
      await repoCache.add(
        RepoEntry(
          owner: 'octocat',
          repo: 'notes',
          connectedAt: DateTime.utc(2026, 3, 10, 9),
        ),
      );

      final syncEngine = _FakeGitHubSyncEngine();

      Future<StorageBundle> storageFactory(
        String accessToken, {
        required String owner,
        required String repo,
        required String branch,
        Future<void> Function()? onRemoteChanged,
      }) async {
        final storage = _FakeNoteStorage();
        return StorageBundle(
          storage: storage,
          noteService: NoteService(),
          syncEngine: syncEngine,
        );
      }

      await tester.pumpWidget(
        SimSyncApp(
          authService: _FakeAuthService(restoreResult: _testSession),
          storageFactory: storageFactory,
          repoCache: repoCache,
        ),
      );
      await tester.pumpAndSettle();

      expect(syncEngine.startCalls, 1);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(syncEngine.stopCalls, 1);
    },
  );

  testWidgets(
    'App blocks creating synced notes while background sync is disabled',
    (WidgetTester tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });

      final repoCache = _InMemoryRepoCache();
      await repoCache.add(
        RepoEntry(
          owner: 'octocat',
          repo: 'notes',
          connectedAt: DateTime.utc(2026, 3, 10, 9),
        ),
      );

      final remoteStorage = _MemoryNoteStorage();

      Future<StorageBundle> storageFactory(
        String accessToken, {
        required String owner,
        required String repo,
        required String branch,
        Future<void> Function()? onRemoteChanged,
      }) async {
        return StorageBundle(
          storage: remoteStorage,
          noteService: NoteService(),
        );
      }

      await tester.pumpWidget(
        SimSyncApp(
          authService: _FakeAuthService(restoreResult: _testSession),
          storageFactory: storageFactory,
          repoCache: repoCache,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('동기화 노트'));
      await tester.pumpAndSettle();

      expect(remoteStorage.saveCalls, 0);
      expect(find.text('동기화가 꺼져 있어 동기화 노트를 생성할 수 없습니다.'), findsOneWidget);
    },
  );

  testWidgets(
    'App shows only notes from the newly selected local path after changing it',
    (WidgetTester tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });

      SharedPreferences.setMockInitialValues({
        AppSettingsController.localNotePathKey: '/notes-a',
      });

      FilePicker.platform = _FakeFilePicker('/notes-b');

      final repoCache = _InMemoryRepoCache();
      await repoCache.add(
        RepoEntry(
          owner: 'octocat',
          repo: 'notes',
          connectedAt: DateTime.utc(2026, 3, 10, 9),
        ),
      );

      final today = DateTime.now();
      final oldPathStorage = _MemoryNoteStorage(
        notes: [
          Note(
            id: 'local-old',
            noteDate: DateTime(today.year, today.month, today.day),
            title: 'old-path-note',
            content: '',
            isDefault: false,
            tags: const [],
            createdAt: today,
            updatedAt: today,
            storageType: StorageType.local,
          ),
        ],
        listDelay: const Duration(milliseconds: 80),
      );
      final newPathStorage = _MemoryNoteStorage(
        notes: [
          Note(
            id: 'local-new',
            noteDate: DateTime(today.year, today.month, today.day),
            title: 'new-path-note',
            content: '',
            isDefault: false,
            tags: const [],
            createdAt: today,
            updatedAt: today,
            storageType: StorageType.local,
          ),
        ],
      );

      Future<StorageBundle> storageFactory(
        String accessToken, {
        required String owner,
        required String repo,
        required String branch,
        Future<void> Function()? onRemoteChanged,
      }) async {
        final prefs = await SharedPreferences.getInstance();
        final path = prefs.getString(AppSettingsController.localNotePathKey);
        final localStorage = path == '/notes-b'
            ? newPathStorage
            : oldPathStorage;
        return StorageBundle(
          storage: _MemoryNoteStorage(),
          localStorage: localStorage,
          noteService: NoteService(),
        );
      }

      await tester.pumpWidget(
        SimSyncApp(
          authService: _FakeAuthService(restoreResult: _testSession),
          storageFactory: storageFactory,
          repoCache: repoCache,
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pumpAndSettle();

      expect(find.text('old-path-note'), findsWidgets);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Change...').first);
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      await tester.pumpAndSettle();

      expect(find.text('new-path-note'), findsWidgets);
      expect(find.text('old-path-note'), findsNothing);
    },
  );
  testWidgets(
    'Changing local path immediately clears old local notes before new ones load',
    (WidgetTester tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });

      SharedPreferences.setMockInitialValues({
        AppSettingsController.localNotePathKey: '/notes-a',
      });

      FilePicker.platform = _FakeFilePicker('/notes-b');

      final repoCache = _InMemoryRepoCache();
      await repoCache.add(
        RepoEntry(
          owner: 'octocat',
          repo: 'notes',
          connectedAt: DateTime.utc(2026, 3, 10, 9),
        ),
      );

      final today = DateTime.now();
      final oldPathStorage = _MemoryNoteStorage(
        notes: [
          Note(
            id: 'local-old',
            noteDate: DateTime(today.year, today.month, today.day),
            title: 'old-local-note',
            content: '',
            isDefault: false,
            tags: const [],
            createdAt: today,
            updatedAt: today,
            storageType: StorageType.local,
          ),
        ],
      );
      final newPathStorage = _MemoryNoteStorage(
        notes: [
          Note(
            id: 'local-new',
            noteDate: DateTime(today.year, today.month, today.day),
            title: 'new-local-note',
            content: '',
            isDefault: false,
            tags: const [],
            createdAt: today,
            updatedAt: today,
            storageType: StorageType.local,
          ),
        ],
        // Add delay so we can observe the intermediate state.
        listDelay: const Duration(milliseconds: 200),
      );

      Future<StorageBundle> storageFactory(
        String accessToken, {
        required String owner,
        required String repo,
        required String branch,
        Future<void> Function()? onRemoteChanged,
      }) async {
        final prefs = await SharedPreferences.getInstance();
        final path = prefs.getString(AppSettingsController.localNotePathKey);
        final localStorage =
            path == '/notes-b' ? newPathStorage : oldPathStorage;
        return StorageBundle(
          storage: _MemoryNoteStorage(),
          localStorage: localStorage,
          noteService: NoteService(),
        );
      }

      await tester.pumpWidget(
        SimSyncApp(
          authService: _FakeAuthService(restoreResult: _testSession),
          storageFactory: storageFactory,
          repoCache: repoCache,
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pumpAndSettle();

      // Old local note should be visible.
      expect(find.text('old-local-note'), findsWidgets);

      // Open settings and change path.
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Change...').first);
      await tester.pump();
      await tester.tap(find.text('Done'));
      // Pump just enough for didUpdateWidget to fire, but NOT enough for
      // the delayed new storage to finish loading.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Old local notes should be gone immediately, even before new ones load.
      expect(find.text('old-local-note'), findsNothing);

      // Drain pending storage timers (listDates + listAllNotes from search
      // index rebuild) so the test tears down cleanly.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'RepoSelectionScreen path change updates AppSettingsController',
    (WidgetTester tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });

      SharedPreferences.setMockInitialValues({
        AppSettingsController.localNotePathKey: '/notes-initial',
      });

      FilePicker.platform = _FakeFilePicker('/notes-from-repo-screen');

      // Suppress network image errors from RepoSelectionScreen's avatar.
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('NetworkImageLoadException')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      await tester.pumpWidget(
        SimSyncApp(
          authService: _FakeAuthService(restoreResult: _testSession),
          storageFactory: _fakeStorageFactory,
          repoCache: RepoCache.withPath(
            '/tmp/simsync_test_nonexistent/repos.json',
          ),
        ),
      );

      // Allow async _restoreSession + AppSettingsController.load() to complete.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(RepoSelectionScreen), findsOneWidget);
      // Initial path from settings controller should be displayed.
      expect(find.text('/notes-initial'), findsOneWidget);

      // Tap "변경" button to change path via FilePicker.
      await tester.tap(find.text('변경'));
      await tester.pump();

      // After picking, the controller should be updated and the new path shown.
      expect(find.text('/notes-from-repo-screen'), findsOneWidget);
      expect(find.text('/notes-initial'), findsNothing);
    },
  );
}

final _testSession = AuthSession(
  provider: 'github',
  accessToken: 'token',
  tokenType: 'bearer',
  scope: 'read:user',
  issuedAt: DateTime.utc(2026, 3, 10, 9),
  expiresAt: DateTime.utc(2026, 3, 11, 9),
  user: const AuthUser(id: '1', login: 'octocat', name: null, avatarUrl: ''),
);

/// Test storage factory that returns local NoteService without disk config.
Future<StorageBundle> _fakeStorageFactory(
  String accessToken, {
  required String owner,
  required String repo,
  required String branch,
  Future<void> Function()? onRemoteChanged,
}) async {
  final service = NoteService();
  return StorageBundle(storage: service, noteService: service);
}

class _FakeNoteStorage implements NoteStorage {
  @override
  Future<void> deleteNote(Note note) async {}

  @override
  Future<Note?> getNote(String noteId, DateTime noteDate) async => null;

  @override
  Future<List<Note>> listAllNotes() async => const [];

  @override
  Future<List<DateTime>> listDates(String yearMonth) async => const [];

  @override
  Future<List<Note>> listNotes(DateTime date) async => const [];

  @override
  Future<void> saveNote(Note note) async {}

  final Map<String, String> _textFiles = {};

  @override
  Future<String?> readTextFile(String relativePath) async =>
      _textFiles[relativePath];

  @override
  Future<void> writeTextFile(String relativePath, String content) async {
    _textFiles[relativePath] = content;
  }

  @override
  String noteDirPath(DateTime noteDate) =>
      '${noteDate.year}-${noteDate.month.toString().padLeft(2, '0')}-${noteDate.day.toString().padLeft(2, '0')}';

  final Map<String, Uint8List> _binaryFiles = {};

  @override
  Future<Uint8List?> readBinaryFile(String relativePath) async =>
      _binaryFiles[relativePath];

  @override
  Future<void> writeBinaryFile(String relativePath, Uint8List bytes) async {
    _binaryFiles[relativePath] = bytes;
  }
}

class _MemoryNoteStorage implements NoteStorage {
  _MemoryNoteStorage({List<Note>? notes, this.listDelay = Duration.zero})
    : _notes = List<Note>.from(notes ?? const []);

  final List<Note> _notes;
  final Duration listDelay;
  int saveCalls = 0;
  int deleteCalls = 0;

  Future<void> _waitForListDelay() async {
    if (listDelay > Duration.zero) {
      await Future<void>.delayed(listDelay);
    }
  }

  @override
  Future<void> deleteNote(Note note) async {
    deleteCalls += 1;
    _notes.removeWhere((item) => item.id == note.id);
  }

  @override
  Future<Note?> getNote(String noteId, DateTime noteDate) async {
    return _notes.where((note) => note.id == noteId).firstOrNull;
  }

  @override
  Future<List<Note>> listAllNotes() async {
    await _waitForListDelay();
    return List<Note>.from(_notes);
  }

  @override
  Future<List<DateTime>> listDates(String yearMonth) async {
    await _waitForListDelay();
    final parts = yearMonth.split('-');
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null) return const [];

    return _notes
        .where(
          (note) => note.noteDate.year == year && note.noteDate.month == month,
        )
        .map(
          (note) => DateTime(
            note.noteDate.year,
            note.noteDate.month,
            note.noteDate.day,
          ),
        )
        .toSet()
        .toList()
      ..sort();
  }

  @override
  Future<List<Note>> listNotes(DateTime date) async {
    await _waitForListDelay();
    return _notes
        .where(
          (note) =>
              note.noteDate.year == date.year &&
              note.noteDate.month == date.month &&
              note.noteDate.day == date.day,
        )
        .toList();
  }

  @override
  Future<void> saveNote(Note note) async {
    saveCalls += 1;
    _notes.removeWhere((item) => item.id == note.id);
    _notes.add(note);
  }

  final Map<String, String> _textFiles = {};

  @override
  Future<String?> readTextFile(String relativePath) async =>
      _textFiles[relativePath];

  @override
  Future<void> writeTextFile(String relativePath, String content) async {
    _textFiles[relativePath] = content;
  }

  @override
  String noteDirPath(DateTime noteDate) =>
      '${noteDate.year}-${noteDate.month.toString().padLeft(2, '0')}-${noteDate.day.toString().padLeft(2, '0')}';

  final Map<String, Uint8List> _binaryFiles = {};

  @override
  Future<Uint8List?> readBinaryFile(String relativePath) async =>
      _binaryFiles[relativePath];

  @override
  Future<void> writeBinaryFile(String relativePath, Uint8List bytes) async {
    _binaryFiles[relativePath] = bytes;
  }
}

class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this.directoryPath);

  final String directoryPath;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async {
    return directoryPath;
  }
}

class _FakeGitHubSyncEngine extends GitHubSyncEngine {
  _FakeGitHubSyncEngine() : super(token: 'token', owner: 'owner', repo: 'repo');

  int startCalls = 0;
  int stopCalls = 0;

  @override
  void start() {
    startCalls += 1;
  }

  @override
  void stop() {
    stopCalls += 1;
  }

  @override
  Future<void> syncNow() async {}

  @override
  void dispose() {}
}

class _FakeAuthService implements AuthService {
  _FakeAuthService({
    required this.restoreResult,
    Future<AuthSession> Function()? signInHandler,
    List<bool>? validationResults,
  }) : _signInHandler = signInHandler,
       _validationResults = List<bool>.from(validationResults ?? const []);

  final AuthSession? restoreResult;
  final Future<AuthSession> Function()? _signInHandler;
  final List<bool> _validationResults;
  int logoutCalls = 0;
  int validateSessionCalls = 0;

  @override
  Future<void> logout() async {
    logoutCalls += 1;
  }

  @override
  Future<AuthSession?> restoreSession() async => restoreResult;

  @override
  Future<AuthSession> signIn({
    DeviceAuthorizationPrompt? onAuthorizationPrompt,
  }) async {
    if (_signInHandler != null) {
      return _signInHandler();
    }

    throw UnimplementedError();
  }

  @override
  void cancelSignIn() {}

  @override
  Future<bool> validateSession(AuthSession session) async {
    validateSessionCalls += 1;
    if (_validationResults.isEmpty) {
      return true;
    }
    return _validationResults.removeAt(0);
  }
}

class _InMemoryRepoCache extends RepoCache {
  _InMemoryRepoCache() : super.withPath('/tmp/simsync-unused-repo-cache.json');

  final List<RepoEntry> _entries = [];

  @override
  Future<void> add(RepoEntry entry) async {
    _entries.removeWhere((e) => e.owner == entry.owner && e.repo == entry.repo);
    _entries.insert(0, entry);
  }

  @override
  Future<List<RepoEntry>> load() async => List<RepoEntry>.from(_entries);

  @override
  Future<void> remove(String owner, String repo) async {
    _entries.removeWhere((e) => e.owner == owner && e.repo == repo);
  }
}
