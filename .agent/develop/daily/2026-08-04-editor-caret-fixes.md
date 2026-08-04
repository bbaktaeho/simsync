---
title: Editor Caret Fixes (Trailing Space / Image Insert)
description: 헤더 스페이스 후 캐럿 정지, 이미지 붙여넣기 후 캐럿 하단 표류 수정
type: develop
created: 2026-08-04
related:
  - .agent/plan/020-2026-08-04-editor-caret-fixes/plan.md
---

# Editor Caret Fixes

## Root Causes

1. **헤더 스페이스 캐럿 정지**: SkParagraph는 줄 끝 공백과 뒤따르는 `\n`이
   fontSize가 다른 텍스트 run으로 갈리면 그 공백의 캐럿 전진을 무시한다
   (TextPainter S1~S6 실험으로 확정 — 색 차이는 무관, fontSize 차이만 재현).
   컨트롤러가 모든 `\n`을 base로 스타일링해 헤더(H1~H6)/인용문/코드 줄은 항상
   이 run 경계가 생겼다. 문서 마지막 줄(개행 없음)에서는 정상이라 "가끔"으로
   보였다.
2. **이미지 삽입 캐럿**: `_insertImageBlock`이 캐럿을 태그 줄 끝에 둠 → 태그
   줄 라인 박스는 이미지 높이만큼 예약돼 캐럿이 밴드 하단에 그려짐 (300px
   이미지에서 top 200.7px 실측). 리사이즈해도 비례해서 어긋나고, 타이핑하면
   태그 줄이 깨짐.

## Fix

- `markdown_editing_controller.dart`: 활성 줄이 공백/탭으로 끝나면 그 줄의
  `\n` span에 줄 마지막 span의 스타일을 물려줘 run 경계를 제거. 비활성 줄과
  접힘 분기는 그대로 (렌더 높이 불변).
- `editor_panel.dart` `_insertImageBlock`: 삽입 캐럿을 태그 뒤 개행 다음으로
  이동 (모든 분기에서 개행 보장 — 기존 테스트 기대값으로 교차 확인).

## Verification (3회)

1. 회귀 테스트 2건 신규 (`editor_caret_test.dart`, `editor_panel_image_test.dart`)
   — 수정 제거 시 정확히 그 2건만 실패함을 확인 (테스트 유효성 검증).
2. `flutter analyze` clean + 전체 테스트 487개 통과.
3. `flutter build macos --release` 성공.

## Notes

- mobile/에 복제된 에디터 기반 코드에는 같은 패턴이 있을 수 있다 — 모바일
  포팅 작업에서 반영 필요.
