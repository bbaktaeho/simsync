import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:simsync_mobile/models/note.dart';
import 'package:simsync_mobile/screens/editor_screen.dart';
import 'package:simsync_mobile/settings/app_settings_controller.dart';
import 'package:simsync_mobile/theme/app_theme.dart';
import 'package:simsync_mobile/widgets/editor_panel.dart';

import 'mobile_bug_regressions_test.dart' show InMemoryNoteStorage;

/// 하단 툴바는 모바일 입력의 주 수단이다 — 눌렀을 때 원문이 정확히 어떻게
/// 바뀌는지 잠가 둔다.
void main() {
  late AppSettingsController settings;

  setUpAll(() => initializeDateFormatting('ko'));

  setUp(() {
    settings = AppSettingsController(defaultLocalNotePath: '/tmp/simsync-test');
  });

  tearDown(() => settings.dispose());

  Future<TextEditingController> pumpEditor(
    WidgetTester tester,
    String content,
  ) async {
    final now = DateTime(2026, 8, 16);
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: EditorScreen(
        storage: InMemoryNoteStorage(),
        onNoteChanged: (_) {},
        onNoteDeleted: (_) {},
        note: Note(
          id: 'n1',
          noteDate: now,
          title: 't',
          content: content,
          isDefault: true,
          tags: const [],
          createdAt: now,
          updatedAt: now,
        ),
        settingsController: settings,
      ),
    ));
    await tester.pumpAndSettle();
    return tester.widget<EditorPanel>(find.byType(EditorPanel)).controller;
  }

  Future<void> tapTool(WidgetTester tester, IconData icon) async {
    await tester.ensureVisible(find.byIcon(icon).first);
    await tester.tap(find.byIcon(icon).first);
    await tester.pump();
  }

  testWidgets('할 일 버튼은 줄 프리픽스를 토글한다 (두 번 눌러도 겹치지 않는다)',
      (tester) async {
    final controller = await pumpEditor(tester, 'todo');
    controller.selection = const TextSelection.collapsed(offset: 4);

    await tapTool(tester, Icons.check_box_outlined);
    expect(controller.text, '- [ ] todo');

    await tapTool(tester, Icons.check_box_outlined);
    expect(controller.text, 'todo', reason: '같은 프리픽스를 다시 누르면 해제');
  });

  testWidgets('목록 버튼은 기존 블록 프리픽스를 교체한다', (tester) async {
    final controller = await pumpEditor(tester, '- [ ] todo');
    controller.selection = const TextSelection.collapsed(offset: 8);

    await tapTool(tester, Icons.format_list_bulleted_rounded);
    expect(controller.text, '- todo', reason: '체크박스 → 불릿 (쌓이지 않는다)');
  });

  testWidgets('들여쓰기/내어쓰기 버튼이 Tab을 대신한다', (tester) async {
    final controller = await pumpEditor(tester, '- a\n- b');
    controller.selection = const TextSelection.collapsed(offset: 7);

    await tapTool(tester, Icons.format_indent_increase_rounded);
    expect(controller.text, '- a\n  - b');

    await tapTool(tester, Icons.format_indent_decrease_rounded);
    expect(controller.text, '- a\n- b');
  });

  testWidgets('인용 버튼은 이 앱의 문법인 | 를 넣는다 (> 는 details 트리거)',
      (tester) async {
    final controller = await pumpEditor(tester, 'quote');
    controller.selection = const TextSelection.collapsed(offset: 5);

    await tapTool(tester, Icons.format_quote_rounded);
    expect(controller.text, '| quote');
  });

  testWidgets('표 버튼은 파싱 가능한 표 블록을 넣는다', (tester) async {
    final controller = await pumpEditor(tester, 'x');
    controller.selection = const TextSelection.collapsed(offset: 1);

    await tapTool(tester, Icons.table_chart_outlined);
    expect(controller.text, contains('| 항목 | 값 |'));
    expect(controller.text, contains('| --- | --- |'));
  });

  testWidgets('굵게 버튼은 선택을 감싼다', (tester) async {
    final controller = await pumpEditor(tester, 'bold me');
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 4);

    await tester.ensureVisible(find.text('B'));
    await tester.tap(find.text('B'));
    await tester.pump();

    expect(controller.text, '**bold** me');
  });
}
