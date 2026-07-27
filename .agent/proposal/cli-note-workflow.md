---
title: CLI 노트 작성 워크플로 제안 (AI agent용)
description: CLI로 노트를 생성하는 방식 비교 — 클론 기반 / API 직접 / 하이브리드, 가이드 노출 설계 포함
type: proposal
created: 2026-07-27
status: active
related:
  - .agent/plan/016-2026-07-27-cli-foundation/plan.md
---

# CLI 노트 작성 워크플로 제안

## 배경

- CLI의 1차 사용자는 AI agent다. agent가 노트를 "규칙대로" 작성하게 하는 것이 목표.
- 작성 규칙(경로, frontmatter 스키마, id 불변 등)은 이미 노트 스토어 repo의
  `.agents/note-format.md` / `.agents/guidelines.md`에 있다 (0.3.1 하네스).
- 스토어 repo는 일반 GitHub repo이므로 클론이 가능하다.

## 방식 A — 로컬 클론 기반 (git-native)

CLI가 스토어 repo를 클론하고, 노트 작업은 클론 안에서 파일로 한다.

```
simsync store clone <owner/repo> [dir]   # 세션 토큰으로 클론 + 설정 저장
simsync note new [--date 2026-07-27] [--title "..."] [--memo] [--local? 없음]
                                         # 규칙대로 경로/frontmatter 스캐폴드 생성, 경로 출력
simsync store sync                       # pull --rebase + push (앱 커밋과 정합)
```

agent 워크플로: `store clone` → 클론 디렉토리에서 작업 (AGENTS.md/.agents/가
그대로 agent 지침이 된다) → `note new`로 스캐폴드 → 본문 작성 → `store sync`.

- 장점
  - 하네스가 그대로 살아난다: 클론을 연 AI 도구(Claude Code 등)가 AGENTS.md를
    자동으로 읽는다. CLI와 하네스가 한 시스템이 된다.
  - 읽기/검색/수정/대량 작업이 전부 공짜 (파일시스템 + git). read/list/update
    명령을 CLI에 재구현할 필요가 없다.
  - 오프라인 작성 가능, 커밋 이력/롤백은 git이 제공.
- 단점
  - 클론 상태 관리 필요 (위치 설정, 오래된 클론, push 충돌 → pull --rebase로 해소).
  - 토큰을 remote URL에 넣지 않도록 git credential 처리 주의.

## 방식 B — GitHub Contents API 직접 (앱과 동일 경로)

클론 없이 CLI가 API로 즉시 커밋한다.

```
simsync note create --date 2026-07-27 --title "..." [--memo] --content-file - 
```

- 장점: 무상태(클론 관리 없음), 단발 자동화(cron/원격 스크립트)에 적합, 앱과 같은 방식.
- 단점: 기존 노트를 읽고 고치려면 read/list/update/delete 명령을 계속 추가하게 됨
  (git이 공짜로 주는 것을 API로 재구현). 오프라인 불가, 대량 작업 느림.
  agent가 규칙 문서를 보려면 별도 fetch 필요.

## 방식 C — 하이브리드 (단계적)

1차는 A(클론 기반)를 기본으로 하고, 필요해지면 B의 원샷 명령
(`simsync note quick "한 줄 메모"` — API로 즉시 커밋)을 추가한다.

## 가이드 노출 설계 (공통)

```
simsync guide                # 가이드 목록 + 개요 (.agents/README.md)
simsync guide note-format    # 노트 작성 규칙 전문
simsync guide guidelines     # agent 작업 규칙 전문
```

- 소스 우선순위: 클론이 설정돼 있으면 클론의 `.agents/`에서 읽는다 (사용자
  커스텀 반영). 없으면 CLI에 내장된 canonical 사본을 출력한다 — 내장 원문은
  데스크톱 `agent_harness.dart` 템플릿과 동일하게 유지한다.
- agent 표준 워크플로: `auth status` → `guide note-format` → `note new` → 본문
  작성 → `store sync`.

## 추천

**방식 C (= A를 1차로, B는 후순위)** 를 추천한다.

근거: 이 CLI의 사용자는 AI agent이고, agent는 "로컬 파일 + git" 환경에서 가장
잘 동작한다. 클론 기반은 하네스(.agents/)를 별도 비용 없이 agent 지침으로
살리며, CLI가 유지할 표면적(명령 수)을 최소로 유지한다 — CLI는 스캐폴드와
동기화만 책임지고 나머지는 git과 agent에 맡긴다. API 원샷은 cron 등 무상태
자동화 수요가 실제로 생겼을 때 추가한다.

## 결정 (2026-07-27, 소유자)

1. 노트 작성 방식: **C 채택** — 클론 기반을 1차로 구현 (`store clone`/`store sync`/
   `note new`/`guide`), API 원샷은 수요 발생 시 추가.
2. bare `simsync`: **help 출력으로 변경**, 앱 실행은 `simsync open`으로 이동.
3. `note new`는 synced 스토어(클론) 전용 — 로컬 노트는 범위 외.

구현 노트: 인증은 클론 로컬 git 설정에 `simsync auth git-credential` helper를
등록하는 gh 방식 — 토큰이 git 설정/URL에 남지 않고, 클론 안의 맨 git
pull/push도 CLI 세션으로 동작한다. helper는 https + github.com 요청에만
토큰을 내준다 (다른 host remote/submodule로의 유출 차단).

## 추가 결정 (2026-07-27, 소유자): 앱과 상태 공유

CLI와 데스크톱 앱은 같은 로컬 머신에서 "같은 상태 파일"을 공유한다 — 별도
IPC 없이 (앱은 sandbox off, 두 파일 모두 시작 시 읽음):

| 상태 | 공유 파일 | 규칙 |
|------|-----------|------|
| 세션 | `~/Library/Application Support/com.simsync.simsync/auth/session.json` | 앱 FileSessionStore와 동일 파일·스키마. 한쪽 로그인 = 양쪽 적용. CLI는 Dart 로컬 ISO8601 타임스탬프도 파싱, 쓸 때는 RFC3339(Dart 파싱 가능) |
| 스토어 | `~/.simsync/repos.json` | 앱 RepoCache와 동일 파일. 첫 엔트리 = 활성 스토어. CLI `store clone`은 인자 없으면 이걸 쓰고, 다른 repo 지정은 거부, 앱에 없으면 클론 성공 후 첫 엔트리로 기록(connectedAt 필수 — 없으면 앱 파싱 실패) |

- 로그인 2회 문제 해소, 스토어 불일치 원천 차단 (`requireConfig`가 클론↔공유
  스토어 불일치도 거부).
- 한계(문서화): 앱이 "실행 중"일 때 CLI가 바꾼 상태는 앱 재시작에 반영된다.
  실시간 IPC는 필요해질 때 추가.
