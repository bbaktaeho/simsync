---
title: CLI 로컬 노트 지원 + 리뷰 지침 제안
description: simsync note new --local 추가, 위클리/먼슬리 CLI 미지원 사유 문서화, 지침 스토어화 제안
type: develop
created: 2026-08-05
related:
  - .agent/proposal/cli-review-instructions.md
---

# CLI 로컬 노트 지원 + 리뷰 지침 제안

## 확인 결과

- **메모는 이미 됐다** — `note new --memo`가 처음부터 있었다.
- **로컬 노트는 없었다** — CLI는 클론(동기화 스토어)에만 파일을 만들었다.
- **위클리/먼슬리 리뷰도 없다** — 명령 자체가 없다.

## 로컬 노트 추가

`note new --local`. 경로 레이아웃(`notes/YYYY-MM/DD/{제목}.md`)은 데스크톱의
`LocalNoteStorage`와 `GitHubNoteStorage`가 동일하므로 루트만 갈아끼우면 된다.

핵심은 **루트를 어디서 얻느냐**다. 로컬 노트는 동기화되지 않아서 앱과 CLI가 같은
디렉토리를 보지 않으면 서로가 만든 노트를 아예 못 본다. 그런데 `localNotePath`는
기기별 값이라 `settings/settings.json` 동기화에서 의도적으로 빠져 있다.

→ macOS `defaults read com.simsync.simsync flutter.local_note_path`로 앱 설정을
직접 읽는다(`cli/prefs.go`). 실제로 앱이 쓰는 값(`/Users/bbaktaeho/Documents`)이
그대로 나오는 것을 확인했다. 우선순위는
`--path` > `SIMSYNC_LOCAL_NOTE_PATH` > 앱 설정 > `~/Documents/SimSync`.

앱 규칙도 맞췄다: 그 날짜의 첫 **동기화** 일일 노트만 `is_default: true`가 되고,
메모와 로컬 노트는 되지 않는다 (`menu_bar_controller.createNote`와 동일).

`store status`에 로컬 노트 디렉토리를 한 줄 추가했다 — 앱과 CLI가 같은 곳을 보는지
확인하는 수단이자, 경로 해석이 맞는지 파일을 만들지 않고 검증하는 수단이다.

## 위클리/먼슬리는 왜 아직인가

명령을 안 만들어서가 아니라 **CLI가 앱의 지침을 알 수 없어서**다. 리뷰는 2단계고
각 단계가 다른 지침을 쓴다.

| 지침 | 위치 | 스토어에 있나 |
|------|------|---------------|
| 1차 아웃라인 시스템 지침(주/월) | 앱 코드 상수 | 없음 |
| 2차 리뷰 지침(주/월) | `AppSettings` | 있음 (`settings/settings.json`) |

2차는 이미 동기화된다(`toSyncJson`). 1차는 코드에만 있는데, 아웃라인의 출력
형식(`- [ ] (MM-DD) 제목 — 요약`)이 2차의 입력 계약이라 이걸 모르면 CLI가 만든
아웃라인을 앱이 이어받지 못한다.

→ `help`와 `README`에 "곧 구현 예정"으로 사유와 함께 명시하고, 설계는
[.agent/proposal/cli-review-instructions.md](../../proposal/cli-review-instructions.md)에
적었다. 요지는 1차 지침도 `.agents/` 하네스에 내보내고(`agent_harness.dart`),
CLI는 `guide.go`의 기존 "클론 우선 → 내장본" 우선순위를 그대로 쓰는 것이다.
새 메커니즘 없이 이미 있는 둘을 잇는다.

## 검증 (3회)

1. `gofmt` clean, `go vet` clean, `go build`, `go test ./...` 전부 통과.
2. 무력화 검증 — 로컬 노트의 `is_default` 규칙과 `--path` 가드를 각각 되돌리면
   대응 테스트(`TestNoteNewLocal`, `TestNoteNewPathRequiresLocal`)가 실패함을 확인.
3. 실제 바이너리로 로컬 일일 노트·로컬 메모를 만들어 frontmatter를 확인하고,
   동기화 노트가 여전히 클론 경로에 생성되는지(회귀 없음) 확인. 회귀 확인 때
   실제 클론에 만들어진 파일은 커밋 전에 삭제했다.
