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

## 디자인 정리 (같은 브랜치)

DESIGN.md를 기준으로 "정리 안 된" 지점만 손봤다. 새 스타일을 만들지 않는다.

### 1. 미완료 토큰 마이그레이션 마무리

`app_dimensions.dart`에 `// Deprecated aliases — remove in PR2 once all usages
migrated` 주석과 함께 구/신 라디우스 토큰이 **41:60으로 공존**하고 있었다.
`borderRadius/borderRadiusSm/borderRadiusLg` 41곳을 `radiusStandard/radiusMicro/
radiusComfortable`로 옮기고 별칭을 삭제했다. 값이 같아 시각 변화는 없다.

### 2. 스케일 밖 라디우스

- `circular(6)` 3곳(인라인 표·이미지 컨테이너, 코드 블록 박스) → `radiusStandard`(8).
  DESIGN.md §5 반경 스케일은 4/5/8/12/16/pill이고 8은 "small cards, containers,
  inline elements"로 규정돼 있다.
- 이미지 리사이즈 핸들이 한 위젯에서 topLeft 4 / bottomRight 5를 섞어 쓰던 것을
  `radiusMicro`로 통일.
- 1/1.5/2px는 헤어라인 장식(탭 밑줄, 인용문 바)이라 그대로 둔다.

### 3. 확인 버튼 스타일 통일

`filledButtonTheme`이 없어 `FilledButton` 5곳이 제각각이었다 — padding 16/10,
12/8, Material 기본값 세 가지에 높이도 36/32/기본으로 갈렸다. 테마에 DESIGN.md
버튼 규격(padding 8x16, radius 4, 높이 36)을 정의하고 호출부의 중복 스타일을
제거했다. 삭제 확인 버튼의 `backgroundColor: c.error`만 남겼다.

### 4. 하드코딩 흰색 → 토큰

액센트 위에 얹히는 흰색 텍스트/아이콘 13곳을 `c.textOnAccent`로 교체
(`onError`도 포함). 라이트/다크 모두 흰색이라 시각 변화는 없지만, 토큰을
바꾸면 따라오도록 만든다. 남긴 두 곳은 의도가 다르다 — 브랜드 로고의 기본
색 파라미터, 그리고 `ShaderMask`의 알파 마스크(색이 아니라 알파만 쓰임,
주석 추가).

### 손대지 않은 것

- **아이콘 크기 11/12/13/14/16/18 혼재** — DESIGN.md에 아이콘 스케일 규정이 없다.
  근거 없이 통일하면 레이아웃만 흔든다. 규격을 먼저 정하는 게 순서다.
- **여백의 2/3/5/6/10px** — DESIGN.md §5가 "non-rigid organic scale"로 2,3,5,6,7,11,14를
  명시적으로 허용한다. 위반이 아니다.

### 검증

`flutter analyze` clean, 527개 통과. 디버그 빌드로 표·코드 블록·체크박스·노트
리스트를 실제 렌더해 확인. 다이얼로그 버튼은 클릭이 필요해 육안 확인 못 했다
(테마 값은 DESIGN.md 규격 그대로).
