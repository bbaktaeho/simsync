---
title: Editor Checkbox / Tab Indent
description: 마크다운 에디터에 클릭 가능한 체크박스 렌더링과 리스트 Tab 들여쓰기 추가
type: develop
created: 2026-08-15
---

# Editor Checkbox / Tab Indent

데스크톱 에디터에 두 가지를 추가했다. 모바일은 범위 밖.

## 1. 체크박스 렌더링 + 클릭 토글

**전**: `- [x] done`이 원문 그대로 보였다 (마크 문자만 accent 색).

**후**: `[x]` 세 글자를 투명 처리해 **폭만 남기고**, 그 자리에 실제 체크박스
위젯을 겹쳐 그린다. 클릭하면 원문의 마크 문자(`x` ↔ 공백)가 토글된다.

**설계**: 기존 오버레이 하네스를 재사용했다. 인라인 테이블/이미지/details
chevron이 이미 "문자 범위에 고정된 위젯"을 `EditorOverlayLayoutDelegate`로
배치하고 있어서, 앵커 하나(`EditorOverlayAnchor.charBox` — 문자 범위 박스 안
중앙 정렬)만 추가하면 됐다. 델리게이트가 `RenderEditable.getBoxesForSelection`
으로 이번 프레임의 실제 좌표를 읽으므로 줌/스크롤/폰트가 바뀌어도 자리가
어긋나지 않는다.

대안으로 검토했다가 버린 것:
- `WidgetSpan`으로 치환 — placeholder가 1글자로 세어 `[ ]`(3글자)와 어긋난다.
  컨트롤러의 문자 보존 invariant가 깨져 캐럿이 desync된다.
- `TextSpan.recognizer` — `EditableText`는 span recognizer를 호출하지 않는다.
- 데코레이션 페인터로 그리기 — 그림과 히트 테스트가 따로 놀아 조용히 어긋난다.

세부:
- 판정 정규식은 `checkboxLineRe` 하나로 통일해 렌더러와 오버레이가 같은 줄을
  본다 (`markdown_editing.dart`).
- 캐럿이 그 줄에 있어도 원문을 노출하지 않는다. 체크박스는 문법 노이즈가 아니라
  구조 컨트롤이라 테이블/이미지와 같은 취급이다. 대괄호 안을 편집해 형식이
  깨지면 매칭이 풀려 원문이 다시 보인다(자가 복구).
- 토글은 1글자 → 1글자 교체라 캐럿/선택을 건드리지 않는다.
- `TextFieldTapRegion`으로 감싼다. 데스크톱 TextField는 자기 영역 밖 탭에서
  포커스를 놓기 때문에, 감싸지 않으면 체크만 눌러도 편집 중이던 캐럿이 사라진다.
- `_forwardEditorScroll`로 감싼다. 오버레이가 히트 테스트를 가로채면 그 12px
  위에서 휠/트랙패드 스크롤이 죽는다 (테이블/이미지와 같은 이유).
- 크기는 `_checkboxSize = 12`(본문 14px 기준 `[ ]` 폭)에 콘텐츠 줌을 곱한 값.
  폰트를 바꾸면 조정해야 하는 캘리브레이션 상수다.

## 2. 리스트 Tab / Shift+Tab 들여쓰기

리스트 줄에서 Tab을 누르면 캐럿이 줄 어디에 있든 줄 머리를 2칸 들여쓴다
(하위 목록). Shift+Tab은 한 단계 되돌린다. 리스트 줄이 아니면 `ignored`를 돌려
기본 Tab 동작(포커스 이동)을 그대로 남긴다.

- 계산은 `indentListSelection`(순수 함수, 서비스 계층)에 두고 패널은 키만
  가로챈다. 리스트 판정은 Enter 자동 이어쓰기와 같은 `_matchMarker`를 재사용해
  두 기능이 같은 줄을 리스트로 본다.
- 2칸인 이유: `- ` 항목의 콘텐츠 열과 맞고, 4칸을 넘지 않아 코드 블록이 되지
  않는다.
- 선택이 여러 줄에 걸치면 걸친 줄을 모두 처리한다. 다음 줄 머리에서 끝나는
  선택은 그 줄을 포함하지 않는다(에디터 관행).
- 키 가로채기는 기존 cmd+V 인터셉트와 같은 `Focus.onKeyEvent` 자리다. 이
  Focus가 앱 레벨 `Shortcuts`(Tab → NextFocusIntent)보다 포커스 체인에서
  깊어서 먼저 받는다.

## 검증

- `flutter analyze` clean, 전체 518개 통과.
- 서비스 단위 테스트: 체크박스 탐색(들여쓴 항목, 다른 불릿, fence 제외, 닫는
  대괄호 뒤 공백 요구), 들여쓰기(캐럿 보정, outdent 클램프, 다중 줄 선택,
  리스트 아님 → null).
- 위젯 테스트(`editor_panel_checkbox_test.dart`): 클릭 토글(양방향), 캐럿 불변,
  읽기 전용 무시, **그려진 체크박스 중심이 감춰진 `[x]` 중심과 1px 이내**,
  포커스 유지, 닫힌 details 안에서는 화면 밖, Tab/Shift+Tab 실제 키 이벤트 경로.
- 컨트롤러 테스트: 체크박스 줄을 문자 보존 invariant 입력에 추가, 대괄호가
  투명하되 폭은 남는지 확인.
- 무력화 검증: `TextFieldTapRegion` 제거 → 포커스 테스트 실패, charBox 배치에서
  `leftInset` 제거 → 위치 테스트 실패. 두 줄 다 테스트가 지키고 있다.

런타임(실제 앱)에서 눈으로 확인하지는 않았다. 위치·크기는 테스트로 수치
검증했지만 색/두께 같은 시각적 마감은 실행해서 봐야 한다.

## 검토에서 잘라낸 것 / 남긴 것

- 잘라냄: `listIndentUnit` 공개 → 파일 내부 전용이라 private. 토글 stale 가드
  3줄 → 1줄.
- 남김(이유 있음): 다중 줄 선택 들여쓰기(요청 밖이지만 표준 동작이고 테스트가
  있다), `_forwardEditorScroll` 래핑(없으면 체크박스 12px 위에서 스크롤이
  죽는다), `_checkboxSize` 상수(폰트 바뀌면 조정할 캘리브레이션 knob).
- 안 씀: Material `Checkbox` — 최소 크기/탭 타깃/스플래시가 12px 슬롯과 싸운다.
  `Transform.scale`로 우겨넣는 것보다 20줄짜리 Container가 짧다.

## 알려진 갭

위클리 리뷰 뷰(`markdown_preview.dart`)는 여전히 `- [ ]`를 원문으로 그린다.
읽기 전용 AI 출력이라 이번 범위에서 제외했다.
