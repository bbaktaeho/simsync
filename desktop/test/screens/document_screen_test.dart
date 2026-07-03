import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simsync/auth/auth_models.dart';
import 'package:simsync/auth/auth_provider.dart';
import 'package:simsync/auth/auth_service.dart';
import 'package:simsync/main.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/services/note_service.dart';
import 'package:simsync/storage/github/repo_cache.dart';
import 'package:simsync/storage/note_storage.dart';
import 'package:simsync/widgets/editor_tab_bar.dart';
import 'package:simsync/widgets/note_list_section.dart';

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

  final Map<String, String> textFiles = {};

  @override
  Future<String?> readTextFile(String relativePath) async =>
      textFiles[relativePath];

  @override
  Future<void> writeTextFile(String relativePath, String content) async {
    textFiles[relativePath] = content;
  }
}

class _FakeAuthService implements AuthService {
  _FakeAuthService({required this.restoreResult});

  final AuthSession? restoreResult;

  @override
  Future<void> logout() async {}

  @override
  Future<AuthSession?> restoreSession() async => restoreResult;

  @override
  Future<AuthSession> signIn({
    DeviceAuthorizationPrompt? onAuthorizationPrompt,
  }) async =>
      throw UnimplementedError();

  @override
  void cancelSignIn() {}

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

  testWidgets(
    'cmd+W closes the active editor tab',
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
        return StorageBundle(
          storage: _FakeNoteStorage([note]),
          noteService: NoteService(),
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

      // The default note auto-opens in a tab.
      expect(find.text('Markdown 100%'), findsOneWidget);
      expect(find.text('No notes for this date'), findsNothing);

      // Cmd+W closes the active tab.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(find.text('No notes for this date'), findsOneWidget);
      expect(find.text('Markdown 100%'), findsNothing);
    },
  );

  testWidgets(
    'memo tab filters notes to memos only',
    (WidgetTester tester) async {
      final today = DateTime.now();
      final dailyNote = Note(
        id: 'daily-1',
        noteDate: DateTime(today.year, today.month, today.day),
        title: 'Daily one',
        content: '',
        isDefault: true,
        tags: const [],
        createdAt: today,
        updatedAt: today,
      );
      final memoNote = Note(
        id: 'memo-1',
        noteDate: DateTime(today.year, today.month, today.day),
        title: 'Memo one',
        content: '',
        isDefault: false,
        tags: const [],
        createdAt: today,
        updatedAt: today.add(const Duration(seconds: 1)),
        isMemo: true,
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
          storage: _FakeNoteStorage([dailyNote, memoNote]),
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

      // Scope assertions to the sidebar list: the editor keeps showing the
      // active tab regardless of the daily/memo list filter.
      Finder inList(String text) => find.descendant(
            of: find.byType(NoteListSection),
            matching: find.text(text),
          );

      // Daily tab: memo not in the list.
      expect(inList('Daily one'), findsWidgets);
      expect(inList('Memo one'), findsNothing);

      // Switch to memo tab.
      await tester.tap(find.text('memo'));
      await tester.pumpAndSettle();

      // Memo tab: memo visible, daily filtered out.
      expect(inList('Memo one'), findsWidgets);
      expect(inList('Daily one'), findsNothing);

      // Back to daily.
      await tester.tap(find.text('daily'));
      await tester.pumpAndSettle();

      expect(inList('Daily one'), findsWidgets);
      expect(inList('Memo one'), findsNothing);
    },
  );

  testWidgets(
    'returning to daily after opening a memo keeps the original date',
    (WidgetTester tester) async {
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      // A memo dated in a different month than today.
      final memoDate = DateTime(today.year, today.month - 2, 1);

      final dailyNote = Note(
        id: 'daily-today',
        noteDate: todayDate,
        title: 'Today daily',
        content: '',
        isDefault: true,
        tags: const [],
        createdAt: today,
        updatedAt: today,
      );
      final memoNote = Note(
        id: 'memo-pastmonth',
        noteDate: memoDate,
        title: 'Past memo',
        content: '',
        isDefault: false,
        tags: const [],
        createdAt: memoDate,
        updatedAt: memoDate,
        isMemo: true,
      );

      Future<StorageBundle> storageFactory(
        String accessToken, {
        required String owner,
        required String repo,
        required String branch,
        Future<void> Function()? onRemoteChanged,
      }) async {
        return StorageBundle(
          storage: _FakeNoteStorage([dailyNote, memoNote]),
          noteService: NoteService(),
        );
      }

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
          repoCache: _InMemoryRepoCache([
            RepoEntry(owner: 'octocat', repo: 'notes'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      // Start on the daily tab showing today's note.
      expect(find.text('Today daily'), findsWidgets);

      // Open the memo tab and select the past-dated memo.
      await tester.tap(find.text('memo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Past memo').first);
      await tester.pumpAndSettle();

      // Return to the daily tab — today's note must reappear, proving the
      // calendar date was NOT moved to the memo's date.
      await tester.tap(find.text('daily'));
      await tester.pumpAndSettle();

      expect(find.text('Today daily'), findsWidgets);
    },
  );

  testWidgets(
    'opens notes in tabs and returns to the create screen when all are closed',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final today = DateTime.now();
      final date = DateTime(today.year, today.month, today.day);
      final noteA = Note(
        id: 'a',
        noteDate: date,
        title: 'Note A',
        content: '',
        isDefault: true,
        tags: const [],
        createdAt: today,
        updatedAt: today,
      );
      final noteB = Note(
        id: 'b',
        noteDate: date,
        title: 'Note B',
        content: '',
        isDefault: false,
        tags: const [],
        createdAt: today,
        updatedAt: today.add(const Duration(seconds: 1)),
      );

      Future<StorageBundle> storageFactory(
        String accessToken, {
        required String owner,
        required String repo,
        required String branch,
        Future<void> Function()? onRemoteChanged,
      }) async {
        return StorageBundle(
          storage: _FakeNoteStorage([noteA, noteB]),
          noteService: NoteService(),
        );
      }

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
          repoCache: _InMemoryRepoCache([
            RepoEntry(owner: 'octocat', repo: 'notes'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      EditorTabBar tabBar() =>
          tester.widget<EditorTabBar>(find.byType(EditorTabBar));

      // Initial load opens the date's default note as a single tab.
      expect(find.byType(EditorTabBar), findsOneWidget);
      expect(tabBar().tabs.length, 1);
      expect(tabBar().tabs.first.id, 'a');

      // The tab bar fills the editor width (left-aligned), not just the width
      // of a single content-sized tab.
      expect(
        tester.getSize(find.byType(EditorTabBar)).width,
        greaterThan(400),
      );

      // Opening a second note from the list adds a second tab.
      await tester.tap(
        find.descendant(
          of: find.byType(NoteListSection),
          matching: find.text('Note B'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tabBar().tabs.length, 2);
      expect(tabBar().activeNoteId, 'b');

      // Closing the active tab activates the neighbour.
      await tester.tap(
        find.descendant(
          of: find.byType(EditorTabBar),
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      await tester.pumpAndSettle();
      expect(tabBar().tabs.length, 1);
      expect(tabBar().activeNoteId, 'a');

      // Closing the last tab returns to the create screen.
      await tester.tap(
        find.descendant(
          of: find.byType(EditorTabBar),
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EditorTabBar), findsNothing);
      expect(find.text('No notes for this date'), findsOneWidget);
    },
  );

  testWidgets(
    'closing a dirty tab activates the neighbour without re-selecting it',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final today = DateTime.now();
      final date = DateTime(today.year, today.month, today.day);
      final noteA = Note(
        id: 'a',
        noteDate: date,
        title: 'Note A',
        content: 'A body',
        isDefault: true,
        tags: const [],
        createdAt: today,
        updatedAt: today,
      );
      final noteB = Note(
        id: 'b',
        noteDate: date,
        title: 'Note B',
        content: 'B body',
        isDefault: false,
        tags: const [],
        createdAt: today,
        updatedAt: today.add(const Duration(seconds: 1)),
      );

      Future<StorageBundle> storageFactory(
        String accessToken, {
        required String owner,
        required String repo,
        required String branch,
        Future<void> Function()? onRemoteChanged,
      }) async {
        return StorageBundle(
          storage: _FakeNoteStorage([noteA, noteB]),
          noteService: NoteService(),
        );
      }

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
          repoCache: _InMemoryRepoCache([
            RepoEntry(owner: 'octocat', repo: 'notes'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      EditorTabBar tabBar() =>
          tester.widget<EditorTabBar>(find.byType(EditorTabBar));

      // Open B and make it dirty.
      await tester.tap(
        find.descendant(
          of: find.byType(NoteListSection),
          matching: find.text('Note B'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tabBar().activeNoteId, 'b');

      final contentField = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText == 'Start writing in markdown...',
      );
      await tester.enterText(contentField, 'edited B body');
      await tester.pump();

      // Close the dirty active tab.
      await tester.tap(
        find.descendant(
          of: find.byType(EditorTabBar),
          matching: find.byIcon(Icons.close_rounded),
        ),
      );
      await tester.pumpAndSettle();

      // The neighbour A must be the active tab; B must be gone, not re-selected.
      expect(tabBar().tabs.length, 1);
      expect(tabBar().activeNoteId, 'a');
      expect(tabBar().tabs.map((t) => t.id), isNot(contains('b')));

      // Flush any pending debounce timers.
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets(
    'title bar theme toggle flips between light and dark',
    (WidgetTester tester) async {
      Future<StorageBundle> storageFactory(
        String accessToken, {
        required String owner,
        required String repo,
        required String branch,
        Future<void> Function()? onRemoteChanged,
      }) async {
        return StorageBundle(
          storage: _FakeNoteStorage(const []),
          noteService: NoteService(),
        );
      }

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
          repoCache: _InMemoryRepoCache([
            RepoEntry(owner: 'octocat', repo: 'notes'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      // Tests run with light platform brightness and the default System theme,
      // so the toggle offers "go dark" (moon icon).
      expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);

      await tester.tap(find.byTooltip('다크 모드로'));
      await tester.pumpAndSettle();

      // Now dark → the toggle offers "go light" (sun icon).
      expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);
      expect(find.byIcon(Icons.dark_mode_rounded), findsNothing);
    },
  );
}
