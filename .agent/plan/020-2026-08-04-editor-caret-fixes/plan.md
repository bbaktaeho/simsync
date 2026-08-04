---
title: Editor Caret Fixes (Trailing Space / Image Insert)
description: 헤더 작성 중 스페이스 후 캐럿 정지, 이미지 붙여넣기 후 캐럿 하단 표류 버그 수정
type: plan
created: 2026-08-04
status: active
---

# Editor Caret Fixes

## Problems

1. 헤더 작성 중 스페이스바를 누르면 캐럿이 띄어쓴 뒤로 가지 않고 제자리에 남는
   경우가 있다.
2. 이미지 붙여넣기 후 캐럿이 마크다운에서 한참 아래(이미지 밴드 하단)에 그려진다.
   이미지 크기를 줄여도 여전히 어긋난다.

## Root Causes (probe로 재현·확정)

1. **Trailing space + run 경계**: SkParagraph는 줄 끝 공백 뒤 캐럿을 계산할 때,
   그 공백과 뒤따르는 `\n`이 **fontSize가 다른 텍스트 run**으로 갈리면 공백의
   전진을 무시한다 (색 차이는 무관 — S1~S6 TextPainter 실험). 컨트롤러가 모든
   `\n`을 base 스타일로 스타일링하므로, content가 base가 아닌 줄(헤더 H1~H6,
   인용문 italic, 코드 mono 등)은 항상 이 경계가 생긴다. 마지막 줄(문서 끝,
   `\n` 없음)에서는 발생하지 않아 "가끔"으로 보였다 — 아래에 내용이 있는 줄을
   편집할 때만 재현.
2. **이미지 삽입 캐럿 위치**: `_insertImageBlock`이 캐럿을 `<img>` 태그 줄 끝에
   둔다. 태그 줄의 라인 박스는 (이미지 높이 + 여백)으로 예약되어 있어 캐럿이
   밴드 하단(base라인 근처, probe 실측 300px 이미지에서 top 200.7px)에 그려진다.
   리사이즈해도 밴드에 비례해 어긋난 채로 남고, 그대로 타이핑하면 태그 줄이
   깨진다.

## Fix

1. `markdown_editing_controller.dart` `buildTextSpan`: **활성 줄이 trailing
   whitespace로 끝나면** 그 줄의 `\n` span에 줄 마지막 span과 같은 스타일을
   물려줘 run 경계를 없앤다. 비활성 줄과 접힘(collapse) 분기는 기존 그대로 —
   렌더 높이·접힘 동작에 영향 없음. 캐럿은 활성 줄에만 그려지므로 이 범위로
   충분하다.
2. `editor_panel.dart` `_insertImageBlock`: 삽입 캐럿을 태그 뒤 개행 다음
   (`insertAt + prefix.length + tag.length + 1`)으로 옮긴다. 모든 분기에서 태그
   뒤에 개행이 보장된다 (suffix가 ''인 분기는 기존 `\n\n`을 재사용).

## Verification

1. 회귀 테스트: `editor_caret_test.dart`(헤더 trailing space 캐럿 전진),
   `editor_panel_image_test.dart`(첨부 후 selection이 태그 다음 줄).
2. `flutter analyze` clean + `flutter test` 전체 통과.
3. `flutter build macos --release` 성공.
