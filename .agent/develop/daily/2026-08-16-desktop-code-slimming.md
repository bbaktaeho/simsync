---
title: Desktop Code Slimming
description: desktop/lib 과도 설계 감사 후 죽은 코드 제거와 호버 보일러플레이트 축약
type: develop
created: 2026-08-16
---

# Desktop Code Slimming

기능 변경 없이 코드량만 줄이는 작업. `desktop/lib` 22,120줄 / 72파일 대상.

## 감사 방법

추측 대신 스크립트로 훑었다.

- 공개 타입 103개 각각을 "자기 파일 밖에서 참조되는가"로 검사 → 죽은 타입 색출
- pubspec 의존성 20개를 `package:<name>/` import 존재 여부로 검사
- 파일 간 같은 이름 헬퍼 정의 검색 → 중복 로직 색출 (0건)
- 반복 UI 패턴 카운트 (`_isHovered` 34회, `InputBorder.none` 14회 등)

## 잘라낸 것

| 대상 | 근거 |
|------|------|
| `ConflictResolver` + `LastWriteWinsResolver` | 프로덕션 참조 0. 자기 테스트만 붙어 있었다. LWW 정책은 `mergeDirtyNotes`가 수행 중 |
| `SyncEngine` 추상 인터페이스 | 구현 1개(`GitHubSyncEngine`), 테스트도 구체 클래스를 확장. `SyncStatus` enum만 구현 파일로 옮기고 파일 삭제 |
| 호버 StatefulWidget 6벌 | `HoverBuilder` 하나로 대체. 상태가 `_isHovered` 하나뿐인 위젯들이 위젯+State+createState 세 벌씩 들고 있었다 |
| `cupertino_icons` 의존성 | 코드에서 0회 사용 |

결과: 12파일 +156/-248, `lib` 22,120 → 22,069줄, 의존성 -1개.

## 남긴 것과 이유

- **아이콘 버튼 변종 7종**(`_ToolbarIconButton`, `_MonthNavButton`, `_NavButton`,
  `_IconStepButton`, `_PaginationButton`, `_CornerButton`, `_ClearIcon`) — 크기·테두리·색이
  서로 달라 통합하면 외형이 바뀐다. 공통인 호버 로직만 뽑았다.
- **`_ResizeHandle`** — `_isDragging`도 함께 들고 있어 StatefulWidget이 필요하다.
- **borderless `InputDecoration`** — 완전 동일한 조합은 3곳뿐. 헬퍼를 만들어도 15줄
  남짓이라 간접 계층이 더 비싸다.
- **`AuthProvider` 추상** — 구현은 하나지만 테스트가 `_FakeAuthProvider`로 갈아끼운다.
  실제 테스트 seam이라 유지.
- **예외 클래스 3종**(`CodexCliException` 등) — 타입으로 잡는 곳은 없지만 메시지를 나른다.
  에러 처리는 축약 대상에서 제외한다.

## 검증

- `flutter analyze` clean, 527개 통과 (삭제된 conflict_resolver 테스트 2개 제외, 신규 1개 포함)
- `HoverBuilder`에 마우스 진입/이탈 테스트 1개 추가 — 리팩터의 유일한 위험(호버가 죽는 것)을 잡는다
- 디버그 빌드로 실제 앱 실행 후 VM service `_flutter.screenshot`으로 화면 대조 — 리팩터 전과 동일하게 렌더
