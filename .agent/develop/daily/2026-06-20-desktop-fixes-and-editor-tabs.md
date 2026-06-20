---
title: Desktop 버그 수정 및 에디터 탭 개발 일지
description: 코드블록 크래시/검색 UI/메모 날짜 버그 수정 + Claude Code 위클리 연동 + 에디터 멀티탭 구현
type: develop
created: 2026-06-20
related:
  - .agent/plan/009-2026-06-20-desktop-fixes-and-editor-tabs/plan.md
---

# Desktop 버그 수정 및 에디터 탭

## 작업 범위 (desktop only)

버그 4건 + 기능 2건.

## 버그 수정

### 1. 마크다운 코드블록 렌더링 크래시
- 근본 원인: `markdown_preview.dart`의 syntax-highlight 빌더가 `'pre'` 키로 등록됨. flutter_markdown은 `pre` 블록의 텍스트를 `MarkdownElementBuilder.visitText`(기본 null 반환)로 보내, 지연 생성된 부모 inline이 자식을 못 받고 `_addAnonymousBlockIfNeeded`가 비우지 않아 최종 `assert(_inlines.isEmpty)` 실패 → 코드블록 있는 모든 노트에서 크래시.
- 수정: 빌더를 `'code'` 키로 이동. 인라인 코드(개행 없음 + language class 없음)는 null 반환해 기본 스타일 유지, 블록 코드만 하이라이팅. `class="language-xx"`에서 실제 언어를 읽어 처음으로 진짜 하이라이팅 동작.
- 테스트: `test/widgets/markdown_preview_test.dart` (fenced/no-lang/unknown/indented/inline/mixed 6 케이스, 예외 없음).

### 2. 캘린더 날짜 클릭 시 split + 빨간 에러
- 빨간 에러 = #1과 동일 크래시(split 기본 모드의 프리뷰 pane에서 표출). #1 수정으로 해소. split은 008에서 도입한 의도된 기능이라 유지.

### 3. 검색창/필터 버튼 크기 불일치
- `note_search_section.dart`: 공유 높이 상수(`_controlHeight=32`), radius 통일(`radiusStandard`), 아이콘 16px 통일, `CrossAxisAlignment.center`.

### 4. 메모→daily 날짜 보존
- `_onNoteSelected`/`_onSearchResultTap`/`_onWeeklyNoteTap`에서 `note.isMemo`면 `_selectedDate` 미변경. 메모는 날짜 독립이므로 daily 복귀 시 이전 날짜 유지.
- 테스트: `document_screen_test.dart` "returning to daily after opening a memo keeps the original date".

## 기능 추가

### 5. Claude Code 연동 + 위클리 지침 설정
- 연동: Claude Code headless CLI. 검증은 설치된 `claude --help` + 공식 문서(`cat notes | claude -p "<지침>"` 패턴). 지침을 positional, 금주 노트를 stdin으로 전달, stdout(text) 수신.
- `services/claude_code_service.dart`: `Process.start` 기반, runner 주입 가능(테스트). 가용성 체크, 타임아웃, 친절한 에러. macOS GUI PATH 이슈 대비 CLI 경로 설정.
- `AppSettings`에 `weeklyInstruction`/`claudeCodeEnabled`/`claudeCliPath` 추가 + 컨트롤러 setter/persistence. 설정에 "Weekly" pane 신설(지침 textarea + 연동 토글 + 경로 + Test).
- `WeeklyViewPanel` 상단에 요약 카드. "Generate" 클릭 = 명시적 동의(CLAUDE.md). 결과는 패널에만 표시(원본 노트와 분리, 저장 안 함).
- 테스트: `claude_code_service_test.dart`(8), 설정 pane/persistence 테스트.

### 6. 에디터 멀티탭
- `_openTabIds`(최대 10) + `_selectedNote`(활성). 탭 Note는 `_allNotes`에서 id로 resolve. `EditorTabBar` 위젯: 타이틀 `yyyy-MM-dd:파일이름`, 반응형 축약, 개별 close, tooltip.
- 날짜 클릭 → 그 날 기본 노트를 탭으로 오픈(date-oriented). 전부 닫으면 생성 초기 화면.
- 테스트: `editor_tab_bar_test.dart`(3), `document_screen_test.dart` 탭 열기/닫기/생성화면/더티탭 닫기.

## 검증 중 수정한 잠재 버그

- **더티 탭 닫기 크래시 (`setState during build`)**: 더티 노트 전환 시 `EditorPanel.didUpdateWidget` flush가 빌드 도중 부모 setState 호출. `_flushPending`을 post-frame defer로, `_onNoteChanged`는 비활성 노트 재선택 방지 가드 추가. 기존 코드에도 잠재하던 버그를 함께 해결.
- 독립 코드리뷰의 "코드블록 이중 패딩" 지적은 flutter_markdown 소스 확인 결과 빌더가 SCSV를 교체하므로 단일 패딩이 맞음(오인). `TapGestureRecognizer` 누수는 수정.

## 후속: Weekly 연동 견고화 (Anthropic API provider)

- 문제: Claude Code CLI 단독 연동이 macOS GUI(Finder 실행) PATH 미상속으로 동작하지 않음("죽는다").
- 해결: Weekly 연동에 **provider 선택**(Anthropic API / Claude Code CLI) 추가, API 기본.
  - `services/anthropic_api_service.dart`: `http`로 `POST /v1/messages` 직접 호출(`x-api-key` + `anthropic-version`). 지침=system, 노트=user. 기본 모델 `claude-opus-4-8`. validateKey는 무과금 `GET /v1/models`. 친절한 에러 매핑/타임아웃/refusal 처리.
  - `AppSettings`에 `weeklyProvider`/`anthropicApiKey`/`anthropicModel` + 컨트롤러 persistence.
  - 설정 Weekly pane: provider 칩 + 조건부 필드(API 키 obscure + 모델 / CLI 경로), Test 버튼(provider별 검증).
  - `ClaudeCodeService._resolveExecutable`: 경로 미설정 시 common 설치 위치 자동 탐색(GUI PATH 보완).
- 검증: 단위 테스트(API 10 + 컨트롤러/설정), **실제 plumbing** 확인 — 더미 키 `POST /v1/messages` → 401 `authentication_error`(요청 본문/헤더/엔드포인트 정상, 키만 거부). 유효 키면 200+요약.
- 참고: Claude.ai 구독은 API 직접 접근이 아님(별도 pay-as-you-go). 구독만 있으면 CLI provider 사용.

## 결과
- `flutter analyze` clean, `flutter test` 164 passed.
- 앱 빌드/실행 스모크 확인(런타임 예외 없음). 스크린샷은 환경 권한상 불가.
