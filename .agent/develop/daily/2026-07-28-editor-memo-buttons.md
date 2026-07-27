---
title: 에디터 첫 화면 메모 생성 버튼
description: 생성 화면에 동기화/로컬 메모 버튼 2개 추가 (노트 버튼과 동일 크기), 생성 시 메모 탭 자동 전환
type: develop
created: 2026-07-28
---

# 2026-07-28 — 에디터 첫 화면 메모 버튼

## 변경

`EditorPanel`의 생성 화면(선택 날짜에 노트가 없을 때)에 두 번째 줄 추가:

```
[ 동기화 노트 ] [ 로컬 노트 ]
[ 동기화 메모 ] [ 로컬 메모 ]
```

- `onCreateNote` / `onCreateLocalNote` 시그니처를 `VoidCallback?` →
  `void Function({bool memo})?` 로 바꿔 메모 여부를 전달한다 (사이드바 추가
  메뉴와 같은 규약).
- 같은 `_CreateNoteButton` 위젯을 쓰고 라벨 길이도 동일해 두 줄의 버튼 크기가
  정확히 일치한다 (테스트로 고정).
- 메모 아이콘은 사이드바 추가 메뉴와 같은 `sticky_note_2_outlined`.

## 메모 탭 자동 전환

이미 `_finishCreate`가 `_memoTabActive = newNote.isMemo`로 처리하고 있어,
에디터 화면에서 만든 메모도 좌측 리스트가 메모 탭으로 전환된다. 생성 경로
(사이드바 +, 에디터 첫 화면)가 모두 이 함수를 지나므로 추가 작업이 없었다.

## 검증

- flutter analyze clean, flutter test 485개 통과
- 신규 위젯 테스트 4개: 버튼 4개 존재 / 메모·노트가 각각 memo:true·false로
  호출 / 노트·메모 버튼 크기 동일 / 로컬 콜백 없으면 로컬 버튼 2개 숨김
- 실제 앱 스크린샷으로 2×2 배치와 크기 일치 확인

## 참고 (범위 외 발견)

노트 시각 표시가 UTC로 보인다. `GitHubNoteStorage.parseNote`가
`DateTime.parse('...+0900')`로 파싱하면 Dart는 **UTC DateTime**을 돌려주는데,
표시할 때 `.toLocal()`을 하지 않아 9시간 어긋난다 (08:25 생성 → 23:25 표시).
앱이 쓴 노트와 CLI가 쓴 노트 모두 해당되는 기존 동작. 별도 수정 필요.
