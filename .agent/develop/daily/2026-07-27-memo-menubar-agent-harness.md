---
title: 메모 직접 생성 + 메뉴바 노트 관리 + 노트 스토어 agent 하네스 (0.3.1)
description: 추가 메뉴 4종(동기화/로컬 × 노트/메모), 팝오버 우클릭 관리 메뉴, 노트 스토어 repo AI agent 지침 하네스 자동 생성
type: develop
created: 2026-07-27
related:
  - .agent/plan/015-2026-07-27-memo-menubar-agent-harness/plan.md
---

# 2026-07-27 — 0.3.1: 메모 직접 생성, 메뉴바 관리 메뉴, agent 하네스

## 작업 내용

### 1. 메모 직접 생성 (메인 창 + 메뉴바 팝오버)

- 추가 메뉴를 4항목으로 확장: 동기화 노트 / 로컬 노트 / 동기화 메모 / 로컬 메모.
  기존에는 노트를 만든 뒤 우클릭 → 메모로 이동해야 했다.
- 공용 위젯 `AddNoteMenuButton` (`widgets/note_list_menus.dart`)을 메인 창 리스트
  헤더와 팝오버 탭 줄이 함께 사용한다.
- `MenuBarController.createNote`에 `local` 파라미터 추가 — 팝오버에서도 로컬
  노트/메모 생성 가능 (로컬은 sync 꺼짐 상태에서도 허용, 메인 창과 같은 규칙).
- 생성 후 만든 종류의 탭(메모/daily)으로 전환해 항목이 바로 보인다.

### 2. 메뉴바 팝오버 우클릭 관리 메뉴

- `_NoteRow`에 우클릭 → 메인 창 사이드바와 동일한 컨텍스트 메뉴:
  동기화/로컬 전환, 메모/daily 이동, 삭제(확인 다이얼로그).
- 메뉴와 삭제 다이얼로그를 `note_list_menus.dart`로 추출해 두 화면이 공유
  (note_list_section의 자체 구현 ~170줄 제거).
- `MenuBarController`에 `deleteNote` / `convertNote` / `setMemo` 추가.
  전환은 기존 `note_conversion.dart` 헬퍼 재사용, 전환/삭제 전 pending 저장 flush.
- 버그 수정(양쪽 공통): 제목 변경 디바운스 저장이 대기 중일 때 삭제하면
  경로(제목 유래) 불일치로 GitHub 파일이 남는 문제 — 삭제 전 flush로 해결.

### 3. 노트 스토어 AI agent 하네스

- `GitHubApiClient.commitFiles`: Git Database API(트리 inline content)로 여러
  파일을 단일 커밋 생성. Contents API가 못 만드는 symlink(mode 120000) 지원.
- `services/agent_harness.dart`: 지침 템플릿 + `ensureAgentHarness`.
  라우팅 체인: `CLAUDE.md`/`GEMINI.md`(symlink) → `AGENTS.md` →
  `.agents/README.md` → `.agents/note-format.md`, `.agents/guidelines.md`.
- `defaultStorageFactory`에서 fire-and-forget 호출 — AGENTS.md GET 1회로 존재
  확인, 없으면 생성. 신규 repo도 생성 직후 같은 경로를 지나므로 무조건 심긴다.
  실패(오프라인/경합)는 조용히 넘기고 다음 시작에서 재시도.
- 지침 내용은 초안: 경로 규칙, frontmatter 스키마(id 불변 등), 허용/금지,
  동시성(LWW), 개인정보 취급.

## 테스트

- `flutter analyze` clean, `flutter test` 470개 전부 통과.
- 신규: commitFiles(플로우/symlink/ref 거부), agent_harness(존재/생성/실패 4건),
  MenuBarController(local 생성, 삭제, 전환 왕복, sync-off 차단, setMemo),
  추가 메뉴 위젯(4항목/로컬 숨김).

## 범위 외

- mobile 포팅(별도 트랙). mobile에서 만든 repo도 desktop이 열면 하네스가 심긴다.
- 팝오버 날짜 우클릭 메뉴는 기존(동기화 노트/메모 추가) 유지.
