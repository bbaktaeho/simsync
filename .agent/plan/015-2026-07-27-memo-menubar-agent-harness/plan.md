---
title: 메모 직접 생성 + 메뉴바 노트 관리 + 노트 스토어 agent 하네스 (0.3.1)
description: 추가 메뉴에서 메모 직접 생성, 메뉴바 팝오버 우클릭 관리 메뉴, 노트 스토어 repo에 AI agent 지침 하네스 자동 생성
type: plan
created: 2026-07-27
status: active
---

# Plan: 0.3.1 — memo create, menubar actions, agent harness

## Confirmed requirements

1. 노트 생성 시 곧바로 메모로도 생성 가능해야 한다. 메인 창과 상단 메뉴바(트레이 팝오버) 모두.
2. 메뉴바 팝오버의 노트/메모에 우클릭 메뉴 추가: 삭제 + 로컬 전환 + 동기화 전환. 기존 앱(메인 창 사이드바)과 동일 기능.
3. private 노트 스토어에 AI agent용 하네스(지침 라우팅 체인) 자동 생성:
   - 없으면 자동 생성, 신규 repo 생성 시엔 무조건 생성
   - AGENTS.md가 실체, CLAUDE.md 등 시작점 파일은 symlink로 AGENTS.md 연결
   - AGENTS.md는 `.agents/README.md`로 라우팅, README.md가 `.agents/` 내 지침들을 라우팅
   - 지침 내용은 초안 (소유자 검토 후 개선)
4. 버전 0.3.1.

## Assumptions

- Desktop만 대상. 메뉴바 기능은 macOS 전용이고, mobile은 별도 포팅 트랙(관례).
  mobile에서 만든 repo도 desktop이 열면 하네스가 자동 생성되므로 커버된다.
- 팝오버 우클릭 메뉴는 메인 창과 동일 항목: 동기화/로컬 전환, 메모/daily 이동, 삭제.
- symlink는 GitHub Git Database API(mode 120000)로 생성한다. Contents API는 symlink를 만들 수 없다.
- 하네스 언어는 한국어(소유자 노트가 한국어), 기술 식별자는 영어.

## Proposed decisions

- 추가 메뉴를 4항목으로: 동기화 노트 / 로컬 노트 / 동기화 메모 / 로컬 메모.
  탭 전환 없이 어디서든 한 번에 생성("곧바로")이 요구사항이므로 탭 컨텍스트 방식 대신 선택.
- 팝오버 생성도 동일 4항목 (기존엔 동기화 전용 + 탭 컨텍스트). `MenuBarController.createNote`에 `local` 파라미터 추가.
- 우클릭 메뉴와 삭제 확인 다이얼로그를 `widgets/note_list_menus.dart`로 추출해 메인 창/팝오버 공용화 (중복 제거).
- 하네스 생성 진입점은 `defaultStorageFactory` 한 곳: 신규 repo도 생성 직후 이 경로를 지나므로 별도 훅 불필요.
  AGENTS.md GET 1회로 존재 확인 → 404면 단일 커밋으로 전체 생성. 실패는 조용히 넘기고 다음 실행에서 재시도.
- 하네스 파일: `AGENTS.md`(실체) / `CLAUDE.md`,`GEMINI.md`(symlink) / `.agents/README.md`(라우팅) /
  `.agents/note-format.md`(경로·frontmatter 스키마) / `.agents/guidelines.md`(작업 규칙).

## Affected files

- `desktop/lib/widgets/note_list_menus.dart` (신규): 공용 추가 메뉴 버튼, 우클릭 메뉴, 삭제 확인 다이얼로그
- `desktop/lib/widgets/note_list_section.dart`: 자체 메뉴 제거, 공용 위젯 사용, 콜백에 memo 파라미터
- `desktop/lib/screens/document_screen.dart`: `_createNote`/`_createLocalNote`에 memo, 삭제 다이얼로그 공용화
- `desktop/lib/services/menu_bar_controller.dart`: createNote(local), deleteNote, convertNote, setMemo
- `desktop/lib/widgets/menu_bar_panel.dart`: 추가 버튼 교체, _NoteRow 우클릭 메뉴
- `desktop/lib/storage/github/github_api_client.dart`: `commitFiles` (Git Database API)
- `desktop/lib/services/agent_harness.dart` (신규): 하네스 템플릿 + `ensureAgentHarness`
- `desktop/lib/app_bootstrap.dart`: ensure 호출
- `desktop/pubspec.yaml`: 0.3.1+6
- 테스트: menu_bar_controller_test, note_list_section_test, github_api_client_test, agent_harness_test(신규)

## Out of scope

- mobile 포팅 (별도 트랙)
- 팝오버 날짜 우클릭 메뉴(노트/메모 추가) 변경 — 기존 유지
- 하네스 지침의 다국어화, 추가 도구(cursor 등) symlink — 초안 이후 결정
