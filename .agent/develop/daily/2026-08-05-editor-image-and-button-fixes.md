---
title: Editor Image / Login Button Fixes
description: 이미지 삽입 캐럿, 리사이즈 실시간 반영, 크기 상한, 로그인 버튼 크기 불일치 수정
type: develop
created: 2026-08-05
related:
  - .agent/plan/020-2026-08-04-editor-caret-fixes/plan.md
---

# Editor Image / Login Button Fixes

## 1. 로그인 다이얼로그 버튼 크기 불일치

**원인**: `app_theme.dart`에 `elevatedButtonTheme`(padding 24/14, Inter 15 w600)만
있고 `outlinedButtonTheme`가 없어 후자는 Material 기본값으로 그려졌다. 두 버튼을
`Expanded`로 나란히 두면 폭은 같지만 라벨 줄바꿈 지점이 달라져 "Open GitHub"만
2줄이 되고 높이가 어긋났다.

**수정**: `outlinedButtonTheme`를 같은 padding/shape/textStyle로 추가(라이트·다크가
`_buildTheme` 하나를 공유). 다이얼로그의 두 라벨은 `maxLines: 1`로 묶어 줄바꿈
자체를 차단.

## 2. 이미지 붙여넣기 후 캐럿이 한참 아래

**원인**: 문서 끝에 삽입할 때 개행을 하나만 붙여 `<img ...>\n`로 끝났다. 그러면
태그 줄이 마지막 실제 줄이 되고, 뒤따르는 고스트 줄(마지막 빈 줄)이 그 줄의 최대
글리프 — 이미지 높이만큼 예약된 글리프 — 를 물려받아 이미지 높이만큼 커진다.
TextPainter 실측: `tag+\n`은 문단 높이 624(=312×2)에 마지막 줄 캐럿 y 528,
`tag+\n\n`은 360에 정상. 글자를 하나 치면 그 줄이 본문 스타일이 되어 캐럿이
제자리로 올라오는 증상과 정확히 일치한다.

**수정**: `_insertImageBlock`의 `after.isEmpty` 분기를 `'\n\n'`으로 바꿔 빈 줄을
하나 확보한다.

**한계**: 이미 `<img>\n`로 끝나는 기존 노트는 그대로다(엔터 한 번으로 해소).
고스트 줄 높이는 SkParagraph가 직전 줄의 최대 스타일로 정하므로 컨트롤러의
스타일링만으로는 막을 수 없다.

## 3. 리사이즈 중 아래 본문이 안 밀림

**원인**: 드래그 미리보기가 `InlineImageView`의 로컬 state(`_dragWidth`)에만
있었다. 줄 높이 예약은 마크다운 태그의 width/height로 계산되므로 드롭 전까지
그대로고, 오버레이 자식은 델리게이트가 준 tight constraint 안에서 내부 Container만
커져 오버플로우로 그려졌다. 그래서 늘릴 때는 아래가 안 밀리다가 드롭하는 순간
한 번에 밀렸다(줄일 때는 이미지만 작아져 정상처럼 보였다).

**수정**: 미리보기 state를 없애고 드래그 중 매 프레임 태그를 갱신한다. 표시 크기와
예약이 같은 값에서 나오므로 항상 붙어 있다. 드래그 시작 시 종횡비를 캡처해
매 프레임 반올림으로 비율이 드리프트하는 것을 막고, `_resizeImage`는 줄 끝을
현재 텍스트에서 다시 찾아 stale range 교체를 피한다.

## 4. 반복 리사이즈 중 강제종료

**재현 실패**. 위젯 테스트로 스크롤·큰 이미지·반복 드래그를 돌렸지만 예외가 나지
않았고, `~/Library/Logs/DiagnosticReports`에도 simsync 크래시 리포트가 없었다.
따라서 원인을 확정했다고 말할 수 없다.

다만 확인된 위험 요소는 제거했다. 줄 높이 예약은 이미지 높이를 그대로 글리프
fontSize로 환산하는데, 폭 상한(1200)만 있고 높이 상한이 없어 세로로 긴 이미지가
`200x1000 → 1200x6000`(fontSize 약 4600)까지 커지는 것을 실측했다. `maxHeight`
1200을 추가해 그 영역을 만들지 않는다(같은 조건에서 240x1200으로 멈춘다).
0으로 나누기 가드도 함께 넣었다.

## 검증 (5회)

1. `flutter analyze` clean + 전체 494개 통과.
2. 전체 스위트 2회 반복 — 플레이키 없음. (`test()`에서 테마를 만들면 GoogleFonts
   fetch가 테스트 종료 후 터져 스위트를 깨뜨리는 문제를 발견해 `testWidgets`로 전환.)
3. 수정별 무력화 검증: outlinedButtonTheme 제거 / 삽입 빈 줄 되돌림 / 높이 상한
   제거 / 드래그 실시간 반영 차단 — 각각 대응 테스트가 실패함을 확인.
4. `flutter analyze` + 전체 테스트 + `flutter build macos --release` 성공.
5. 통합 디버그 빌드 + 전체 테스트 최종 재실행.

테스트로 잡히지 않는 것도 기록한다: `_aspect`의 0 나누기 가드는 width가 0인 태그가
폭 0짜리 Stack이 되어 핸들이 hit test 밖으로 나가므로 드래그를 시작할 수 없다 —
회귀 테스트 없이 한 줄 방어로만 남겼다.
