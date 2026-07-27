---
title: CLI 클론 존재 가드 + 설치 문서 (0.3.2)
description: 클론이 지워졌을 때 note new가 고아 파일을 만들던 갭 차단, cli/README.md 설치 가이드 추가
type: develop
created: 2026-07-28
related:
  - .agent/plan/016-2026-07-27-cli-foundation/plan.md
  - .agent/proposal/cli-note-workflow.md
---

# 2026-07-28 — CLI 클론 가드 (0.3.2, CLI 전용 릴리즈)

## 배경

0.3.1 릴리즈 후 소유자 질문("틀어질 때 방지는 어떻게 되나")에 답하며 코드를
재확인하다 발견한 갭. `requireConfig`는 스토어 이름 불일치만 검사하고 클론
경로의 존재는 확인하지 않았다. 사용자가 클론 디렉토리를 지우거나 옮기면:

- `note new`가 `os.MkdirAll`로 stale 경로에 디렉토리를 새로 만들고 노트를 씀
- → git 밖 고아 파일. `store sync`는 `fatal: not a git repository`로 실패하므로
  스토어 오염은 없지만, 노트 하나가 엉뚱한 곳에 남는다.

## 수정

`requireConfig`에 `<ClonePath>/.git` 존재 확인 3줄 추가.

- 호출부가 `note new`(note.go:79)와 `store sync`(store.go:335) 둘뿐이라,
  공통 게이트 한 곳으로 두 경로가 모두 막힌다. 앞으로 붙는 클론 기반 명령도
  자동 보호된다.
- `.git`은 worktree/submodule에서 파일일 수 있어 종류는 보지 않고 존재만 확인.
- `store sync`의 오류 메시지도 `fatal: not a git repository` → "클론이
  없습니다. store clone으로 다시 클론하세요"로 개선된다.
- `store status`는 그대로 차단 없이 보고만 한다 (진단 명령이 실패하면 원인
  파악이 더 어려워진다).

## 설치 문서 (cli/README.md 신규)

소유자 지적: "어느 경로에서든 실행되게 하는 법"이 릴리즈 노트에 얇게만 있었다.

- PATH 개념 설명 + 세 가지 설치 경로: `/usr/local/bin`(macOS 기본 PATH라 셸
  무관, 권장), `~/.local/bin`(sudo 없이, 셸 rc 등록), 소스 빌드/`go install`
- `which simsync` + 다른 디렉토리에서 실행하는 검증 절차, `command not found`
  대처
- **바이너리를 옮기면 `store clone` 재실행** 안내: credential helper에 CLI의
  절대 경로가 기록되므로 (재클론 없이 설정만 갱신됨)
- 루트에 README가 없어 `cli/README.md`로 두고 `.agent/guide.md`에서 링크

## 검증

- gofmt/vet clean, go test 통과 (신규: 클론 삭제 후 note new가 실패하고 경로를
  되살리지 않는지). 기존 픽스처 `setupClone`에 `.git` 마커 추가.
- 실기: 정상 클론에서 note new/store sync 정상 동작 확인(회귀 없음), 임시 HOME
  으로 클론 없는 상태에서 두 명령 모두 차단 + 디렉토리 미생성 확인,
  store status는 보고만 하는지 확인.

## 릴리즈 범위

CLI 전용 0.3.2. 데스크톱 앱은 0.3.1에서 변경 없음 (`desktop/pubspec.yaml`은
0.3.1+6 유지). 릴리즈에는 편의를 위해 0.3.1과 동일한 DMG를 함께 첨부한다.
