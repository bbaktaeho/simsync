import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simsync/auth/auth_models.dart';
import 'package:simsync/auth/auth_service.dart';
import 'package:simsync/main.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/services/note_service.dart';
import 'package:simsync/storage/github/repo_cache.dart';
import 'package:simsync/storage/note_storage.dart';

class _FakeNoteStorage implements NoteStorage {
  _FakeNoteStorage(this.notes);

  final List<Note> notes;

  @override
  Future<void> deleteNote(Note note) async {}

  @override
  Future<Note?> getNote(String noteId, DateTime noteDate) async {
    return notes.where((note) => note.id == noteId).firstOrNull;
  }

  @override
  Future<List<Note>> listMemoNotes() async =>
      notes.where((n) => n.isMemo).toList();

  @override
  Future<List<Note>> listAllNotes() async => List<Note>.from(notes);

  @override
  Future<List<DateTime>> listDates(String yearMonth) async {
    final parts = yearMonth.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    return notes
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
    return notes
        .where(
          (note) =>
              note.noteDate.year == date.year &&
              note.noteDate.month == date.month &&
              note.noteDate.day == date.day,
        )
        .toList();
  }

  @override
  Future<void> saveNote(Note note) async {}
}

class _FakeAuthService implements AuthService {
  _FakeAuthService({required this.restoreResult});

  final AuthSession? restoreResult;

  @override
  Future<void> logout() async {}

  @override
  Future<AuthSession?> restoreSession() async => restoreResult;

  @override
  Future<AuthSession> signIn() async => throw UnimplementedError();

  @override
  Future<bool> validateSession(AuthSession session) async => true;
}

class _InMemoryRepoCache extends RepoCache {
  _InMemoryRepoCache(this._entries)
    : super.withPath('/tmp/simsync-document-screen-test-repo-cache.json');

  final List<RepoEntry> _entries;

  @override
  Future<void> add(RepoEntry entry) async {
    _entries.removeWhere((item) => item.fullName == entry.fullName);
    _entries.insert(0, entry);
  }

  @override
  Future<List<RepoEntry>> load() async => List<RepoEntry>.from(_entries);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'updates zoom label immediately when cmd plus shortcut is pressed',
    (WidgetTester tester) async {
      final today = DateTime.now();
      final note = Note(
        id: 'note-1',
        noteDate: DateTime(today.year, today.month, today.day),
        title: 'Today',
        content: 'Hello',
        isDefault: true,
        tags: const [],
        createdAt: today,
        updatedAt: today,
      );

      Future<StorageBundle> storageFactory(
        String accessToken, {
        required String owner,
        required String repo,
        required String branch,
        Future<void> Function()? onRemoteChanged,
      }) async {
        final service = NoteService();
        return StorageBundle(
          storage: _FakeNoteStorage([note]),
          noteService: service,
        );
      }

      final repoCache = _InMemoryRepoCache([
        RepoEntry(owner: 'octocat', repo: 'notes'),
      ]);

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
                avatarUrl: '',
              ),
            ),
          ),
          storageFactory: storageFactory,
          repoCache: repoCache,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Markdown 100%'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.equal);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.equal);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      expect(find.text('Markdown 110%'), findsOneWidget);
    },
  );
}
