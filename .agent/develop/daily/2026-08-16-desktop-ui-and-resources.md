---
title: Desktop UI Fixes / Resource Review
description: 리뷰 텍스트 대비, 설정 완료 버튼, 검색창 정렬·테두리, 동기화 폴링 조건부 요청
type: develop
created: 2026-08-16
---

# Desktop UI Fixes / Resource Review

소유자가 짚은 것들을 근거를 잡아 고쳤다. 추측으로 고친 것은 없다.

## 1. 위클리/먼슬리 텍스트가 안 읽힘 — 원인은 대비

처음엔 "다크 모드에서 마크다운 슬롯이 기본 검정으로 떨어진다"고 의심했는데,
**재현 테스트로 확인하니 아니었다**(flutter_markdown은 미지정 슬롯을
DefaultTextStyle로 떨어뜨린다). 팔레트 대비를 전부 계산해서 진짜 원인을 찾았다:

| 조합 | 대비 |
|------|------|
| textMuted on surface (light) | **2.66:1** |
| textMuted on surfaceLight (light) | **2.44:1** |
| textSecondary on surface (light) | 5.5:1 |

WCAG AA는 4.5:1이다. `textMuted`(#a39e98)는 DESIGN.md에서 placeholder/disabled용
으로 규정된 색인데, 위클리/먼슬리 패널이 **읽어야 하는 텍스트**(안내 문구,
노트 수, 날짜, 시각, 빈 상태 설명)에 쓰고 있었다.

→ 본문 성격의 텍스트를 `textSecondary`로 올렸다. 아이콘·장식에는 `textMuted`를
그대로 뒀다. 팔레트 토큰 자체는 건드리지 않았다(DESIGN.md에 값이 못 박혀 있다).
`text_contrast_test.dart`로 라이트/다크 모두 4.5:1 이상을 강제한다.

덤으로 마크다운 스타일시트를 `MarkdownStyleSheet.fromTheme(...).copyWith(...)`
기반 공용 함수로 바꿨다. 위클리 리뷰만 자체 sparse 스타일시트를 들고 있어
미리보기와 다르게 보이던 것도 사라졌다.

## 2. 설정의 Done 버튼

사이드바 하단에 회색 텍스트 버튼으로 있었다. 바로 위 "JSON으로 편집"(보조 동작)과
스타일이 같아 무엇이 주 동작인지 읽히지 않았고, 라벨만 영어였다.
→ 폭 전체를 쓰는 `FilledButton` "완료"로 바꿨다. 보조 동작은 텍스트 버튼 그대로.

## 3. 검색창

- **힌트가 세로 중앙에서 7px 아래**였다. 원인은 `isCollapsed: true` — 실험으로
  변종 4개를 재보니 isCollapsed는 내용을 박스 위쪽에 붙인다(6.5px 편차).
  `isDense + contentPadding 0 + filled false`로 바꾸니 0.5px 이내.
- **테두리 제거**. 채운 배경만으로 충분하다. 포커스일 때만 액센트 테두리를 그려
  DESIGN.md §8(포커스 표시)은 지킨다.
- 두 가지 모두 테스트로 못 박았다(`note_search_section_align_test.dart`).

### 검색창 테두리 — 한 번 더

바깥 컨테이너의 테두리를 지웠는데도 **입력칸 안쪽에 테두리가 한 겹 남아 있었다**
(소유자 스크린샷으로 확인). 원인은 테마다: `InputDecorationTheme`이 `border`뿐
아니라 `enabledBorder`/`focusedBorder`와 `filled`까지 준다. 호출부에서 `border`만
`InputBorder.none`으로 두면 나머지가 이긴다.

같은 함정이 3곳 더 있었다 — 표 셀 인라인 편집, JSON 다이얼로그, 검색 필터의 날짜
입력. 반복되는 실수라 `bareInputDecoration` 프리셋을 테마에 두고 네 곳 모두
거기서 가져다 쓰게 했다. 테스트는 데코레이션의 6개 테두리 슬롯이 전부 none인지
확인한다.

## 4. 리소스 / 외부 요청

측정 결과:

- **동기화 폴링이 5초마다 GitHub 커밋 API를 친다** — 하루 약 1.7만 요청. 응답을
  매번 통째로 받고 rate limit도 그대로 깎였다.
  → **ETag 조건부 요청**(`If-None-Match`)을 추가했다. 변경이 없으면 304 + 빈 본문이고
  **GitHub은 304를 rate limit에서 차감하지 않는다**. 동작은 그대로다(304면 알던
  sha 유지, 변경 콜백도 울리지 않는다). 테스트로 헤더 전송과 304 처리를 검증.
- **검색은 문제 없다**: 인덱스는 메모리의 `_allNotes`로만 재구축하고 호출 지점도
  하나다. 동기화 틱마다 `listAllNotes`를 다시 부르지 않는다.
- **GoogleFonts는 런타임 다운로드다.** pubspec에 번들 폰트가 없어 Inter/JetBrains
  Mono를 첫 실행 때 fonts.gstatic.com에서 받아 캐시한다. 설치당 1회라 상시 비용은
  아니지만, 오프라인 첫 실행에서는 시스템 폰트로 대체돼 렌더가 달라진다.
  → 폰트 파일을 assets로 번들하면 외부 요청이 0이 되고 렌더도 결정적이 된다.
  바이너리를 리포에 넣는 결정이라 이번 변경에는 포함하지 않았다.

## 검증

`flutter analyze` clean, 537개 통과(신규 6개: 대비 4, 검색창 정렬/테두리 2,
ETag 1 — 중복 제외). 디버그 빌드 실행해 예외 0건, 검색창은 실제 화면으로 확인했다.
위클리 패널은 클릭이 필요해 육안 확인 대신 대비 수치와 테스트로 검증했다.
