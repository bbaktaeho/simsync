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

## 후속: 코드 박스 + `---` 수평선 (데코레이션 레이어)

- 요구: `---`이 수평선으로 렌더, 코드블록(```...```)을 코드 박스 형태로(편집 가능하게).
- 제약: 단일 TextField에 위젯/박스/HR을 그리면 커서 매핑이 깨짐(WidgetSpan은 toPlainText에 U+FFFC 삽입 → desync). 그래서 **편집은 단일 TextField 유지, 그 뒤에 CustomPaint 데코레이션 레이어**를 동기화해 박스/룰을 그림.
  - `widgets/editor_block_decorations.dart`: `parseEditorBlockRegions(text)`(코드블록=fence open~close 범위, `---`=그 라인 범위; 미종료 fence는 끝까지) + `EditorBlockDecorationPainter`. 페인터는 **TextField와 동일한 span/strut/width/textScaler로 TextPainter를 layout** → `getBoxesForSelection(BoxHeightStyle.max)`로 블록 Y범위 측정 → 코드=둥근 박스, HR=가로선. scroll offset만큼 translate, 폭 단위 캐시(스크롤 시 재layout 안 함).
  - 정렬 핵심: `width - 3.0`으로 layout(= RenderEditable의 `_caretMargin` = caretGap 1.0 + cursorWidth 2.0)해야 줄바꿈 폭이 필드와 일치. TextField에 `strutStyle: StrutStyle.fromTextStyle(bodyStyle)` 명시(페인터와 동일).
  - 컨트롤러: fence/`---` 라인은 비활성 시 `_hideKeepHeight`(투명하되 정상 높이 유지 → 박스/룰 그릴 행 확보), 활성 시 dim. 코드 span의 per-glyph 배경 제거(박스가 대신).
- 검증: 영역 파서 단위테스트 6, HR 숨김/표시 + char 보존(`---`/`***`/코드) 컨트롤러 테스트, 에디터 위젯테스트(데코레이션 페인터 마운트 + paint 무예외), `flutter analyze` clean, 전체 185 통과, macOS 빌드 + Finder형 기동 스모크. 독립 적대 리뷰: 정렬 dy/dx=0 경험 확인, scroll 동기화·Stack·hit-test·dispose 안전, critical 0. caret-margin 정렬 결함 1건 수정.
- 알려진 한계: 내용 없는 빈 마커 라인(예: 빈 `# `)이 코드/HR 바로 위에 있고 커서를 거기 둘 때, selection-only 변경엔 페인터 미재생성이라 그 아래 박스가 일시적으로 ~12px 어긋남(다음 편집 시 보정). 매우 드물어 한계로 둠.

## 후속: 마크다운 전체 표현 지원 (인용문 등)

- 요구: 마크다운 모든 표현 반영, 특히 `>` 인용문 렌더링. 인터넷으로 CommonMark+GFM+확장 전체 형식 확인 후 적용.
- 추가 구현:
  - **blockquote**: 컨트롤러는 `>`/`>>` 마커를 비활성 시 투명-폭유지(`_hideKeepHeight`, 들여쓰기 확보)·활성 시 dim, 내용은 muted italic. 데코레이션 레이어가 **왼쪽 바**를 그림(연속 `>` 라인 그룹핑, 빈 줄로 종료). `EditorBlockRegion.kind`(code/rule/quote)로 확장.
  - **인라인 토큰 전체**(named-group 정규식): `***bold italic***`/`___`, `**`/`__` bold, `*`/`_` italic, `~~strike~~`, `==highlight==`, `` `code` ``, 링크 `[text](url)`(텍스트는 accent+underline, url·괄호는 비활성 시 숨김), autolink `<url>`, 평문 URL. 순서: 긴 opener 우선, link→plain-url, autolink→plain-url.
  - char 보존: 각 토큰을 마커+내용+마커로 분해해 원문 정확 복원(`![img](x)`는 `!`가 평문으로 보존되고 `[img](x)`만 링크 — 손상 없음).
- 위젯 한계: 표·이미지는 위젯 렌더 불가(단일 TextField). 인라인/박스/바까지가 한계.
- 검증(5회+): 컨트롤러 테스트(새 토큰 char 보존 양상태 + 링크/`***`/`==`/blockquote hide·reveal) / 영역 파서 테스트(code/rule/quote 그룹핑·종료·fence 제외) / `flutter analyze` clean / 전체 189 통과 / 독립 적대 리뷰(42 적대 입력 char 보존, 정규식 순서·backtracking·blockquote 파싱 검증, critical 0) / macOS 빌드 + Finder형 스모크.
- 부수: 리뷰가 발견한 기존 결함(controller 파일에 NUL 0x00 2개 — memoization 키 구분자/주석, git 바이너리 인식 유발) 공백으로 교체(런타임 무영향).

## 후속: Cmd+W 탭 닫기 단축키

- `ShortcutAction.closeTab`(기본 `Cmd+W`) 추가 — 설정형 바인딩 시스템에 등록(설정 > 단축키에 자동 노출·재설정 가능). `document_screen._handleHardwareKeyEvent`에서 활성 탭(`_selectedNote`)을 `_closeTab`. 닫기 시 더티 노트는 EditorPanel의 노트 prop 변경 flush로 보존.
- 검증: 통합 테스트(`cmd+W closes the active editor tab` — 자동 오픈된 탭이 Cmd+W로 닫혀 빈 상태 복귀), analyze clean, 전체 190 통과, macOS 빌드+스모크.

## 후속: 코드 박스가 타이핑 중 안 늘어나는 버그 수정

- 증상: 코드블록에 다음 라인을 작성해도 코드 박스 그림이 늘어나지 않음.
- 근본 원인: 데코레이션 페인터는 `_buildEditor`에서 생성되는데, 타이핑 시 `_onContentChanged`가 setState를 안 함(의도적) → `_buildEditor` 미리빌드 → 페인터가 새 span/regions로 갱신 안 됨(repaint는 스크롤만 청취). 박스가 옛 크기로 고정.
- 수정: 데코레이션 레이어만 `ListenableBuilder(listenable: _contentController)`로 감싸 텍스트/커서 변경 시 페인터를 새 span·regions로 재생성·재측정(전체 패널은 미리빌드). 박스/룰/인용바가 입력에 따라 즉시 늘고 줄어듦. 부수효과로 이전 "빈 마커 라인 위 블록" 정렬 한계도 해소(selection 변경에도 재측정).
- 검증: 통합 테스트(`code box decoration grows as more code lines are typed` — 코드 라인 추가 시 region.end 증가), analyze clean, 전체 191 통과, macOS 빌드+스모크.

## 후속: 코드 박스가 콘텐츠 아래로 길게 뻗는 버그 수정

- 증상: 코드블록 닫은 뒤(``` 이후) 작성한 텍스트 쪽으로 코드 박스 그림이 넘어감.
- 재현으로 확인: 정적 콘텐츠는 정확(닫는 ```에서 region 끝, 이후 텍스트는 일반 폰트). 문제는 데코레이션 박스가 **숨겨진 fence 행(full-height 23.8px)을 포함**해 박스가 콘텐츠보다 ~2행 길어져 다음 줄에 닿음.
- 근본: fence 줄을 `_hideKeepHeight`(투명·전체높이 유지)로 렌더 → 박스가 fence 행 높이까지 감쌈. + strut floor(bodyStyle 14→23.8px)가 collapse를 막음.
- 수정: (1) fence 줄을 `_marker`(비활성 시 fontSize 0.1)로 collapse, (2) TextField·painter의 strut를 minimal(`fontSize 1`)로 낮춰 fence 줄만 ~1px로 줄임(실측: 일반/빈 줄은 23.8px 유지, fence만 1px). 박스가 콘텐츠에 딱 맞음. `---`·blockquote는 `_hideKeepHeight` 유지(행 높이 필요).
- 검증: fence collapse 테스트, char 보존·정렬 테스트 유지, analyze clean, 전체 192 통과, macOS 빌드+스모크.

## 후속: 코드블록에서 빠져나갈 수 없는 문제 (Enter 탈출)

- 증상: 코드 박스 다음 줄에 쓰려고 Enter를 눌러도 코드 박스만 계속 늘어남.
- 근본 원인: 종료되지 않은(unterminated) 코드 펜스(여는 ```만 있고 닫는 ``` 없음) → 박스가 문서 끝까지 확장, Enter마다 안에서 줄 추가. 닫는 펜스가 collapse 렌더라 인지·탈출 어려움.
- 수정: `markdown_editing.dart`에 `_exitUnterminatedCodeFence` — 미종료 코드블록 안의 **빈 줄에서 Enter** 시 그 자리에 닫는 펜스를 넣고 커서를 블록 밖 아래 줄로 이동(Typora식). 여는 마커(```/~~~)와 동일하게 닫음. 종료된 블록·비빈 줄·블록 밖은 영향 없음.
- 검증: 포매터 테스트 5(미종료 빈 줄 닫고 탈출, ~~~ 동일 마커, 비빈 줄 일반 개행, 종료 블록 무영향, 일반 텍스트 무영향), analyze clean, 전체 197 통과, macOS 빌드+스모크.

## 후속: UI 다듬기 (커서 정렬/버튼 대비·크기/위클리 표시)

- 커서-텍스트 불일치: 직전 minimal strut(fontSize 1)이 빈 필드 커서 정렬을 깨뜨림 → `StrutStyle.fromTextStyle(bodyStyle)`로 복원(TextField·painter 동일). fence는 `_marker`(collapse)→`_hideKeepHeight`(투명 full-height)로 복원하되, 코드 박스 region을 **콘텐츠 라인만**으로(`parseEditorBlockRegions`) 바꿔 박스가 안 길어지고 다음 줄을 침범하지 않게.
- 버튼 파란 selected 대비: 설정 provider 선택을 `_providerChip`로 — 선택 시 accent 배경+흰 텍스트(또렷), 미선택 surface+muted(ChoiceChip 기본 저대비 해소).
- 버튼 크기: 위클리 Generate(아이콘 16/13px/패딩↑/min 36), 삭제·취소 다이얼로그(취소 TextButton, 삭제 FilledButton error+흰 텍스트, 13px/패딩↑).
- 위클리 Generate 표시: 에러를 테두리 박스로 prominent하게, 안내 메시지를 provider-무관하게. **표시 자체는 정상**(위젯 테스트: 성공→요약, 실패→에러, 게이팅). "아무것도 안 나옴"은 provider 미설정/라이브 호출 문제 — 마스터 토글+provider 설정 필요.
- 설정 Claude 테스트: 앞서 node-PATH(buildPathEnv)+방어 try/catch 수정으로 죽지 않고 결과 표시. 로직 정상, 결과는 사용자 claude 설치/API 키에 의존.
- 검증(6회): 전체 201 테스트, analyze clean, strut 가드 테스트, 위클리 표시 테스트 3, macOS 빌드+스모크, 독립 적대 리뷰(critical 0). 픽셀 정합은 스크린샷 불가로 로직으로 검증.

## 후속: 마크다운 표 그리드 에디터

- 요구: 표를 파이프 문법 손작성 대신 실제 표 모양(셀 입력)으로 작성/편집.
- 제약: 단일 TextField엔 인라인 편집 가능 위젯 불가(커서 desync) → **그리드 에디터 다이얼로그**(`widgets/table_editor_dialog.dart`)로 셀 입력 → 마크다운 직렬화. 사용자는 파이프를 안 씀.
- `services/markdown_editing.dart`: `MarkdownTableData`(rows/aligns) + `MarkdownTableAlign`, `tableAtOffset`(커서 위치의 표 감지·파싱·범위), `serializeMarkdownTable`(정렬·`\|` 이스케이프). 파서는 unescaped `|`로 split하고 `\|`를 언이스케이프(직렬화와 대칭 → 리터럴 파이프 셀 round-trip 안전). 구식 `buildMarkdownTable`/`_InsertTableDialog`/`_TableSpec`/`_StepperRow` 제거.
- `editor_panel._insertTable`: 커서가 표 안이면 그 표를 그리드로 열어 편집 후 범위 교체(`_replaceRange`), 아니면 새 표 삽입. 툴바 표 버튼 tooltip "표 삽입 / 편집".
- 그리드 에디터: 셀 TextField, 행/열 추가·삭제(헤더·최소 1행/열 보호), 열별 정렬 토글(L/C/R), 삽입/저장·취소. 컨트롤러 add/remove 시 dispose.
- 검증(6+): 표 파싱/직렬화/정렬/감지/round-trip(+리터럴 파이프) 단위테스트, 그리드 위젯테스트(편집→직렬화/행·열 추가/취소), 에디터 삽입 테스트, analyze clean, 전체 209 통과, macOS 빌드+스모크, 독립 적대 리뷰(critical 1=이스케이프 비대칭 발견·수정, 나머지 niche/cosmetic defer).
- 한계(docstring 명시): 코드펜스 내 파이프 라인 오탐 가능, 표 바로 위 파이프 산문은 감지 가림(둘 다 빈 줄로 회피; GFM도 표 위 빈 줄 권장).

## 후속: 표 에디터를 pluto_grid 라이브러리 기반으로 교체

- 요구: 표 에디터를 라이브러리로 구현. pub.dev 조사 — `editable`(5년 방치), `pluto_grid_plus`(discontinued)는 제외, **`pluto_grid 8.1.0`**(주 25.5k 다운로드, MIT, macOS, 셀 편집+키보드 내비, 활발 유지보수) 채택. API는 context7로 확인(추측 금지).
- 매핑: 마크다운 표는 헤더가 편집 데이터 행 → **모든 행을 pluto 데이터 행**(row 0=헤더, rowColorCallback로 틴트), 컬럼은 위치(`c0..`). `_data`+`_aligns`가 모델, pluto onChanged가 _data 갱신. 정렬은 툴바(포커스 열에 적용), 행/열 추가·삭제도 툴바. 구조 변경 시 `_gridVersion`(key) bump으로 재빌드(편집은 _data로 보존). 직렬화/파싱은 기존(`serializeMarkdownTable`/`tableAtOffset`) 재사용.
- **critical 수정(독립 리뷰가 pluto 소스로 실증)**: `setEditing(false)`는 편집 TextField 값을 cell.value에 커밋하지 않음 → 셀 타이핑 후 Enter/Tab 없이 Save/툴바 클릭하면 입력 유실. 수정: `_syncFromGrid`에서 읽기 전 `sm.textEditingController.text`를 `changeCellValue`로 현재 셀에 직접 커밋. 회귀 테스트(타이핑→Enter 없이 Save→캡처) 추가.
- 검증: 표 다이얼로그 위젯테스트 6(렌더/초기 직렬화/행·열 추가/blank/취소/편집 캡처), analyze clean, 전체 211 통과, macOS 빌드(pluto 포함)+스모크, 독립 적대 리뷰(critical 1 발견·수정, 나머지 sound).
- 트레이드오프: pluto는 스프레드시트 키보드 내비를 주지만 마크다운의 편집형 헤더·열별 정렬은 "헤더=틴트된 첫 행 + 정렬 툴바"로 우회. 이전 커스텀 그리드 다이얼로그를 대체.

## 후속: 표를 에디터 본문에 인라인 렌더링 (raw 마크다운 제거)

- 문제: pluto 다이얼로그는 별도 팝업이고, 에디터 본문에선 표가 여전히 raw `| ... |` 마크다운으로 보임. 사용자는 본문에서 표가 렌더되어 보이길 원함.
- 제약: 단일 TextField엔 위젯 인라인 임베드 불가(커서 매핑). → 코드박스와 같은 **데코레이션 레이어** 방식 확장.
- 구현: `findTableRegions(text)`(markdown_editing.dart) 모든 GFM 표 탐지(펜스 제외, 행별 char 범위) → 컨트롤러가 표 라인 숨김(헤더/본문 투명 keep-height, 구분선 fontSize~0) → painter `_paintTable`이 그리드+셀 텍스트(균등 열, 헤더 틴트, 정렬, ellipsis) 그림. 직렬화/파싱은 기존 재사용.
- 표 클릭 → 편집: `onTap: _handleContentTap`(post-frame로 settle된 selection 읽고 `tableAtOffset`이면 다이얼로그). 숨은 마크다운에 커서가 박혀 타이핑으로 표가 깨지는 문제 방지. `_insertTable`은 캐럿 위치 표 편집/신규 삽입 분기.
- **독립 적대 리뷰가 critical 1 실증**(시각 결함, 내가 못 봄): 공유 strut가 라인 높이를 floor → 구분선이 fontSize 0.1로도 collapse 안 됨 → 모든 표에 헤더-본문 사이 ~14px 빈 띠(리뷰어가 box 측정으로 입증: header[0.2,24], sep[24,38]=14px, body[38,62]). 수정: painter가 예약 밴드를 논리 행 수로 균등 분할해 slack 흡수(셀 텍스트는 painter가 직접 그려 숨은 라인 Y 비종속) → 빈 띠 수학적 제거 + 행 높이 균일. minor: bare `---` 구분선이 rule로 중복 렌더 → editor_panel에서 표 구분선과 겹치는 rule 영역 제외.
- 검증: findTableRegions 5, 컨트롤러 표 숨김+char보존, painter 표 그리기 no-crash, editor 인라인(painter 배선/캐럿 편집/직접 탭 편집/bare-`---` 필터), analyze clean, 전체 222 통과, macOS 빌드+스모크, 독립 리뷰(critical 1 수정·나머지 sound, char-보존 불변식 확인). pluto 6 테스트 유지(라이브러리 정상).
- 시각 픽셀 정확도는 스크린샷 없이 확정 불가 → 사용자 눈 확인 필요(밴드 제거·정렬은 결정적으로 보장).

## 후속: 표를 인라인 오버레이 위젯으로 교체 (좌우 스크롤 + 커서 시 +열/+행)

- 요구: 별도 오버레이(pluto 다이얼로그) 말고 **기존 에디터 화면에서** 표 수정. 커서가 표에 있으면 우측 +열/하단 +행 버튼으로 추가, 커서 밖이면 뷰만, 우측 상단 버튼 유지, 넓은 표는 좌우 스크롤.
- 판단: 좌우 스크롤·인라인 +버튼은 그려진(CustomPaint) 표로는 불가(정적). → 표를 **실제 위젯 오버레이**(`InlineTableView`)로 교체. 단일 TextField는 유지(텍스트 편집 회귀 방지)하고, 표 마크다운은 컨트롤러가 숨긴 채 측정된 rect 위에 위젯을 띄움.
- 구현: `measureTableRegions`(필드와 동일 레이아웃으로 표 rect 측정, painter에서 표 그리기 제거) → `editor_panel._buildTableOverlays`가 텍스트/캐럿/스크롤에 동기화해 `Positioned`로 InlineTableView 배치. 위젯: 가로 스크롤(colW=max(132,폭/열)), 헤더 틴트, active 시 +열(우)/+행(하) 버튼 → `_mutateTable`이 마크다운 in-place 교체(캐럿 유지로 active 지속). 탭=활성화(`_activateTable`). 셀 내용 편집은 우측 상단 버튼→pluto 다이얼로그 유지(사용자 명시). 필드 onTap(다이얼로그) 제거.
- 스코프(명시): 인라인은 +열/+행 구조 편집(사용자 "그거 클릭하면 열·행 추가되면 되는거지"). 셀 내용은 다이얼로그.
- **독립 적대 리뷰: critical 0**. 최고 위험(오버레이가 필드 위 → 본문 탭 패스스루)은 안전(Stack/Positioned만, opaque 배경 없음 → 빈 영역 hit 통과; 텍스트 선택/캐럿 정상). minor 3: (1) active 중 캐럿이 숨은 마크다운에 있어 타이핑 시 표 변형(복구 가능·드묾), (2) 측정 밴드가 strut-floor된 구분선 포함해 표 ~1줄 높음(시각만, 갭/겹침 없음), (3) 키 입력당 레이아웃 2회(짧은 노트 무방). 모두 수용.
- 검증: 표 테스트(InlineTableView 렌더/탭 활성화+행·열 추가 정확 마크다운/툴바 버튼 편집/bare-`---` 필터/char-보존), analyze clean, 전체 223 통과, macOS 빌드+스모크, 독립 리뷰(critical 0). 시각/상호작용 느낌은 스크린샷 없어 사용자 확인 필요(정렬·스크롤·버튼 동작은 결정적).

## 검색 기능 고도화 (역색인 최적화 + 필터 UI 재디자인)

- 요구: (1) 최적화(인덱싱 미리), (2) 태그 검색·from/to 날짜 UI를 보기 좋게(미니 캘린더 + 직접 입력). /frontend-design.
- **최적화**: NoteSearchIndex를 쿼리마다 substring 선형 스캔 → **역색인**(token→ids prefix-AND + tag→ids)으로. upsert/remove 증분 유지. NoteSearchQuery.tag(단일)→tags(멀티 AND). token-prefix AND라 순서무관 다중어 + type-ahead. 검색 입력 120ms 디바운스.
- **필터 UI**: AlertDialog → 필터 버튼에 앵커된 **popover**(OverlayEntry + CompositedTransformFollower). SearchFilterPanel: 멀티 태그 칩, 프리셋(오늘/최근7일/이번달), From/To(YYYY-MM-DD 직접 입력 + 인라인 MiniCalendar 선택, 범위 하이라이트), 라이브 적용. MiniCalendar/SearchFilterPanel 위젯 신규.
- 검증: 패널을 PNG로 렌더해 디자인 시각 확인(칩 선택/프리셋/날짜필드/캘린더 범위 하이라이트 의도대로). 인덱스 테스트(prefix/순서무관/멀티태그/allTags/하이라이트 오프셋), 패널 테스트(칩/프리셋/직접입력/캘린더탭/초기화/클램프), MiniCalendar 테스트. analyze clean, 전체 239, 빌드+스모크.
- **독립 적대 리뷰 critical 0**(오버레이 누수/디바운스 레이스/역색인 증분 모두 안전 확인). minor 수정: 직접 입력 start>end 클램프(캘린더와 일치), 선행 공백 하이라이트 오프셋. 나머지(좁은 창 popover 클램프 없음, 기호 쿼리 분리)는 수용.

## 아이콘 통일 (데스크탑+모바일, 첫 화면 로고)

- 요구: 앱 아이콘(sync 루프)을 모바일·데스크탑 통일 + 데스크탑 첫 시작 화면 로고도 동일하게.
- 단일 소스 painter 추출: `desktop/lib/widgets/app_logo_mark.dart`(paintSyncIcon/paintSyncForeground + AppLogoMark 위젯). 제너레이터·인앱 로고가 모두 이걸 사용 → 절대 안 갈림.
- 첫 화면(login_screen)을 `edit_note` 아이콘 → `AppLogoMark(size:48)`로 교체.
- 제너레이터가 전 플랫폼 생성: macOS(squircle, fullBleed=false), iOS(full-bleed — iOS가 모서리 마스킹), Android legacy ic_launcher(full-bleed) + adaptive(그라디언트 배경 XML + 흰 마크 foreground PNG + anydpi XML).
- 검증: iOS 1024·macOS 512 PNG를 Read로 시각 확인(full-bleed/­squircle 모두 의도대로, macOS 회귀 없음), 모바일 크기·XML 확인, analyze clean, 전체 239, 빌드+스모크. iOS App Store 제출 시 alpha 제거는 추후 고려(개발 빌드 무관).

## 위클리 컨텍스트 스코핑 (다른 경로 차단 + 권한 프롬프트 제거)

- 요구: 주간 요약 컨텍스트는 그 주의 노트만. 다른 경로 파일 읽지 말 것. 권한 요구 대응. 로컬 동기화 노트 사용 확인. 설정 지침 반영 확인.
- 확인: 금주 노트는 stdin 파이프(로컬 `_weekNotes`, GitHub 아님). 지침은 `settings.weeklyInstruction`(설정>Weekly>위클리 지침)이 prompt로 전달 — 둘 다 이미 동작.
- 개선(ClaudeCodeService): CLI 호출에 `--disallowedTools`(Read/Edit/Write/Bash/Glob/Grep/WebFetch/WebSearch/Task/NotebookEdit) 추가 → 파일/셸/네트워크 도구 전면 차단(다른 경로·repo·CLAUDE.md 못 읽음) + headless 권한 프롬프트 제거. `_defaultRunner`는 격리된 빈 임시 디렉토리에서 실행(`-p` trust skip + CLAUDE.md 미로드) + `--no-session-persistence`.
- 검증: claude --help로 플래그 실재 확인, mock runner 테스트(도구 차단 args), analyze clean, 전체 240, 빌드+스모크. 실제 CLI 호출은 CLAUDECODE 가드로 세션 내 런타임 테스트 불가.
