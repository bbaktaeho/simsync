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

## 후속: 노션/옵시디언식 인라인 에디터 (프리뷰·split 제거)

- 요구: 에디터와 뷰를 함께(편집 중 인라인 렌더링), 마크다운 프리뷰/split 모두 제거, 가장 기본 기능부터.
- 방향(decision): 무거운 에디터 패키지 도입 없이 `TextEditingController.buildTextSpan` 오버라이드로 편집 중 인라인 스타일링(옵시디언 Live Preview 방식). 노트는 markdown source 유지(데이터 모델 일치), 의존성 0 추가.
  - `widgets/markdown_editing_controller.dart`: `MarkdownEditingController`. 라인 단위 파싱(heading/checkbox/bullet/ordered/quote + fenced code 추적) + 인라인 토큰(bold/italic/strike/inline code). 마커는 숨기지 않고 dim 처리.
  - **불변식**: span 텍스트 합 == `controller.text` (커서/선택 desync 방지). 마커를 제거하지 않고 스타일만 입혀 char-count 보존.
- `editor_panel.dart`: `EditorViewMode`(edit/split/preview) 및 `_ViewModeControl`/`_ViewModeSegment`/`_buildLivePreview`/`_buildPreviewSurface` 제거. body는 단일 인라인 에디터. 본문 폰트를 mono→proportional(`mdBody`)로 변경해 렌더 모습과 일치. 툴바에 기본 포맷 버튼(Bold/Italic/Heading/Bullet/Checklist) 추가, 기존 table/renumber 유지.
  - `_wrapSelection`(선택 래핑 + 이미 래핑 시 언랩), `_toggleLinePrefix`(블록 프리픽스 토글, 기존 블록 타입은 교체(checkbox→bullet 등), 들여쓰기·커서 보존).
- `document_screen.dart`: `EditorPanel.allowSplit` 제거. `markdown_preview.dart`는 weekly view에서 계속 사용하므로 유지(에디터 프리뷰만 제거).
- 검증(5회+): 컨트롤러 단위테스트(char 보존 16케이스 + 스타일 7) / `flutter analyze` clean / 인라인 위젯테스트 7 / 독립 적대적 코드리뷰(파싱 로직 50만 입력 퍼징 → char 불일치 0, 한글 IME 기능 정상[composing 밑줄만 누락], 커서수학·성능 양호) / 전체 스위트.
  - 리뷰 중 발견·수정: line-prefix 토글이 기존 블록 타입을 중첩(`- [ ] ` + Bullet → `[ ] ...`)하던 문제를 "정확히 같은 프리픽스일 때만 toggle-off, 아니면 교체"로 수정. Bold 언랩 추가.
- 한계: 편집 중 composing(한글 조합) 밑줄 affordance는 없음(기능은 정상). 인라인 nested 스타일(굵게 안의 기울임)은 MVP 범위 외.

## 결과
- `flutter analyze` clean, `flutter test` 172 passed.
- 앱 빌드/실행 스모크 확인(런타임 예외 없음). 스크린샷은 환경 권한상 불가.

## 후속: 설정 Claude Test 실패(node PATH) 수정

- 증상 보고: 설정에서 Claude Test 클릭 시 동작 불가("죽는다").
- 조사(systematic-debugging): Test 핸들러 `_probe`는 `isAvailable`/`validateKey`만 호출 — 둘 다 catch-all + 타임아웃이라 **Dart 레벨에선 하드 크래시 불가**. 크래시 리포트도 없음.
- **근본 원인(직접 재현 확인)**: `/opt/homebrew/bin/claude`는 `#!/usr/bin/env node` 스크립트. Finder 실행 GUI 앱의 최소 PATH(`/usr/bin:/bin:...`)엔 `node`(`/opt/homebrew/bin/node`)가 없어 `claude` 실행이 `env: node: No such file or directory`(exit 127)로 실패 → CLI provider가 Finder 실행 시 항상 "unavailable". `_resolveExecutable`은 claude 경로는 찾지만 인터프리터(node)는 PATH에서 못 찾는 중첩 문제.
- 수정: `ClaudeCodeService.buildPathEnv`(순수 함수, 테스트 가능)로 spawn 시 PATH 보강 — exe 자신의 디렉터리(보통 node 동거) + 공용 설치 경로 + 상속 PATH(중복 제거). `_defaultRunner`의 `Process.start`에 `environment: {PATH: ...}` 주입. 재현 검증: 보강 PATH로 `claude --version` → exit 0(이전 127).
- 방어: `_probe`에 try/catch 추가(어떤 예외도 앱을 죽이지 않고 "unavailable" 표시, defense-in-depth).
- 검증: `buildPathEnv` 단위테스트 3, `flutter analyze` clean, 전체 175 테스트 통과, macOS 디버그 빌드 + `open`(Finder형) 기동 스모크 정상.
- 미해결: 사용자가 보고한 게 "하드 크래시"라면 Dart 경로상 재현 불가 — fresh 빌드에서 증상/메시지 확인 필요(필요시 진단 로그 추가).

## 후속: 옵시디언식 Live Preview(활성/비활성 렌더) + 코드 하이라이팅

- 요구: 블록을 편집 중이 아니면 곧바로 마크다운 렌더링, 커서를 대면 렌더 모양 유지한 채 편집(옵시디언). 코드블록 다국어 컬러 하이라이팅.
- 기술 제약(decision): Flutter TextField는 표시 텍스트 == 컨트롤러 텍스트여야 커서 매핑이 유지됨(문자를 진짜 숨기면 깨짐). 그래서 **문자는 보존하되 비활성 라인의 마커를 `fontSize 0.1 + transparent`로 collapse**(시각적으로 사라지나 커서/선택 매핑은 그대로). 활성 라인(커서/선택이 닿은 라인)만 마커 표시(dim). focus 해제 시 전체 렌더.
  - `MarkdownEditingController`: `focused` 필드 + selection으로 라인별 active 판정(`selStart <= lineEnd && selEnd >= lineStart`, offset += line.length+1). 활성→마커 dim, 비활성→collapse. 구조 마커(list/quote/checkbox)는 비활성에도 유지(구조 전달).
  - live 갱신: EditableText가 selection 변경에도 `setState` 무조건 호출 → buildTextSpan 재실행(SDK 소스로 확인). `editor_panel`은 FocusNode 리스너로 `controller.focused` 설정 + setState.
- 코드 하이라이팅: `highlight` 패키지 코어(`highlight.parse`)로 fenced code를 라인 단위 토크나이즈 → `github`/`atom-one-dark` 테마 컬러 span. json/go/py/sh/js/yaml/dart 등 등록 없이 동작. fence 라인은 비활성 시 collapse. 미지원 언어/파서 오류는 plain mono fallback(char 보존). 키 입력당 재파싱 비용은 라인 단위 memoize(`_highlightCache`, key=`lang line`, 2000 cap)로 비활성 라인 재파싱 제거.
- 불변식: span 텍스트 합 == controller.text(활성/비활성/코드 포함). 독립 적대 리뷰가 40+ 적대 입력 × 상태 × 선택 + highlight 소스로 검증, char 손상 0.
- 검증(5회+): 컨트롤러 단위테스트 8(char 보존 양상태, 마커 collapse/reveal, 다중 컬러 토큰, fallback) / 통합 테스트(focus 배선 + 커서 이동 활성 갱신) / `flutter analyze` clean / 전체 177 통과 / 독립 적대 리뷰(critical 0; live 재렌더 SDK 소스 확인) / macOS 빌드 + Finder형 기동 스모크.
- 한계: 표/이미지는 위젯 렌더가 아니라(단일 TextField 제약) 인라인 스타일링까지만. 라인 단위(블록 단위 아님) — 대부분의 노트에선 블록≈라인이라 영향 적음.
