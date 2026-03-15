import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:simsync/auth/auth_models.dart';
import 'package:simsync/auth/auth_service.dart';
import 'package:simsync/main.dart';
import 'package:simsync/screens/repo_selection_screen.dart';
import 'package:simsync/services/note_service.dart';
import 'package:simsync/storage/github/repo_cache.dart';

void main() {
  testWidgets('App renders GitHub login screen when no session exists', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      SimSyncApp(
        authService: _FakeAuthService(
          restoreResult: null,
        ),
        storageFactory: _fakeStorageFactory,
        repoCache: RepoCache.withPath('/tmp/simsync_test_nonexistent/repos.json'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SimSync'), findsOneWidget);
    expect(find.text('Continue with GitHub'), findsOneWidget);
    expect(find.text('Email'), findsNothing);
    expect(find.text('Password'), findsNothing);
  });

  testWidgets('App restores session and routes to repo selection when no config exists', (
    WidgetTester tester,
  ) async {
    // Suppress network image errors from RepoSelectionScreen's avatar.
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('NetworkImageLoadException')) return;
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    await tester.pumpWidget(
      SimSyncApp(
        authService: _FakeAuthService(
          restoreResult: _testSession,
        ),
        storageFactory: _fakeStorageFactory,
        repoCache: RepoCache.withPath('/tmp/simsync_test_nonexistent/repos.json'),
      ),
    );

    // Allow async _restoreSession + RepoCache.load() to complete.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(RepoSelectionScreen), findsOneWidget);
  });

  testWidgets('Login button shows loading indicator while auth is in progress', (
    WidgetTester tester,
  ) async {
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
        repoCache: RepoCache.withPath('/tmp/simsync_test_nonexistent/repos.json'),
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
  });
}

final _testSession = AuthSession(
  provider: 'github',
  accessToken: 'token',
  tokenType: 'bearer',
  scope: 'read:user',
  issuedAt: DateTime.utc(2026, 3, 10, 9),
  expiresAt: DateTime.utc(2026, 3, 11, 9),
  user: const AuthUser(
    id: '1',
    login: 'octocat',
    name: null,
    avatarUrl: 'https://example.com/avatar.png',
  ),
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
  }) : _signInHandler = signInHandler;

  final AuthSession? restoreResult;
  final Future<AuthSession> Function()? _signInHandler;

  @override
  Future<void> logout() async {}

  @override
  Future<AuthSession?> restoreSession() async => restoreResult;

  @override
  Future<AuthSession> signIn() async {
    if (_signInHandler != null) {
      return _signInHandler();
    }

    throw UnimplementedError();
  }
}
