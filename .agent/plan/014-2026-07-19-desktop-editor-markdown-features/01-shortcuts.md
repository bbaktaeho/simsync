---
title: 포맷팅 단축키 구현 (Task 1-2)
description: ShortcutAction 확장, EditorPanel 포맷 API 공개, 전역 키 핸들러 디스패치
type: plan
created: 2026-07-19
---

# 포맷팅 단축키 (Task 1-2)

배경: 전역 단축키는 `document_screen.dart`의 `_handleHardwareKeyEvent`(HardwareKeyboard.instance.addHandler, `document_screen.dart:1226`)가 `widget.settingsController.bindings`를 순회하며 처리한다. 바인딩 로딩(`app_settings_controller.dart:230` `_loadBindings`)은 `defaultShortcutBindings`를 기준으로 저장값을 덮어쓰므로, enum에 새 액션을 추가하면 기존 사용자 설정과 자동 병합된다. 설정 화면 리바인딩 UI도 bindings 목록을 그대로 쓴다.

포맷팅 동작 자체는 `editor_panel.dart`의 `_wrapSelection`(`:792`) / `_toggleLinePrefix`(`:833`)에 이미 있다.

---

## Task 1: ShortcutAction enum + 기본 바인딩

**Files:**
- Modify: `desktop/lib/settings/shortcut_binding.dart`
- Test: `desktop/test/settings/shortcut_binding_format_test.dart` (신규)

**Interfaces:**
- Produces: `ShortcutAction.formatBold`, `.formatItalic`, `.formatStrikethrough`, `.formatInlineCode`, `.formatLink`, `.formatCheckbox`, `.formatHighlight` — Task 2가 switch에서 사용

- [ ] **Step 1: 실패하는 테스트 작성**

`desktop/test/settings/shortcut_binding_format_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/settings/shortcut_binding.dart';

ShortcutBinding _bindingFor(ShortcutAction action) =>
    defaultShortcutBindings.firstWhere((b) => b.action == action);

void main() {
  test('포맷 액션 7종의 기본 바인딩이 존재한다', () {
    expect(_bindingFor(ShortcutAction.formatBold).key, LogicalKeyboardKey.keyB);
    expect(_bindingFor(ShortcutAction.formatBold).meta, isTrue);
    expect(_bindingFor(ShortcutAction.formatBold).shift, isFalse);

    expect(_bindingFor(ShortcutAction.formatItalic).key, LogicalKeyboardKey.keyI);

    final strike = _bindingFor(ShortcutAction.formatStrikethrough);
    expect(strike.key, LogicalKeyboardKey.keyX);
    expect(strike.meta, isTrue);
    expect(strike.shift, isTrue, reason: 'cmd+X(잘라내기) 충돌 회피');

    expect(_bindingFor(ShortcutAction.formatInlineCode).key, LogicalKeyboardKey.keyE);
    expect(_bindingFor(ShortcutAction.formatLink).key, LogicalKeyboardKey.keyK);

    final checkbox = _bindingFor(ShortcutAction.formatCheckbox);
    expect(checkbox.key, LogicalKeyboardKey.keyC);
    expect(checkbox.shift, isTrue);

    final highlight = _bindingFor(ShortcutAction.formatHighlight);
    expect(highlight.key, LogicalKeyboardKey.keyH);
    expect(highlight.shift, isTrue);
  });

  test('shift 필수 바인딩은 shift 없이 매칭되지 않는다', () {
    final strike = _bindingFor(ShortcutAction.formatStrikethrough);
    final event = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyX,
      logicalKey: LogicalKeyboardKey.keyX,
      timeStamp: Duration.zero,
    );
    expect(strike.matches(event, isMetaPressed: true, isShiftPressed: true), isTrue);
    expect(strike.matches(event, isMetaPressed: true, isShiftPressed: false), isFalse);
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd desktop && flutter test test/settings/shortcut_binding_format_test.dart`
Expected: FAIL — `formatBold` getter 미정의 (컴파일 에러)

- [ ] **Step 3: enum + 기본 바인딩 추가**

`shortcut_binding.dart`의 enum을 다음으로 교체:

```dart
/// Identifiers for every bindable keyboard shortcut in the app.
enum ShortcutAction {
  openSettings('설정 열기'),
  zoomIn('확대'),
  zoomOut('축소'),
  search('검색'),
  closeTab('탭 닫기'),
  formatBold('굵게'),
  formatItalic('기울임'),
  formatStrikethrough('취소선'),
  formatInlineCode('인라인 코드'),
  formatLink('링크'),
  formatCheckbox('체크박스'),
  formatHighlight('하이라이트');

  const ShortcutAction(this.label);
  final String label;
}
```

`defaultShortcutBindings` 리스트 끝에 추가:

```dart
  // 포맷팅 단축키. cmd+X(잘라내기), cmd+C(복사), cmd+H(맥 숨기기)와의 충돌을
  // 피하려고 취소선/체크박스/하이라이트는 shift를 요구한다.
  ShortcutBinding(
    action: ShortcutAction.formatBold,
    key: LogicalKeyboardKey.keyB,
    meta: true,
  ),
  ShortcutBinding(
    action: ShortcutAction.formatItalic,
    key: LogicalKeyboardKey.keyI,
    meta: true,
  ),
  ShortcutBinding(
    action: ShortcutAction.formatStrikethrough,
    key: LogicalKeyboardKey.keyX,
    meta: true,
    shift: true,
  ),
  ShortcutBinding(
    action: ShortcutAction.formatInlineCode,
    key: LogicalKeyboardKey.keyE,
    meta: true,
  ),
  ShortcutBinding(
    action: ShortcutAction.formatLink,
    key: LogicalKeyboardKey.keyK,
    meta: true,
  ),
  ShortcutBinding(
    action: ShortcutAction.formatCheckbox,
    key: LogicalKeyboardKey.keyC,
    meta: true,
    shift: true,
  ),
  ShortcutBinding(
    action: ShortcutAction.formatHighlight,
    key: LogicalKeyboardKey.keyH,
    meta: true,
    shift: true,
  ),
```

- [ ] **Step 4: 통과 확인**

Run: `flutter test test/settings/shortcut_binding_format_test.dart` → PASS
Run: `flutter test test/settings/` → 기존 설정 테스트 전체 PASS (enum 추가로 exhaustive switch가 깨지면 이 시점에 컴파일 에러로 드러난다 — `document_screen.dart:1239`의 switch는 Task 2에서 고치므로, 여기서 깨지면 Task 2 Step 3의 switch 수정을 먼저 적용)

- [ ] **Step 5: 커밋**

```bash
git add desktop/lib/settings/shortcut_binding.dart desktop/test/settings/shortcut_binding_format_test.dart
git commit -m "feat: 포맷팅 단축키 액션과 기본 바인딩 추가"
```

주의: Step 4에서 `document_screen.dart`의 non-exhaustive switch 컴파일 에러가 나면 Task 1과 Task 2를 한 커밋으로 묶는다 (빌드 깨진 커밋 금지).

---

## Task 2: EditorPanel 포맷 API 공개 + 전역 디스패치

**Files:**
- Modify: `desktop/lib/widgets/editor_panel.dart` (`_EditorPanelState` → `EditorPanelState` 공개, `applyFormat`/`_insertLink`/`hasEditorFocus` 추가)
- Modify: `desktop/lib/screens/document_screen.dart` (`_editorKey` + switch 확장)
- Test: `desktop/test/widgets/editor_panel_format_test.dart` (신규)

**Interfaces:**
- Consumes: Task 1의 `ShortcutAction.format*`
- Produces: `EditorPanelState.hasEditorFocus → bool`, `EditorPanelState.applyFormat(ShortcutAction action) → void` — document_screen이 GlobalKey로 호출

- [ ] **Step 1: 실패하는 테스트 작성**

`desktop/test/widgets/editor_panel_format_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/models/note.dart';
import 'package:simsync/settings/shortcut_binding.dart';
import 'package:simsync/theme/app_theme.dart';
import 'package:simsync/widgets/editor_panel.dart';

Note _note(String content) {
  final now = DateTime(2026, 7, 19);
  return Note(
    id: 'n1',
    noteDate: now,
    title: 't',
    content: content,
    isDefault: true,
    tags: [],
    createdAt: now,
    updatedAt: now,
  );
}

Future<GlobalKey<EditorPanelState>> _pump(WidgetTester tester, Note note) async {
  final key = GlobalKey<EditorPanelState>();
  await tester.pumpWidget(MaterialApp(
    theme: buildLightTheme(),
    home: Scaffold(body: EditorPanel(key: key, note: note, onNoteChanged: (_) {})),
  ));
  return key;
}

TextField _contentField(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).last);

void main() {
  testWidgets('applyFormat(bold)는 선택 영역을 **로 감싼다', (tester) async {
    final key = await _pump(tester, _note('hello world'));
    final controller = _contentField(tester).controller!;
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    key.currentState!.applyFormat(ShortcutAction.formatBold);
    await tester.pump();
    expect(controller.text, '**hello** world');
  });

  testWidgets('applyFormat(strikethrough)는 ~~로 감싼다', (tester) async {
    final key = await _pump(tester, _note('abc'));
    final controller = _contentField(tester).controller!;
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
    key.currentState!.applyFormat(ShortcutAction.formatStrikethrough);
    await tester.pump();
    expect(controller.text, '~~abc~~');
  });

  testWidgets('applyFormat(checkbox)는 줄 프리픽스를 토글한다', (tester) async {
    final key = await _pump(tester, _note('todo item'));
    final controller = _contentField(tester).controller!;
    controller.selection = const TextSelection.collapsed(offset: 2);
    key.currentState!.applyFormat(ShortcutAction.formatCheckbox);
    await tester.pump();
    expect(controller.text, '- [ ] todo item');
  });

  testWidgets('applyFormat(link)는 선택을 [텍스트]()로 감싸고 캐럿을 괄호 안에 둔다',
      (tester) async {
    final key = await _pump(tester, _note('click here'));
    final controller = _contentField(tester).controller!;
    controller.selection = const TextSelection(baseOffset: 6, extentOffset: 10);
    key.currentState!.applyFormat(ShortcutAction.formatLink);
    await tester.pump();
    expect(controller.text, 'click [here]()');
    expect(controller.selection.baseOffset, 'click [here]('.length);
  });

  testWidgets('링크: 선택이 없으면 빈 링크 삽입, 캐럿은 대괄호 안', (tester) async {
    final key = await _pump(tester, _note(''));
    final controller = _contentField(tester).controller!;
    controller.selection = const TextSelection.collapsed(offset: 0);
    key.currentState!.applyFormat(ShortcutAction.formatLink);
    await tester.pump();
    expect(controller.text, '[]()');
    expect(controller.selection.baseOffset, 1);
  });
}
```

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/widgets/editor_panel_format_test.dart`
Expected: FAIL — `EditorPanelState` 미공개 (컴파일 에러)

- [ ] **Step 3: EditorPanel 수정**

`editor_panel.dart`:

1. import 추가: `import '../settings/shortcut_binding.dart';`
2. `State<EditorPanel> createState() => _EditorPanelState();` → `EditorPanelState()`
3. `class _EditorPanelState extends State<EditorPanel>` → `class EditorPanelState extends State<EditorPanel>` (파일 내 참조 이름도 전부 변경)
4. `EditorPanelState`에 메서드 추가 (`_renumberList` 아래):

```dart
  /// 전역 단축키 핸들러(document_screen)가 포커스 여부를 확인할 때 사용.
  bool get hasEditorFocus => _contentFocusNode.hasFocus;

  /// 전역 단축키의 포맷팅 액션을 에디터에 적용한다. 동작은 툴바와 동일한
  /// _wrapSelection/_toggleLinePrefix를 재사용한다.
  void applyFormat(ShortcutAction action) {
    if (widget.isReadOnly || widget.note == null) return;
    switch (action) {
      case ShortcutAction.formatBold:
        _wrapSelection('**');
      case ShortcutAction.formatItalic:
        _wrapSelection('*');
      case ShortcutAction.formatStrikethrough:
        _wrapSelection('~~');
      case ShortcutAction.formatInlineCode:
        _wrapSelection('`');
      case ShortcutAction.formatHighlight:
        _wrapSelection('==');
      case ShortcutAction.formatCheckbox:
        _toggleLinePrefix('- [ ] ');
      case ShortcutAction.formatLink:
        _insertLink();
      case ShortcutAction.openSettings:
      case ShortcutAction.zoomIn:
      case ShortcutAction.zoomOut:
      case ShortcutAction.search:
      case ShortcutAction.closeTab:
        break;
    }
  }

  /// 선택 영역을 [텍스트]() 링크로 만든다. 선택이 있으면 캐럿을 URL 자리에,
  /// 없으면 빈 링크를 삽입하고 캐럿을 대괄호 안에 둔다.
  void _insertLink() {
    final value = _contentController.value;
    final text = value.text;
    final selection = value.selection;
    if (!selection.isValid) return;
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(0, text.length);
    final selected = text.substring(start, end);
    final replacement = '[$selected]()';
    _contentController.value = TextEditingValue(
      text: text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(
        offset: selected.isEmpty ? start + 1 : start + replacement.length - 1,
      ),
    );
    _onContentChanged();
  }
```

- [ ] **Step 4: document_screen 디스패치**

`document_screen.dart`:

1. 상태 필드 추가 (`_openTabIds` 근처):

```dart
  /// 포맷팅 단축키를 에디터 상태로 전달하기 위한 키.
  final GlobalKey<EditorPanelState> _editorKey = GlobalKey<EditorPanelState>();
```

2. `_buildRightPanel`의 `EditorPanel(` 생성자에 `key: _editorKey,` 추가 (`document_screen.dart:1360`).
3. `_handleHardwareKeyEvent`의 switch(`:1239`)에 케이스 추가:

```dart
          case ShortcutAction.formatBold:
          case ShortcutAction.formatItalic:
          case ShortcutAction.formatStrikethrough:
          case ShortcutAction.formatInlineCode:
          case ShortcutAction.formatLink:
          case ShortcutAction.formatCheckbox:
          case ShortcutAction.formatHighlight:
            // 에디터 본문에 포커스가 있을 때만 소비한다. 아니면 시스템 기본
            // 동작(예: cmd+shift+X가 다른 곳에서 갖는 의미)을 막지 않는다.
            final editor = _editorKey.currentState;
            if (editor == null || !editor.hasEditorFocus) return false;
            editor.applyFormat(binding.action);
```

- [ ] **Step 5: 통과 확인**

Run: `flutter test test/widgets/editor_panel_format_test.dart && flutter test test/widgets/ test/screens/`
Expected: 신규 + 기존 위젯/스크린 테스트 전체 PASS

- [ ] **Step 6: analyze + 커밋**

```bash
cd desktop && flutter analyze
git add desktop/lib/widgets/editor_panel.dart desktop/lib/screens/document_screen.dart desktop/test/widgets/editor_panel_format_test.dart
git commit -m "feat: 에디터 포맷팅 단축키 연결 (cmd+B/I/E/K, cmd+shift+X/C/H)"
```
