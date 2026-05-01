---
title: Stage 1+2 Fixes and Enhancements Plan
description: Settings/Search 버그 수정 3건, 단축키 설정 카테고리, 검색 UI 재설계
type: plan
created: 2026-03-15
---

# Stage 1+2 Fixes and Enhancements Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Settings 버그 3건을 수정하고, 단축키 설정 카테고리를 추가하고, 검색 UI를 상단 중앙 + 결과 패널 + 키워드 하이라이트 방식으로 재설계한다.

**Architecture:** 버그 수정은 RepoSelectionScreen의 독립적 SharedPreferences 접근을 제거하고 AppSettingsController를 single source of truth로 통합한다. 검색 UI는 에디터 영역 왼쪽 1/3에 결과 패널을 두고, NoteSearchIndex가 매칭 라인 + context를 반환하도록 확장한다. 단축키 설정은 ShortcutBinding 모델을 추가하고 settings에 Shortcuts 카테고리를 넣는다.

**Tech Stack:** Flutter (Dart), SharedPreferences, existing AppSettingsController pattern

---

## File Structure

### Bug Fixes (Phase 1)

| Action | File | Responsibility |
|--------|------|---------------|
| Modify | `desktop/lib/screens/repo_selection_screen.dart` | 독립적 path 로직 제거, AppSettingsController 사용 |
| Modify | `desktop/lib/main.dart` | RepoSelectionScreen에 settingsController 전달 |
| Modify | `desktop/lib/screens/document_screen.dart` | local path 변경 시 즉시 local 노트 제거, progress bar 제거 |
| Modify | `desktop/lib/widgets/note_search_section.dart` | isLoading/progress bar 관련 코드 제거 |

### Features (Phase 2)

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `desktop/lib/settings/shortcut_binding.dart` | 단축키 바인딩 모델 (action, key combination, isFixed) |
| Modify | `desktop/lib/settings/app_settings.dart` | searchContextLines 필드 추가 |
| Modify | `desktop/lib/settings/app_settings_controller.dart` | shortcut, searchContextLines persistence 추가 |
| Modify | `desktop/lib/screens/settings_screen.dart` | Shortcuts 카테고리 추가, searchContextLines 컨트롤 |
| Create | `desktop/lib/search/search_result.dart` | SearchResult 모델 (note, matchedLine, contextBefore, contextAfter) |
| Modify | `desktop/lib/search/note_search_index.dart` | searchWithContext() 메서드 추가 |
| Create | `desktop/lib/widgets/search_results_panel.dart` | 검색 결과 리스트 패널 (키워드 하이라이트, context lines) |
| Modify | `desktop/lib/screens/document_screen.dart` | 검색 UI 재배치 (상단 중앙 + 좌측 1/3 결과 패널), Cmd+Shift+F |

### Tests

| Action | File |
|--------|------|
| Modify | `desktop/test/widget_test.dart` | RepoSelectionScreen path 동기화 테스트 |
| Modify | `desktop/test/search/note_search_index_test.dart` | searchWithContext 테스트 |
| Create | `desktop/test/search/search_result_test.dart` | SearchResult 모델 테스트 |
| Create | `desktop/test/settings/shortcut_binding_test.dart` | ShortcutBinding 모델 테스트 |
| Modify | `desktop/test/screens/document_screen_test.dart` | 검색 UI, Cmd+Shift+F 테스트 |
| Modify | `desktop/test/widgets/note_search_section_test.dart` | progress bar 제거 반영 |

---

## Phase 1: Bug Fixes

### Task 1: RepoSelectionScreen 로컬 경로 동기화 버그 수정

RepoSelectionScreen이 SharedPreferences에 직접 접근하여 `'local_note_path'`를 읽고 쓰는데, AppSettingsController의 in-memory 값과 동기화되지 않는다. settings를 열면 controller의 기본값이 보인다.

**Files:**
- Modify: `desktop/lib/screens/repo_selection_screen.dart`
- Modify: `desktop/lib/main.dart:397-404`
- Modify: `desktop/test/widget_test.dart`

- [ ] **Step 1: failing test 추가**

`desktop/test/widget_test.dart`에 테스트를 추가한다. RepoSelectionScreen에서 local path를 변경한 뒤 authenticated 상태에서 settings를 열면 변경된 path가 보여야 한다.

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd desktop && flutter test test/widget_test.dart -v`
Expected: FAIL — settings에서 기본 경로가 보임

- [ ] **Step 3: RepoSelectionScreen에 AppSettingsController 연결**

`repo_selection_screen.dart`에서:
- `SharedPreferences` import 제거
- `_localNotePath` 필드 제거
- `_loadLocalNotePath()` 메서드 전체 제거
- `initState`에서 `_loadLocalNotePath()` 호출 제거
- constructor에 `AppSettingsController settingsController` 파라미터 추가
- `_buildLocalPathSection` 등에서 `_localNotePath` 대신 `widget.settingsController.value.localNotePath` 사용
- `_pickLocalPath()`에서 SharedPreferences 직접 쓰기 대신 `widget.settingsController.setLocalNotePath(result)` 호출
- build에서 `AnimatedBuilder(animation: widget.settingsController, ...)` 등으로 controller 변경 감지 (또는 ListenableBuilder)

`main.dart`에서:
- `RepoSelectionScreen` 생성 시 (line 398-404) `settingsController: _settingsController`를 전달

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd desktop && flutter test test/widget_test.dart -v`
Expected: PASS

- [ ] **Step 5: 전체 테스트 + analyze**

Run: `cd desktop && flutter analyze && flutter test`
Expected: 모두 통과

- [ ] **Step 6: Commit**

```bash
git add desktop/lib/screens/repo_selection_screen.dart desktop/lib/main.dart desktop/test/widget_test.dart
git commit -m "fix: sync local note path between repo selection and settings via AppSettingsController"
```

---

### Task 2: 로컬 경로 변경 시 이전 노트 즉시 제거

local path를 변경하면 StorageBundle이 교체되지만, 이전 local 노트가 `_allNotes` 목록에서 제거되기 전에 UI가 렌더링된다.

**Files:**
- Modify: `desktop/lib/screens/document_screen.dart:116-129`
- Modify: `desktop/test/widget_test.dart`

- [ ] **Step 1: failing test 추가**

`desktop/test/widget_test.dart`에 테스트를 추가한다. local path 변경 직후 (새 storage 로드 완료 전) 이전 경로 노트가 즉시 사라져야 한다.

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd desktop && flutter test test/widget_test.dart -v`
Expected: FAIL

- [ ] **Step 3: didUpdateWidget에서 즉시 local 노트 제거**

`document_screen.dart`의 `didUpdateWidget`에서 `localStorage`가 변경되면:
1. `_allNotes`에서 `storageType == StorageType.local`인 노트를 즉시 제거
2. `_selectedNote`가 local 노트였다면 null로 초기화
3. 그 후 `_loadNotes()` 호출

주의: 기존 didUpdateWidget에서 `storage`와 `localStorage` 변경을 한 조건으로 묶고 있다. `localStorage`만 변경된 경우에만 local 노트를 제거해야 하므로 조건을 분리한다.

```dart
// localStorage 변경 시 이전 local 노트 즉시 제거
if (oldWidget.localStorage != widget.localStorage) {
  setState(() {
    _allNotes.removeWhere((n) => n.storageType == StorageType.local);
    if (_selectedNote?.storageType == StorageType.local) {
      _selectedNote = null;
    }
  });
}
// storage 또는 localStorage 변경 시 전체 노트 재로드
if (oldWidget.storage != widget.storage ||
    oldWidget.localStorage != widget.localStorage) {
  unawaited(_loadNotes());
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd desktop && flutter test test/widget_test.dart -v`
Expected: PASS

- [ ] **Step 5: 전체 테스트 + analyze**

Run: `cd desktop && flutter analyze && flutter test`
Expected: 모두 통과

- [ ] **Step 6: Commit**

```bash
git add desktop/lib/screens/document_screen.dart desktop/test/widget_test.dart
git commit -m "fix: immediately clear local notes from list when local path changes"
```

---

### Task 3: 검색 progress bar 제거

in-memory index rebuild는 사실상 즉각적이므로 progress bar가 불필요하다. 노트 저장 후 sync engine이 remote change를 감지하면 full reload -> rebuildSearchIndex -> progress bar가 매번 나타나는 것이 원인이다.

**Files:**
- Modify: `desktop/lib/screens/document_screen.dart:89-97,607-626`
- Modify: `desktop/lib/widgets/note_search_section.dart`
- Modify: `desktop/test/widgets/note_search_section_test.dart`

- [ ] **Step 1: NoteSearchSection에서 isLoading/progress bar 제거**

`note_search_section.dart`:
- `isLoading` 파라미터와 `LinearProgressIndicator` 관련 코드 제거

- [ ] **Step 2: DocumentScreen에서 _isSearchLoading 상태 제거**

`document_screen.dart`:
- `_isSearchLoading` 필드 제거
- `_rebuildSearchIndex`에서 `_isSearchLoading` 설정/해제 라인 제거
- `NoteSearchSection` 호출부에서 `isLoading: _isSearchLoading` 제거

- [ ] **Step 3: 관련 테스트 갱신**

`note_search_section_test.dart`에서 `isLoading` 파라미터를 전달하는 부분이 있다면 제거. 현재 테스트에서는 `isLoading`을 명시적으로 테스트하지 않으므로 이 step은 no-op일 수 있다. 컴파일 에러가 나는 부분만 수정한다.

참고: Task 3은 순수 삭제 작업이므로 failing test를 먼저 추가하는 TDD 패턴을 적용하지 않는다. 대신 삭제 후 기존 테스트가 모두 통과하는 것으로 검증한다.

- [ ] **Step 4: 전체 테스트 + analyze**

Run: `cd desktop && flutter analyze && flutter test`
Expected: 모두 통과

- [ ] **Step 5: Commit**

```bash
git add desktop/lib/screens/document_screen.dart desktop/lib/widgets/note_search_section.dart desktop/test/widgets/note_search_section_test.dart
git commit -m "fix: remove search progress bar that appeared on every note edit"
```

---

## Phase 2: Features

### Task 4: 단축키 설정 카테고리

설정에 "Shortcuts" 카테고리를 추가한다. 현재 바인딩된 단축키 목록을 보여주고, 일부 단축키는 사용자가 수정할 수 있다. `Cmd + ,` (설정 열기)는 고정.

**Files:**
- Create: `desktop/lib/settings/shortcut_binding.dart`
- Modify: `desktop/lib/settings/app_settings.dart`
- Modify: `desktop/lib/settings/app_settings_controller.dart`
- Modify: `desktop/lib/screens/settings_screen.dart`
- Modify: `desktop/lib/screens/document_screen.dart`
- Create: `desktop/test/settings/shortcut_binding_test.dart`

- [ ] **Step 1: ShortcutBinding 모델 생성**

`desktop/lib/settings/shortcut_binding.dart`를 생성한다:

```dart
import 'package:flutter/services.dart';

class ShortcutBinding {
  final String action;
  final String label;
  final LogicalKeyboardKey key;
  final bool meta;
  final bool shift;
  final bool alt;
  final bool isFixed;

  const ShortcutBinding({
    required this.action,
    required this.label,
    required this.key,
    this.meta = false,
    this.shift = false,
    this.alt = false,
    this.isFixed = false,
  });

  String get displayString {
    final parts = <String>[];
    if (meta) parts.add('Cmd');
    if (shift) parts.add('Shift');
    if (alt) parts.add('Alt');
    parts.add(key.keyLabel);
    return parts.join(' + ');
  }

  ShortcutBinding copyWith({
    LogicalKeyboardKey? key,
    bool? meta,
    bool? shift,
    bool? alt,
  }) {
    return ShortcutBinding(
      action: action,
      label: label,
      key: key ?? this.key,
      meta: meta ?? this.meta,
      shift: shift ?? this.shift,
      alt: alt ?? this.alt,
      isFixed: isFixed,
    );
  }

  /// modifier 상태를 파라미터로 받아 테스트 가능하게 한다.
  /// DocumentScreen에서 호출 시 HardwareKeyboard.instance에서 값을 전달한다.
  bool matches(KeyEvent event, {
    required bool isMetaPressed,
    required bool isShiftPressed,
    required bool isAltPressed,
  }) {
    if (event.logicalKey != key) return false;
    if (meta != isMetaPressed) return false;
    if (shift != isShiftPressed) return false;
    if (alt != isAltPressed) return false;
    return true;
  }

  Map<String, dynamic> toJson() => {
    'action': action,
    'keyId': key.keyId,
    'meta': meta,
    'shift': shift,
    'alt': alt,
  };

  static ShortcutBinding? fromJson(
    Map<String, dynamic> json,
    ShortcutBinding defaultBinding,
  ) {
    final keyId = json['keyId'] as int?;
    if (keyId == null) return null;
    final logicalKey = LogicalKeyboardKey.findKeyByKeyId(keyId);
    if (logicalKey == null) return null;
    return defaultBinding.copyWith(
      key: logicalKey,
      meta: json['meta'] as bool? ?? defaultBinding.meta,
      shift: json['shift'] as bool? ?? defaultBinding.shift,
      alt: json['alt'] as bool? ?? defaultBinding.alt,
    );
  }
}
```

- [ ] **Step 2: ShortcutBinding 테스트**

`desktop/test/settings/shortcut_binding_test.dart`를 생성한다:
- `displayString`이 올바른 형식을 반환하는지
- `matches`가 올바른 키 조합에서 true를 반환하는지
- `toJson` / `fromJson` 라운드트립이 정상인지
- `isFixed`인 바인딩의 `copyWith`가 동작하는지

Run: `cd desktop && flutter test test/settings/shortcut_binding_test.dart -v`
Expected: PASS

- [ ] **Step 3: AppSettings에 searchContextLines 추가**

`app_settings.dart`에:
- `static const int defaultSearchContextLines = 3;`
- `static const int minSearchContextLines = 1;`
- `static const int maxSearchContextLines = 10;`
- `final int searchContextLines` 필드
- `copyWith`, `==`, `hashCode`에 반영

- [ ] **Step 4: AppSettingsController에 shortcut과 searchContextLines persistence 추가**

`app_settings_controller.dart`에:
- `static const String searchContextLinesKey = 'search_context_lines';`
- `static const String shortcutOverridesKey = 'shortcut_overrides';`
- `load()`에서 searchContextLines 읽기
- `setSearchContextLines(int value)` 메서드
- 기본 단축키 목록 (defaultBindings) 정의: settings, zoomIn, zoomOut, search
- `load()`에서 shortcut overrides 읽기 (JSON string -> Map)
- `updateShortcut(String action, ShortcutBinding binding)` 메서드
- `List<ShortcutBinding> get bindings` getter

- [ ] **Step 5: 설정 controller 테스트 갱신**

`desktop/test/settings/app_settings_controller_test.dart`에:
- searchContextLines persistence 테스트
- shortcut override persistence 테스트

Run: `cd desktop && flutter test test/settings/app_settings_controller_test.dart -v`
Expected: PASS

- [ ] **Step 6: Settings에 Shortcuts pane 추가**

`settings_screen.dart`에:
- `_SettingsPane` enum에 `shortcuts` 추가
- navigation rail에 Shortcuts 아이템 추가 (icon: `Icons.keyboard_rounded`)
- `_buildShortcutsPane` 메서드: 바인딩 목록을 카드로 표시
- 각 바인딩 옆에 현재 키 조합 표시
- `isFixed`가 아닌 바인딩은 "Edit" 버튼 -> 키 입력 캡처 다이얼로그
- 키 캡처 다이얼로그: `Focus` widget + `onKeyEvent` callback으로 다음 키 조합을 캡처하고 저장 (RawKeyboardListener는 deprecated)

- [ ] **Step 7: DocumentScreen에서 shortcut config 사용**

`document_screen.dart`의 `_handleHardwareKeyEvent`에서:
- 하드코딩된 키 비교 대신 `settingsController.bindings`를 순회하며 `binding.matches(event)` 사용
- `Cmd + ,`는 고정이므로 config 변경과 무관하게 항상 동작

- [ ] **Step 8: 전체 테스트 + analyze**

Run: `cd desktop && flutter analyze && flutter test`
Expected: 모두 통과

- [ ] **Step 9: Commit**

```bash
git add desktop/lib/settings/shortcut_binding.dart desktop/lib/settings/app_settings.dart \
  desktop/lib/settings/app_settings_controller.dart desktop/lib/screens/settings_screen.dart \
  desktop/lib/screens/document_screen.dart desktop/test/settings/
git commit -m "feat: add shortcuts category to settings with view and edit support"
```

---

### Task 5: SearchResult 모델 및 context 검색

검색 결과에 매칭 라인과 주변 context 라인을 포함하는 모델을 만든다.

**Files:**
- Create: `desktop/lib/search/search_result.dart`
- Modify: `desktop/lib/search/note_search_index.dart`
- Create: `desktop/test/search/search_result_test.dart`
- Modify: `desktop/test/search/note_search_index_test.dart`

- [ ] **Step 1: SearchResult 모델 생성**

`desktop/lib/search/search_result.dart`:

```dart
import '../models/note.dart';

class SearchMatch {
  final int lineNumber;
  final String line;
  final int matchStart;
  final int matchEnd;

  const SearchMatch({
    required this.lineNumber,
    required this.line,
    required this.matchStart,
    required this.matchEnd,
  });
}

class SearchResult {
  final Note note;
  final SearchMatch match;
  final List<String> contextBefore;
  final List<String> contextAfter;

  const SearchResult({
    required this.note,
    required this.match,
    required this.contextBefore,
    required this.contextAfter,
  });
}
```

- [ ] **Step 2: SearchResult 테스트**

`desktop/test/search/search_result_test.dart`:
- SearchMatch 필드 접근 테스트
- SearchResult 필드 접근 테스트

Run: `cd desktop && flutter test test/search/search_result_test.dart -v`
Expected: PASS

- [ ] **Step 3: NoteSearchIndex에 searchWithContext 추가**

`note_search_index.dart`에 `import 'search_result.dart';`를 추가하고 `searchWithContext` 메서드를 추가한다:

```dart
List<SearchResult> searchWithContext(NoteSearchQuery query, {int contextLines = 3}) {
  final normalizedText = _normalize(query.text);
  // ... 기존 filter 로직 동일 ...
  // text가 있으면: content를 줄 단위로 순회하며 첫 매칭 라인 + context 추출
  // text가 없으면: 첫 줄을 match로 사용
}
```

- content를 `\n`으로 split
- 각 줄에서 `normalizedLine.contains(normalizedText)` 확인
- 첫 매칭 줄의 lineNumber, matchStart, matchEnd 기록
- `contextBefore`: max(0, lineNumber - contextLines) ~ lineNumber
- `contextAfter`: lineNumber+1 ~ min(lines.length, lineNumber + contextLines + 1)
- text 쿼리가 없으면 (tag/date 필터만) 첫 줄을 match로 사용

- [ ] **Step 4: searchWithContext 테스트**

`desktop/test/search/note_search_index_test.dart`에 테스트 추가:
- content 내 keyword 위치에 따른 contextBefore/contextAfter 길이
- contextLines=2일 때 범위가 줄어드는지
- 첫 줄/마지막 줄 매칭 시 context가 잘리는지
- text 없이 tag 필터만 사용 시 첫 줄이 match인지

Run: `cd desktop && flutter test test/search/note_search_index_test.dart -v`
Expected: PASS

- [ ] **Step 5: 전체 테스트 + analyze**

Run: `cd desktop && flutter analyze && flutter test`
Expected: 모두 통과

- [ ] **Step 6: Commit**

```bash
git add desktop/lib/search/search_result.dart desktop/lib/search/note_search_index.dart \
  desktop/test/search/
git commit -m "feat: add SearchResult model with context lines and searchWithContext method"
```

---

### Task 6: 검색 UI 재설계

검색창을 상단 중앙으로 옮기고, 결과를 에디터 좌측 1/3에 리스트로 보여준다. 매칭 키워드를 하이라이트하고, 결과 클릭 시 해당 노트를 에디터에 로드한다.

**Files:**
- Create: `desktop/lib/widgets/search_results_panel.dart`
- Modify: `desktop/lib/screens/document_screen.dart`
- Modify: `desktop/lib/widgets/note_search_section.dart`
- Modify: `desktop/test/screens/document_screen_test.dart`

- [ ] **Step 1: NoteSearchSection을 title bar 용으로 리팩토링**

기존 사이드바용 `NoteSearchSection`을 간결한 검색 입력 위젯으로 변환한다:
- filter chip, filter 버튼 등 사이드바 전용 요소 제거 (filter dialog는 별도 진입점으로 유지)
- 검색 입력 + clear 버튼만 남긴 compact 형태로 변환
- max width 400px, 중앙 정렬에 적합한 구조

- [ ] **Step 2: SearchResultsPanel 위젯 생성**

`desktop/lib/widgets/search_results_panel.dart`:

- 각 SearchResult를 카드로 표시
- 카드 구조:
  - 노트 제목 + 날짜 (상단)
  - context lines (중앙): contextBefore + matchedLine + contextAfter
  - matchedLine에서 keyword 부분을 accent color로 하이라이트
  - context lines는 monospace, 줄번호 표시
- `onResultTap(SearchResult)` callback
- Empty state: "No results found"

- [ ] **Step 3: DocumentScreen에서 검색 UI 재배치**

`document_screen.dart`의 `build` 메서드에서:

**검색창 위치 변경:**
- 사이드바의 `NoteSearchSection` 호출 제거
- `_buildTitleBar`에서 SimSync 로고와 settings 사이 `Spacer` 영역에 리팩토링된 검색 입력 위젯을 배치

**결과 패널 추가:**
- `_buildRightPanel`에서 `_isSearchActive`이면:
  - `Row` 안에 왼쪽 1/3은 `SearchResultsPanel`, 오른쪽 2/3은 `EditorPanel`
  - 중간에 `_ResizeHandle`과 동일한 divider
- 검색 비활성 시 기존 레이아웃 유지

**상태 변경:**
- `_searchResults`를 `List<SearchResult>`로 변경
- `_applySearchQuery`에서 `searchWithContext` 사용
- context lines 수는 `settingsController.value.searchContextLines`에서 가져옴

- [ ] **Step 4: Cmd+Shift+F 단축키 추가**

`document_screen.dart`의 `_handleHardwareKeyEvent`에서:
- `Cmd + Shift + F` 감지 시 검색 모드 활성화 + 검색 입력에 포커스
- FocusNode를 검색 TextField에 연결

단축키 설정의 defaultBindings에도 search 항목 추가 (Task 4에서 이미 추가됨. Task 4 시점에서는 동작 미구현 상태로 바인딩만 정의된다).

- [ ] **Step 5: Settings에 searchContextLines 컨트롤 추가**

`settings_screen.dart`의 Editor & Preview pane에:
- "Search context lines" 카드 추가
- 현재 값 표시 + stepper (+/-) 버튼
- min 1, max 10

- [ ] **Step 6: 결과 클릭 시 에디터 이동**

`_onSearchResultTap(SearchResult result)`:
- `_selectedNote`를 result.note로 설정
- `_selectedDate`를 note.noteDate로 설정
- 검색 모드를 유지하면서 에디터에 해당 노트를 표시

- [ ] **Step 7: 검색 UI 테스트**

`desktop/test/screens/document_screen_test.dart`에:
- Cmd+Shift+F로 검색 모드 진입 확인
- 검색 결과가 좌측 패널에 나타나는지
- 결과 클릭 시 에디터가 해당 노트를 표시하는지

- [ ] **Step 8: 전체 테스트 + analyze + build**

Run: `cd desktop && flutter analyze && flutter test && flutter build macos`
Expected: 모두 통과/성공

- [ ] **Step 9: Commit**

```bash
git add desktop/lib/widgets/search_results_panel.dart desktop/lib/screens/document_screen.dart \
  desktop/lib/widgets/note_search_section.dart desktop/lib/screens/settings_screen.dart \
  desktop/test/
git commit -m "feat: redesign search UI with top-center bar, results panel, and keyword highlight"
```

---

## Execution Order

1. Task 1 → Task 2 → Task 3 (버그 수정, 순서 의존성 낮음)
2. Task 4 (단축키 설정 — Task 5, 6과 독립적)
3. Task 5 → Task 6 (검색 모델 먼저, UI가 모델에 의존)

Task 2, 3은 모두 document_screen.dart를 수정하므로 순차 실행 권장. Task 4는 독립. Task 5 → 6은 순차.

## Verification

모든 Task 완료 후:

```bash
cd desktop
flutter analyze
flutter test
flutter build macos
```
