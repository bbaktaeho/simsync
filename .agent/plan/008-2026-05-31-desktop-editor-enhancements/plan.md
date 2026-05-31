---
title: Desktop Editor Enhancements
description: 데스크톱 마크다운 에디터 개선 — (1) 좌측 편집 + 우측 실시간 프리뷰 분할 모드, (2) 리스트 자동 연속(Enter)/번호 재정렬/테이블 삽입.
type: plan
created: 2026-05-31
status: active
related:
  - .agent/plan/007-2026-05-31-mobile-memo-tab/plan.md
---

# Desktop Editor Enhancements Implementation Plan

> **Goal:** 데스크톱 에디터에서 작성과 동시에 우측에 실시간 프리뷰를 보고, 리스트/테이블 작성을 더 편리하게 한다.
>
> **Architecture:** `EditorPanel`의 단일 `_showPreview` 토글을 3-상태 뷰 모드(`edit | split | preview`)로 확장한다. split 모드는 좌측 에디터 + 우측 `ValueListenableBuilder` 기반 실시간 프리뷰. 리스트/테이블 편의 기능의 텍스트 변환 로직은 순수 함수로 분리(`services/markdown_editing.dart`)해 단위 테스트한다.
>
> **Tech Stack:** Flutter (Dart), `flutter_markdown`(0.7.7+1, gitHubFlavored 기본 → 테이블 렌더 지원), `TextInputFormatter`, `flutter_test`.

---

## Problem

데스크톱 에디터(`desktop/lib/widgets/editor_panel.dart`)는:
- 프리뷰가 `_showPreview` 토글로 **편집 XOR 프리뷰** 배타 전환만 가능. 작성과 동시에 프리뷰 변화를 볼 수 없다.
- 리스트 작성 시 Enter로 다음 마커가 자동으로 나오지 않고, 번호 재정렬·테이블 삽입 편의 기능이 없다. (데스크톱 툴바는 제목 입력 + 프리뷰 토글뿐 — 모바일 같은 마크다운 툴바 없음.)

## Confirmed Decisions

플랫폼: **데스크톱만** (모바일 out of scope).

| 항목 | 결정 |
|------|------|
| 뷰 모드 | 툴바 3-상태 세그먼트 `Edit \| Split \| Preview`. 기본 **Split** |
| split 레이아웃 | `Row(crossAxisAlignment: stretch)` → `Expanded(editor)` + `VerticalDivider` + `Expanded(preview)`, 1:1 고정 |
| 실시간 갱신 | 우측 프리뷰를 `ValueListenableBuilder<TextEditingValue>(valueListenable: _contentController)`로 연결. 디바운스 없이 즉시. 에디터 TextField는 리빌드 안 함 |
| 검색 활성 시 | `DocumentScreen`이 `allowSplit: !_isSearchActive` 전달. split 비허용 시 effective=edit, 세그먼트에서 Split 숨김 (3열 과밀 회피) |
| 리스트 자동 연속 (a) | content `TextField`에 `MarkdownListInputFormatter` 부착. `-`,`*`,`+`,`1.`/`1)`,`- [ ]` 줄에서 Enter → 다음 마커 자동(번호 +1). 빈 마커에서 Enter → 마커 제거(리스트 탈출) |
| 번호 재정렬 (b1) | 툴바 "Renumber list" 액션. 커서가 속한 순서 리스트 블록을 같은 indent 기준 연속 재번호(첫 항목 번호 기준 +1) |
| 테이블 삽입 (c1) | 툴바 "Insert table" 액션 → 행×열 선택 다이얼로그 → GFM 스켈레톤 삽입 |
| 로직 분리 | 텍스트 변환은 `services/markdown_editing.dart` 순수 함수. 위젯은 thin wiring |
| UI 라벨 | 기존 데스크톱 영어 라벨에 맞춤 (`Edit/Split/Preview`, tooltip `Insert table`/`Renumber list`) |
| 뷰 모드 영속화 | 세션 내 유지(현 `_showPreview`처럼). 앱 재시작 간 저장 out of scope |

## Files Affected

### 새 파일
- `desktop/lib/services/markdown_editing.dart` — 순수 로직
  - `class MarkdownListInputFormatter extends TextInputFormatter` — Enter 시 리스트 연속/탈출
  - `TextEditingValue renumberOrderedListAtCursor(TextEditingValue value)` — 커서 블록 재번호
  - `String buildMarkdownTable({required int columns, required int rows})` — GFM 스켈레톤
- `desktop/test/services/markdown_editing_test.dart` — 단위 테스트
- `desktop/test/widgets/editor_panel_view_mode_test.dart` — 위젯 테스트

### 수정
- `desktop/lib/widgets/editor_panel.dart`
  - `enum EditorViewMode { edit, split, preview }` (파일 상단)
  - `bool _showPreview` → `EditorViewMode _viewMode = EditorViewMode.split`
  - `EditorPanel`에 `final bool allowSplit;` (기본 true) 추가
  - `build()`의 `Expanded(child: _showPreview ? _buildPreview : _buildEditor)` → `Expanded(child: _buildBody(c))` (effectiveMode 분기: edit/preview/split)
  - 신규 `_buildLivePreview(c)` (`ValueListenableBuilder`), `_buildPreviewSurface(c, text)` (기존 `_buildPreview`와 공유)
  - `_buildEditor`의 content `TextField`에 `inputFormatters: widget.isReadOnly ? null : [MarkdownListInputFormatter()]`
  - `_buildToolbar`: 제목 입력 우측에 `Insert table` / `Renumber list` 액션 버튼 + `_ViewModeControl`(3-상태, allowSplit 반영). 기존 단일 `_ToggleButton` 대체
  - 신규 `_insertTable()`(다이얼로그), `_insertBlock(String)`, `_renumberList()`
  - 신규 위젯 `_ViewModeControl`, `_ToolbarIconButton`
- `desktop/lib/screens/document_screen.dart`
  - `_buildRightPanel`의 `EditorPanel(...)` 생성에 `allowSplit: !_isSearchActive` 추가 (유일한 변경)

### 변경 없음 (확인됨)
- `desktop/lib/widgets/markdown_preview.dart` — `Markdown` + gitHubFlavored 기본으로 테이블 렌더 지원, 변경 불필요
- `desktop/lib/models/note.dart`, storage/* — 무관

## Behavior

### 기능 1 — 실시간 분할 프리뷰
- 기본 진입 시 Split: 좌측 편집, 우측 프리뷰. 타이핑하면 우측만 즉시 갱신.
- 툴바 `Edit`/`Split`/`Preview`로 전환. Edit=에디터만, Preview=프리뷰만(정적), Split=둘 다.
- 검색 활성 시 Split 세그먼트 숨김, edit로 후퇴.

### 기능 2 — 에디터 편의
- (a) `- item` 줄 끝에서 Enter → `- ` 자동. `1. item`→`2. `. `- [ ] item`→`- [ ] `. 빈 마커(`- `/`1. `/`- [ ] `)에서 Enter → 마커 제거 후 빈 줄.
- (b1) 커서가 `2. ...` 같은 순서 리스트에 있을 때 Renumber → 같은 indent의 연속 블록을 1..n(첫 항목 번호 기준)으로 재번호.
- (c1) Insert table → 열/행 선택 → 커서 위치(줄 시작 보정)에 GFM 테이블 삽입, 프리뷰에 즉시 렌더.

## markdown_editing.dart 로직 사양

### MarkdownListInputFormatter
`formatEditUpdate(old, new)`:
1. `old.selection`이 collapsed가 아니거나, `new`가 "커서 위치에 `\n` 하나 삽입"이 아니면 그대로 반환(passthrough). 판정: `new.text == old.text[0:c] + '\n' + old.text[c:]` && `new.selection`이 `c+1`에 collapsed.
2. old에서 커서 줄(`lineStart..lineEnd`) 추출 → 마커 매칭(task → ordered → bullet 순).
   - task: `^(\s*)([-*+]) +\[([ xX])\] +(.*)$`
   - ordered: `^(\s*)(\d+)([.)]) +(.*)$`
   - bullet: `^(\s*)([-*+]) +(.*)$`
3. 매칭 없음 → passthrough(일반 줄바꿈).
4. body(마커 뒤 내용) `trim().isEmpty` → **탈출**: 해당 줄의 마커 제거(`old[0:lineStart] + old[lineEnd:]`), 커서 `lineStart`.
5. 그 외 → **연속**: `old[0:c] + '\n' + continuation + old[c:]`, 커서 `c+1+continuation.length`.
   - continuation: ordered=`indent + (num+1) + delim + ' '`, task=`indent + bullet + ' [ ] '`, bullet=`indent + bullet + ' '`.

### renumberOrderedListAtCursor(value)
- 커서 줄이 ordered(`^(\s*)(\d+)([.)])(\s.*)$`) 아니면 그대로 반환(no-op).
- 같은 indent의 ordered 줄을 커서 위·아래로 확장해 블록 경계 결정(비-ordered/다른 indent에서 정지).
- base = 블록 첫 줄 번호. 각 줄 `indent + (base + offset) + delim + spaceAndBody`로 치환.
- 커서: 같은 줄·같은 column(클램프) 유지.

### buildMarkdownTable({columns, rows})
- columns≥1, rows≥0 클램프.
- header `| Column 1 | Column 2 |`, separator `| --- | --- |`, 빈 데이터 행 `|  |  |` × rows. `\n` join.

## Test Strategy (코드 기반, 에뮬레이터 미사용)

### 단위 `desktop/test/services/markdown_editing_test.dart`
formatter (helper로 old/new `TextEditingValue` 구성 → `formatEditUpdate` 호출):
1. bullet 연속: `- a`(끝 Enter) → `- a\n- `
2. ordered 증가: `1. a` → `1. a\n2. `
3. `)` delimiter: `1) a` → `1) a\n2) `
4. task 연속: `- [ ] a` → `- [ ] a\n- [ ] `
5. 빈 bullet 탈출: `- `(끝 Enter) → `` (마커 제거)
6. 빈 ordered 탈출: `1. ` → ``
7. 비-리스트 passthrough: `hello` → `hello\n` 그대로
8. 멀티문자 변경 passthrough: old→new가 단일 `\n` 삽입이 아니면 그대로
9. mid-line split: `- helloworld`에서 커서 중간 Enter → `- hello\n- world`
10. indent 유지: `  - a` → `  - a\n  - `

renumber:
11. `1. a\n3. b\n4. c` (커서 2번째 줄) → `1. a\n2. b\n3. c`
12. base 보존: `3. a\n9. b` → `3. a\n4. b`
13. indent/delim/스페이싱 보존: `  2)  x\n  5)  y` → `  1)  x\n  2)  y`
14. 비-ordered 커서 → no-op
15. 블록 경계: `1. a\n\n5. b`에서 커서 1줄 → `1. a`만 (빈 줄에서 정지)

table:
16. `buildMarkdownTable(columns:2, rows:2)` 정확 문자열
17. `columns:3, rows:0` → header+separator만
18. 클램프: `columns:0` → 1열

### 위젯 `desktop/test/widgets/editor_panel_view_mode_test.dart`
(`MaterialApp(theme: buildLightTheme(), home: Scaffold(body: SizedBox(height:600, width:1000, child: EditorPanel(note:...))))`)
19. 기본 Split: content `TextField` 존재 && `MarkdownPreviewWidget` findsOneWidget
20. Edit 전환: `MarkdownPreviewWidget` findsNothing, content TextField 존재
21. Preview 전환: content TextField findsNothing(에디터 숨김), `MarkdownPreviewWidget` 존재
22. 실시간 갱신: split에서 content에 enterText → `tester.widget<MarkdownPreviewWidget>(...).content`가 입력값과 일치
23. `allowSplit:false`: 기본 split이 edit로 후퇴(`MarkdownPreviewWidget` findsNothing) && `find.text('Split')` findsNothing
24. 테이블 삽입: `Insert table` 버튼 탭 → 다이얼로그 → `Insert` 탭 → `find.text('Column 1')` findsWidgets(프리뷰 렌더)

### 추가 검증
- `cd desktop && flutter analyze` clean
- `cd desktop && flutter test` 전체 통과 (기존 101 회귀 없음)
- mobile 무변경 — 회귀 확인용 `cd mobile && flutter test` 1회

## TDD 순서 (bite-sized)

1. `markdown_editing_test.dart` 케이스 16~18(table) 작성 → 실패 → `buildMarkdownTable` 구현 → 통과.
2. 케이스 1~10(formatter) 작성 → 실패 → `MarkdownListInputFormatter` 구현 → 통과.
3. 케이스 11~15(renumber) 작성 → 실패 → `renumberOrderedListAtCursor` 구현 → 통과.
4. `editor_panel.dart`: `EditorViewMode` + `_viewMode`(split 기본) + `allowSplit` + `_buildBody`/`_buildLivePreview` + `_ViewModeControl`. 케이스 19~23 작성 → 통과.
5. content TextField에 formatter 부착 + 툴바 액션 버튼/`_insertTable`/`_insertBlock`/`_renumberList`. 케이스 24 작성 → 통과.
6. `document_screen.dart`에 `allowSplit: !_isSearchActive` 추가.
7. `flutter analyze` + `flutter test`(desktop) → 통과, mobile 회귀 확인.
8. 개발 일지 작성.
9. 커밋 → push → PR(develop 대상).

## Out of Scope

- 모바일 변경.
- 실시간 자동 번호 재정렬(b2), 테이블 인라인 편집(c2).
- split 비율 드래그 리사이즈, 에디터↔프리뷰 스크롤 동기화.
- 뷰 모드 앱 재시작 영속화.
- 데스크톱 전체 마크다운 툴바(B/I/H 등) 추가 — 이번엔 table/renumber 액션만.

## Branch / Workflow

- Base: 최신 `develop`(`ada3a58`, PR #25 머지 후).
- Branch: `feature/desktop-editor-enhancements`.
- 단일 PR (develop 대상). "PR까지" — 머지는 하지 않음.
- 개발 일지: `.agent/develop/daily/2026-05-31-desktop-editor-enhancements.md`.

## Checklist

- [ ] `buildMarkdownTable` (TDD)
- [ ] `MarkdownListInputFormatter` (TDD)
- [ ] `renumberOrderedListAtCursor` (TDD)
- [ ] `EditorViewMode` + split 기본 + `allowSplit` + 실시간 프리뷰
- [ ] formatter 부착 + table/renumber 툴바 액션
- [ ] `document_screen.dart` `allowSplit` 전달
- [ ] 위젯 테스트 19~24
- [ ] desktop `flutter analyze` clean
- [ ] desktop `flutter test` 통과, mobile 회귀 없음
- [ ] 개발 일지
- [ ] PR (develop 대상)
