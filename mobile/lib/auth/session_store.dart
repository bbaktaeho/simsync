import 'dart:convert';
import 'dart:io';

import 'auth_models.dart';

abstract class SessionStore {
  Future<AuthSession?> read();
  Future<void> write(AuthSession session);
  Future<void> clear();
}

class FileSessionStore implements SessionStore {
  FileSessionStore({
    required Future<Directory> Function() directoryProvider,
    this.relativePath = 'auth/session.json',
  }) : _directoryProvider = directoryProvider;

  final Future<Directory> Function() _directoryProvider;
  final String relativePath;

  @override
  Future<void> clear() async {
    final file = await _sessionFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<AuthSession?> read() async {
    final file = await _sessionFile();
    if (!await file.exists()) {
      return null;
    }

    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return AuthSession.fromJson(decoded);
    } on FormatException {
      await clear();
      return null;
    } on TypeError {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(AuthSession session) async {
    final file = await _sessionFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(session.toJson()));
  }

  Future<File> _sessionFile() async {
    final directory = await _directoryProvider();
    return File('${directory.path}/$relativePath');
  }
}
