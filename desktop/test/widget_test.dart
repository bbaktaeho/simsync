import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:simsync/auth/auth_models.dart';
import 'package:simsync/auth/auth_service.dart';
import 'package:simsync/main.dart';
import 'package:simsync/screens/document_screen.dart';
import 'package:simsync/services/note_service.dart';

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
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SimSync'), findsOneWidget);
    expect(find.text('Continue with GitHub'), findsOneWidget);
    expect(find.text('Email'), findsNothing);
    expect(find.text('Password'), findsNothing);
  });

  testWidgets('App restores session and routes to document screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      SimSyncApp(
        authService: _FakeAuthService(
          restoreResult: AuthSession(
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
          ),
        ),
        storageFactory: _fakeStorageFactory,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(DocumentScreen), findsOneWidget);
  });

  testWidgets('Login button shows loading indicator while auth is in progress', (
    WidgetTester tester,
  ) async {
    final completer = Completer<AuthSession>();
    final authService = _FakeAuthService(
      restoreResult: null,
      signInHandler: () => completer.future,
    );

    await tester.pumpWidget(
      SimSyncApp(
        authService: authService,
        storageFactory: _fakeStorageFactory,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue with GitHub'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(
      AuthSession(
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
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(DocumentScreen), findsOneWidget);
  });
}

/// Test storage factory that returns local NoteService without disk config.
Future<StorageBundle> _fakeStorageFactory(String accessToken) async {
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
