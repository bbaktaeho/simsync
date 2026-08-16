import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:simsync_mobile/models/note.dart';
import 'package:simsync_mobile/screens/review_screen.dart';
import 'package:simsync_mobile/storage/note_storage.dart';
import 'package:simsync_mobile/theme/app_theme.dart';

/// 모바일은 리뷰 뷰어다 — 데스크탑이 동기화 스토리지에 써 둔 마크다운을 읽어
/// 보여주기만 한다. 경로 규약이 어긋나면 조용히 빈 화면이 되므로 못 박는다.
void main() {
  setUpAll(() => initializeDateFormatting('ko'));

  Future<void> pump(WidgetTester tester, _FakeStore store) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: ReviewScreen(storage: store),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('먼슬리 리뷰와 주차별 리뷰를 읽어 렌더한다', (tester) async {
    final now = DateTime.now();
    final ym = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final store = _FakeStore({
      'notes/$ym/monthly-review.md': '# 이번 달 요약\n먼슬리 본문',
      'notes/$ym/1주차/weekly-review.md': '# 1주차\n위클리 본문',
    });

    await pump(tester, store);

    expect(find.text('먼슬리 리뷰'), findsOneWidget);
    expect(find.textContaining('먼슬리 본문'), findsOneWidget);
    expect(find.textContaining('위클리 본문'), findsOneWidget);
    expect(find.textContaining('1주차'), findsWidgets);
  });

  testWidgets('리뷰가 없으면 안내를 보여준다 (생성은 데스크탑에서)', (tester) async {
    await pump(tester, _FakeStore({}));

    expect(find.text('이 달의 리뷰가 없습니다'), findsOneWidget);
    expect(find.textContaining('데스크탑에서 만들고'), findsOneWidget);
  });

  testWidgets('빈 문자열 리뷰는 카드로 만들지 않는다', (tester) async {
    final now = DateTime.now();
    final ym = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    await pump(tester, _FakeStore({'notes/$ym/1주차/weekly-review.md': '   '}));

    expect(find.text('이 달의 리뷰가 없습니다'), findsOneWidget);
  });
}

/// 텍스트 파일만 들고 있는 최소 스토어. 노트 CRUD는 이 화면과 무관하다.
class _FakeStore implements NoteStorage {
  _FakeStore(this.files);

  final Map<String, String> files;

  @override
  Future<String?> readTextFile(String relativePath) async => files[relativePath];

  @override
  Future<void> writeTextFile(String relativePath, String content) async {
    files[relativePath] = content;
  }

  @override
  Future<List<Note>> listAllNotes() async => const [];

  @override
  Future<List<Note>> listNotes(DateTime date) async => const [];

  @override
  Future<List<DateTime>> listDates(String yearMonth) async => const [];

  @override
  Future<Note?> getNote(String noteId, DateTime noteDate) async => null;

  @override
  Future<void> saveNote(Note note) async {}

  @override
  Future<void> deleteNote(Note note) async {}

  @override
  Future<Uint8List?> readBinaryFile(String relativePath) async => null;

  @override
  Future<void> writeBinaryFile(String relativePath, Uint8List bytes) async {}

  @override
  String noteDirPath(DateTime noteDate) => 'notes';
}
