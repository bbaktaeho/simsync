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

## 추가 수정: credential helper 격리 + PATH 이름 등록

소유자 질문("바이너리 경로 이동이 이슈인가")을 검증하다 더 큰 문제를 발견했다.

**발견**: macOS Xcode git은 시스템 스코프에 `credential.helper = osxkeychain`을
박아둔다(`/Applications/Xcode.app/.../git-core/gitconfig`). git은 system →
global → local 순으로 helper를 시도하므로, keychain에 github.com 자격 증명이
있으면 거기서 답이 나오고 **우리 local helper는 호출조차 되지 않는다**.
`GIT_TRACE`로 확인: `git credential-osxkeychain get` 하나만 실행됨.

즉 "클론 안의 맨 git pull/push도 CLI 세션으로 동작한다"는 기존 주장이 이런
환경에서는 사실이 아니었다 (다른 신원으로 조용히 인증됨).

**수정 1 — helper 목록 리셋**: 클론 local 설정에 빈 값을 먼저 넣어 상위
스코프 목록을 지운 뒤 SimSync helper를 등록한다. 신규 클론은
`--config credential.helper=` + `--config credential.helper=<spec>`, 기존 클론은
`--replace-all` + `--add`. 리셋은 해당 클론에만 적용된다.
부수효과도 바람직하다: 세션 만료 시 다른 토큰으로 넘어가지 않고 명확히 실패.

**수정 2 — PATH에 있으면 이름으로 등록**: `exec.LookPath("simsync")`가 성공하면
`!simsync auth git-credential`로 기록한다. PATH 안에서 바이너리를 옮기거나
교체해도 클론 설정을 고칠 필요가 없다. 못 찾으면 절대 경로 폴백(이 경우에만
"옮기면 store clone 재실행" 주의가 적용).

**검증**: 테스트에서 local 설정이 `["", helper]` 두 항목인지 확인
(`--get-all`은 빈 값이 TrimSpace에 지워져 `--list`로 파싱). 실기로 실제 스토어
클론을 갱신해 `GIT_TRACE` 상 SimSync helper가 실행되고 `username=x-access-token`
이 나오는 것까지 확인.

## 릴리즈 범위

소유자 요청으로 **v0.3.1 하나로 통합**한다 (릴리즈가 너무 많아짐). v0.3.2는
삭제하고, 이 문서의 모든 CLI 수정을 v0.3.1에 포함시킨다. CLI 내부 버전도
0.3.1로 되돌려 태그와 일치시킨다. 데스크톱 앱은 변경 없음(pubspec 0.3.1+6).
릴리즈 노트의 앱 설치 안내는 adhoc 서명(=Gatekeeper가 반드시 차단, `spctl`
rejected 확인)에 맞춰 `xattr -cr`를 조건부 각주가 아닌 필수 단계로 고쳤다.
