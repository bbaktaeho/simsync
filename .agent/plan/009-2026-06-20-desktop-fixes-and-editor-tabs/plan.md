---
title: Desktop 버그 수정 및 에디터 탭
description: 코드블록 크래시/캘린더 에러/검색 UI/메모 날짜 버그 수정 + Claude Code 위클리 연동 + 에디터 멀티탭
type: plan
created: 2026-06-20
status: active
related:
  - .agent/plan/008-2026-05-31-desktop-editor-enhancements/plan.md
---

# Desktop 버그 수정 및 에디터 탭

데스크톱(`desktop/`) 한정. 버그 4건 + 기능 2건.

## Confirmed requirements (사용자 요청)

1. **코드블록 렌더링 크래시** — 마크다운 ``` 코드가 렌더링 실패. 실패하지 않게 수정.
2. **캘린더 날짜 클릭 시 split + 빨간 에러** — 다른 날짜 클릭 후 파일을 읽을 때 간헐적으로 split + 빨간 에러 화면. 둘 다 수정.
3. **검색창/필터 버튼 크기 불일치** — 시각적 크기 통일.
4. **메모→daily 날짜 보존** — 메모를 보다 daily로 돌아오면 메모 클릭 전 보던 날짜로 복귀해야 함 (예: 06-20 → 메모(05-01) → daily → 06-20).
5. **Claude Code 연동 + 위클리 지침 설정** — 설정에 "위클리 지침 설정"(Claude 연동 포함). Weekly 버튼 클릭 시 Claude Code로 금주 작업 정리.
6. **에디터 탭** — 여러 파일을 탭으로. 타이틀 `날짜:파일이름`, 최대 10개, 반응형 축약. 모든 탭 닫으면 파일 생성 초기 화면.

## Root cause (조사 완료)

- **#1/#2 빨간 에러 (동일 원인)**: `markdown_preview.dart`의 코드 하이라이트 빌더가 `'pre'` 키로 등록됨. flutter_markdown은 `pre` 블록 텍스트를 `MarkdownElementBuilder.visitText`(기본 null 반환)로 보내 부모 inline이 자식을 못 받고, `_addAnonymousBlockIfNeeded`가 자식 없는 inline을 비우지 않아 `assert(_inlines.isEmpty)` 실패 → 모든 코드블록에서 크래시. split 기본 모드의 프리뷰 pane에서 이 크래시가 빨간 에러로 표시됨(코드블록 있는 노트만 → "간헐적").
- **#4**: `_onNoteSelected`가 메모 클릭 시에도 `_selectedDate`를 메모 날짜로 변경.

## Decisions

### #1/#2 (수정 완료)
- 빌더를 `'code'` 키로 등록. 인라인 코드(개행 없음 + language class 없음)는 null 반환해 기본 `code` 스타일 유지. 블록 코드만 하이라이팅. `class="language-xx"`에서 실제 언어 추출(기존엔 pre에 class가 없어 항상 plaintext였음). 박스는 stylesheet `codeblockDecoration` 단일 적용.
- split 자체는 의도된 기능(008)이므로 유지. 크래시 제거로 "빨간 에러"와 "에러로 깨져 보이던 split" 모두 해소. 앱 실행으로 시각 확인.

### #3 (수정 완료)
- `note_search_section.dart`: 검색창·필터 버튼 공유 높이 상수(32), radius 통일(`radiusStandard`), 아이콘 16px 통일.

### #4 (수정 완료)
- `_onNoteSelected`에서 `note.isMemo`면 `_selectedDate`를 변경하지 않음.

### #5 Claude Code 연동 (proposed)
- 연동 방식: Claude Code **headless CLI** (`claude -p` / `--print`). 검증: 설치된 `claude --help` + 공식 문서. notes를 stdin으로 파이프, stdout(text) 수신.
- 신규 `services/claude_code_service.dart`: `Process.start`로 `claude --print --output-format text [--model ...]` 실행, prompt(지침+금주 notes) stdin 전달, stdout 반환. 가용성 체크(`claude --version`). macOS GUI PATH 이슈 대비 CLI 경로 설정 제공.
- 설정: `AppSettings`에 `weeklyInstruction`(String), `claudeCodeEnabled`(bool), `claudeCliPath`(String) 추가 + 컨트롤러 setter/persistence. 설정 화면에 "Weekly" pane 신설(지침 textarea + Claude 연동 토글 + CLI 경로).
- Weekly 버튼: 기존 `WeeklyViewPanel`(주간 저널) 유지 + 상단에 "이번 주 요약 생성"(Claude) 액션. 클릭 = 명시적 동의(CLAUDE.md). 결과는 패널에 표시(원본 노트와 분리, 저장 안 함).

### #6 에디터 탭 (구현 완료)
- `_openTabIds: List<String>`(열린 탭, 최대 10) + `_selectedNote`(활성 탭). 탭 Note는 `_allNotes`에서 id로 resolve(staleness 방지).
- 노트 열기(`_openNote`): 이미 열림→활성화 / 미만→추가+활성화 / 10개 초과→활성 탭 교체.
- 닫기: 활성 탭 닫으면 인접 탭 활성화. 전부 닫으면 `_selectedNote=null` → 생성 초기 화면.
- 탭 여는 경로: 노트 리스트 클릭/검색 결과/주간 노트/노트 생성. **날짜 클릭은 그 날짜의 기본 노트를 탭으로 오픈**(date-oriented 핵심 흐름 유지; 기존 탭은 유지, 재방문 시 기존 탭 재활성화). daily↔memo 필터 전환과 검색 입력은 탭을 자동으로 열지 않음(탭 spam 방지). 최초 로드 시 해당 날짜 기본 노트 1개 자동 오픈.
- 탭 바: 에디터 상단. 타이틀 `yyyy-MM-dd:제목`, 활성 강조, 개별 close. 반응형: 폭에 따라 날짜 축약(`yyyy-MM-dd`→`MM-dd`→날짜 생략) + ellipsis, 전체 라벨 tooltip.

> 결정 변경: 초안의 "날짜 클릭은 탭을 열지 않음"을 **Option B**(날짜 클릭→그 날 기본 노트 오픈)로 변경. SimSync는 date-oriented 앱이라 날짜 클릭→당일 노트 한 번에 보기가 핵심 흐름이며, 탭이 유지되므로 "날짜 안 눌러도 보기" 요구도 충족.

### 검증 중 발견·수정한 잠재 버그
- **더티 탭 닫기 시 크래시**: 더티 노트에서 전환(탭 닫기/전환) 시 `EditorPanel.didUpdateWidget`의 flush가 빌드 도중 부모 `_onNoteChanged`의 setState를 호출 → `setState during build`. 기존 코드의 더티 노트 전환에도 잠재하던 버그. 수정: `_flushPending`이 컨트롤러 텍스트는 동기 스냅샷하되 `onNoteChanged` 호출은 `addPostFrameCallback`으로 defer. 추가로 `_onNoteChanged`는 비활성 노트의 deferred flush가 활성 선택을 가로채지 않도록 가드(`_selectedNote?.id == updatedNote.id`).

## Out of scope
- mobile, 백엔드, AI 요약 영구 저장, split 기본값 변경.

## Verification
- 각 변경에 단위/위젯 테스트. `flutter test` 전체 + `flutter analyze` clean. 실제 macOS 앱 실행으로 시각 검증. 5회 검증(목적/버그/품질/통합/사용자흐름).
