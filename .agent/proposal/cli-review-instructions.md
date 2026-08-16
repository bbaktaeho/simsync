---
title: 리뷰 지침을 스토어에 두고 CLI가 읽기
description: 위클리/먼슬리 리뷰를 CLI(및 외부 agent)에서도 다루기 위해 1·2차 지침과 리뷰 규칙을 스토어에 내보내는 방안
type: proposal
created: 2026-08-05
status: draft
related:
  - .agent/proposal/cli-note-workflow.md
---

# 리뷰 지침을 스토어에 두고 CLI가 읽기

## 왜 필요한가

CLI에는 위클리/먼슬리 리뷰 기능이 없다. 단순히 명령을 안 만들어서가 아니라,
**리뷰를 앱과 같은 결과로 만들려면 CLI가 앱의 지침을 알아야 하는데 알 방법이
없기 때문**이다. 리뷰는 2단계 파이프라인이고 각 단계가 서로 다른 지침을 쓴다.

## 현황 (확인된 사실)

| 요소 | 정의 위치 | 스토어에 있나 | 사용자 편집 |
|------|-----------|---------------|-------------|
| 1차 위클리 아웃라인 시스템 지침 | `AppSettings.weeklyOutlineSystemInstruction` (코드 상수) | 없음 | 불가 |
| 1차 먼슬리 아웃라인 시스템 지침 | `AppSettings.monthlyOutlineSystemInstruction` (코드 상수) | 없음 | 불가 |
| 2차 위클리 리뷰 지침 | `AppSettings.weeklyInstruction` | **있음** (`settings/settings.json`) | 가능 |
| 2차 먼슬리 리뷰 지침 | `AppSettings.monthlyInstruction` | **있음** (`settings/settings.json`) | 가능 |
| 리뷰 파일 경로 규칙 | `review_paths.dart` | `.agents/README.md`에 레이아웃만 서술 | — |
| 모델 선택 / provider | `anthropicModel`, `aiProvider` | 있음 (`settings/settings.json`) | 가능 |

- 2차 지침은 `AppSettings.toSyncJson()`을 통해 이미 스토어로 동기화된다.
  API 키와 기기별 경로(`localNotePath`, CLI 경로)는 의도적으로 제외된다.
- 1차 지침은 코드 상수라 스토어 어디에도 없다. 아웃라인의 출력 형식
  (`- [ ] (MM-DD) 제목 — 요약` 체크박스)이 2차 입력 계약이므로, 이걸 모르면
  CLI가 만든 아웃라인을 앱이 이어받을 수 없다.
- 앱 설정 중 기기별 값은 CLI가 `defaults read com.simsync.simsync flutter.<key>`로
  읽는다 (`cli/prefs.go`). macOS 전용이고 앱이 실행된 적 있어야 한다.

## 제안

지침을 **스토어를 단일 출처로** 삼고, 앱과 CLI가 같은 파일을 읽는다.
새 메커니즘을 만들지 않고 이미 있는 두 가지를 잇는다.

1. **1차 지침도 스토어로 내보낸다.** `agent_harness.dart`가 심는 `.agents/`
   하네스에 `review-format.md`를 추가한다. 내용: 2단계 파이프라인 설명, 아웃라인
   체크박스 형식, 리뷰 파일 경로 규칙, 그리고 1차 시스템 지침 원문.
   하네스는 이미 "없을 때만 단일 커밋으로 생성"하므로 비용이 없다.
2. **2차 지침은 지금처럼 `settings/settings.json`을 쓴다.** 사용자가 앱에서
   고친 값이 그대로 스토어에 있으므로 CLI는 클론에서 읽기만 하면 된다.
3. **CLI는 `guide.go`의 기존 우선순위를 그대로 따른다** — 클론의 `.agents/`가
   있으면 그것을(사용자 커스텀이 진실), 없으면 CLI 내장본. `simsync guide
   review-format`이 자연히 붙는다.

이렇게 하면 CLI가 리뷰를 만들 때 필요한 것이 전부 클론 안에 있다:
아웃라인 지침(`.agents/review-format.md`), 리뷰 지침(`settings/settings.json`),
경로 규칙(같은 문서), 입력이 될 노트(`notes/`).

### 예상 명령

```
simsync review outline --weekly [--date YYYY-MM-DD]   1차: 노트 → 체크박스 아웃라인
simsync review write   --weekly [--date YYYY-MM-DD]   2차: 체크된 항목 → 리뷰
simsync review show    --weekly|--monthly             저장된 리뷰 출력
```

모델 호출은 CLI가 직접 하지 않는 쪽이 단순하다. CLI는 **지침과 입력을 조립해
출력**하고, 실제 생성은 CLI를 호출한 agent가 한다(agent 자신이 이미 모델이다).
그러면 API 키를 CLI가 다룰 필요가 없고, `aiProvider` 분기도 필요 없다.
사람이 직접 쓰는 경우를 위해 나중에 provider 호출을 덧붙일 수는 있다.

## 열린 질문

- 1차 지침을 스토어에 두면 **사용자가 고칠 수 있게 되는데**, 앱은 지금 코드
  상수를 쓴다. 앱도 스토어 값을 읽게 바꿀지(일관성) 아니면 스토어 사본은
  CLI 참고용으로만 둘지(현행 유지, 두 값이 갈릴 위험) 정해야 한다.
  → 갈리는 것이 더 나쁘므로 앱도 읽는 쪽이 맞다고 본다. 다만 읽기 실패 시
  코드 상수로 fallback 해야 오프라인/신규 스토어에서 깨지지 않는다.
- 아웃라인의 체크 상태(사용자가 취사선택한 결과)는 파일에 그대로 있으므로
  추가 저장소가 필요 없다 — 확인 완료.
- 기기별 값(`localNotePath`)은 계속 동기화 대상이 아니다. CLI는 `defaults`로
  읽는다. 이 경로가 macOS 전용이라는 제약은 CLI 자체가 macOS 전용인 동안은
  문제가 아니다.

## 범위 밖

- 리뷰 UI(위클리/먼슬리 뷰) 자체의 CLI 재현. CLI는 파일을 만들고 읽을 뿐,
  체크박스 토글 같은 상호작용은 앱이 한다.
- provider(API/Claude CLI/Codex) 선택을 CLI가 흉내내는 것. 위 설계에서는
  호출자가 모델이므로 불필요하다.
