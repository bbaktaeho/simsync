import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:simsync/auth/auth_models.dart';
import 'package:simsync/auth/auth_service.dart';
import 'package:simsync/main.dart';
import 'package:simsync/screens/repo_selection_screen.dart';
import 'package:simsync/services/note_service.dart';
import 'package:simsync/storage/github/repo_cache.dart';

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
  Future<AuthSession> signIn() async {
    if (_signInHandler != null) {
      return _signInHandler();
    }

    throw UnimplementedError();
  }

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
