---
title: Desktop Editor Enhancements
description: 데스크톱 에디터에 실시간 분할 프리뷰(편집/분할/프리뷰 3-상태) + 리스트 자동 연속(Enter)/번호 재정렬/테이블 삽입 추가.
type: develop
created: 2026-05-31
status: active
related:
  - .agent/plan/008-2026-05-31-desktop-editor-enhancements/plan.md
---

# Desktop Editor Enhancements — 개발 일지

## 배경

데스크톱 에디터는 `_showPreview` 토글로 편집 XOR 프리뷰만 가능했고, 리스트/테이블 작성 편의 기능이 없었다. 사용자 요청: (1) 작성과 동시에 우측 실시간 프리뷰, (2) 리스트 자동 연속/번호 재정렬/테이블 삽입. 플랫폼은 데스크톱만(모바일 out of scope).

## 구현 개요

### 순수 로직 분리 — `desktop/lib/services/markdown_editing.dart` (신규)
위젯과 분리해 단위 테스트 가능하게 작성:
- `MarkdownListInputFormatter extends TextInputFormatter`: "커서에 `\n` 하나 삽입"인 경우에만 작동. 리스트 줄에서 다음 마커 자동(ordered는 +1, task는 `- [ ] `), 빈 마커에서는 마커 제거(리스트 탈출). 그 외는 passthrough.
- `renumberOrderedListAtCursor(TextEditingValue)`: 커서가 속한 ordered 블록(같은 indent 연속)을 첫 항목 번호 기준으로 재번호. ordered가 아니면 no-op. indent/delimiter/스페이싱·커서 column 보존.
- `buildMarkdownTable({columns, rows})`: GFM 스켈레톤 문자열.

### 에디터 와이어링 — `desktop/lib/widgets/editor_panel.dart`
- `enum EditorViewMode { edit, split, preview }`, `bool _showPreview` → `EditorViewMode _viewMode = split`(기본).
- `EditorPanel.allowSplit`(기본 true) 추가. split && !allowSplit → effective edit.
- `_buildBody`: edit=에디터, preview=프리뷰, split=`Row(stretch)[Expanded(editor) | VerticalDivider | Expanded(livePreview)]` 1:1.
- `_buildLivePreview`: `ValueListenableBuilder<TextEditingValue>(_contentController)` → 타이핑 시 우측만 리빌드(에디터 TextField 무리빌드). 디바운스 없음.
- content `TextField`에 `inputFormatters: [MarkdownListInputFormatter()]`(읽기전용 제외).
- 툴바: 단일 `_ToggleButton` 제거 → `Insert table`/`Renumber list` 아이콘 버튼(읽기전용 시 숨김) + `_ViewModeControl`(3-상태 세그먼트, allowSplit 반영).
- `_insertTable`(행×열 다이얼로그 `_InsertTableDialog`) / `_insertBlock`(줄 시작 보정 삽입) / `_renumberList`.

### 검색 정합성 — `desktop/lib/screens/document_screen.dart`
- `_buildRightPanel`에서 `EditorPanel(... allowSplit: !_isSearchActive)`. 검색 활성(좌측 결과 패널 + 에디터) 시 분할을 막아 3열 과밀 회피. (유일한 변경)

## 의식적으로 빠뜨린 것
- 실시간 자동 번호 재정렬(타이핑마다) — 입력 충돌/커서 점프 위험 → 명시적 액션(b1)만.
- 테이블 인라인 편집(행·열 추가/삭제, 정렬) — 큰 기능, 후속.
- split 비율 드래그 리사이즈, 에디터↔프리뷰 스크롤 동기화, 뷰 모드 앱 재시작 영속화.
- 모바일 변경.

## 막힌 지점 / 메모
- `flutter_markdown 0.7.7+1`은 `extensionSet` 기본값이 `gitHubFlavored`(widget.dart:398)라 테이블이 기본 렌더됨 → 프리뷰 변경 불필요.
- split 안 TextField(`expands:true`)는 bounded height가 필요 → `Row(crossAxisAlignment: stretch)`로 해결.
- 데스크톱 프리뷰(`MarkdownPreviewWidget`)는 `content`만 받고 title을 렌더하지 않아, split 기본값으로 바꿔도 기존 `document_screen_test`(title 텍스트 검증) 회귀 없음.

## 검증 (코드 기반, 에뮬레이터 미사용)
- `desktop flutter analyze`: No issues found
- `desktop flutter test`: 125/125 통과 (기존 101 + 신규 24)
  - 단위 `test/services/markdown_editing_test.dart` 18: formatter(연속/탈출/passthrough/indent/mid-line) + renumber(블록/base/경계/no-op) + table(2x2/0행/클램프)
  - 위젯 `test/widgets/editor_panel_view_mode_test.dart` 6: 기본 split, Edit/Preview 전환, 실시간 갱신, allowSplit=false 후퇴, 테이블 삽입 렌더
- `mobile flutter test`: 12/12 통과 (모바일 무변경, 회귀 확인)

## 결정 로그

| 결정 | 근거 |
|------|------|
| 3-상태 세그먼트, split 기본 | 기존 이진 토글 자연 확장 + "작성과 동시에 보기" 요청에 직접 부합 |
| 실시간 갱신 = ValueListenableBuilder | 에디터 TextField 무리빌드, 커서/성능 안전 |
| 검색 중 allowSplit=false | 좌측 결과 패널과 3열 과밀 회피 |
| 로직을 services로 분리 | 위젯 없이 순수 단위 테스트 |
| 자동 연속은 formatter | enterText로 위젯테스트 어려워 formatter `formatEditUpdate`를 직접 단위 테스트 |
| 번호 재정렬은 명시적 액션 | 실시간 자동(b2)의 입력 충돌 위험 회피 (MVP) |
