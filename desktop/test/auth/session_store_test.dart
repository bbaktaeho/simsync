import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/auth/auth_models.dart';
import 'package:simsync/auth/session_store.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('simsync-session-store-test');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('FileSessionStore writes and restores session json', () async {
    final store = FileSessionStore(
      directoryProvider: () async => tempDir,
    );
    final session = AuthSession(
      provider: 'github',
      accessToken: 'abc',
      tokenType: 'bearer',
      scope: 'read:user',
      issuedAt: DateTime.utc(2026, 3, 10),
      expiresAt: DateTime.utc(2026, 3, 11),
      user: const AuthUser(
        id: '1',
        login: 'octocat',
        name: 'Octo Cat',
        avatarUrl: 'https://example.com/avatar.png',
      ),
    );

    await store.write(session);
    final restored = await store.read();

    expect(restored, isNotNull);
    expect(restored!.accessToken, 'abc');
    expect(restored.user.login, 'octocat');
  });

  test('FileSessionStore clears saved session', () async {
    final store = FileSessionStore(
      directoryProvider: () async => tempDir,
    );

    await store.write(
      AuthSession(
        provider: 'github',
        accessToken: 'abc',
        tokenType: 'bearer',
        scope: 'read:user',
        issuedAt: DateTime.utc(2026, 3, 10),
        expiresAt: DateTime.utc(2026, 3, 11),
        user: const AuthUser(
          id: '1',
          login: 'octocat',
          name: null,
          avatarUrl: 'https://example.com/avatar.png',
        ),
      ),
    );

    await store.clear();

    expect(await store.read(), isNull);
  });

  test('FileSessionStore deletes corrupted session files', () async {
    final store = FileSessionStore(
      directoryProvider: () async => tempDir,
    );
    final file = File('${tempDir.path}/auth/session.json');
    await file.parent.create(recursive: true);
    await file.writeAsString('{not-json');

    final restored = await store.read();

    expect(restored, isNull);
    expect(file.existsSync(), isFalse);
  });
}
