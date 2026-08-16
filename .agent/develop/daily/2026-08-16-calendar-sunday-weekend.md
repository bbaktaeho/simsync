---
title: Calendar Sunday Start / Weekend Color
description: 사이드바 캘린더를 일요일 시작으로 바꾸고 토·일에 주말 색 적용
type: develop
created: 2026-08-16
---

# Calendar Sunday Start / Weekend Color

## 바꾼 것

- 사이드바 캘린더(`calendar_section.dart`)를 **일요일 시작**으로 전환.
  선행 칸 수는 `DateTime(y, m, 1).weekday % 7` (월=1..일=7이므로 일=0, 토=6).
  검색 필터의 미니 캘린더는 이미 일요일 시작이었다 — 두 캘린더가 서로 달랐던
  것을 맞춘 셈이다.
- 토·일에 **주말 색** 적용. 요일 헤더와 날짜 모두. 색은 새 토큰
  `calendarWeekend` (라이트 `#DD5B00` = DESIGN.md Orange, 다크는 명도 보정).
  인접 월의 주말은 같은 색을 흐리게 해서 "이번 달이 주인공" 규칙을 유지한다.
- 미니 캘린더는 일요일만 `c.error`(에러 색)로 칠하고 있었다 — 의미가 맞지 않아
  주말 토큰으로 교체하고 토요일도 포함했다.

## 안 건드린 것

위클리 리뷰의 주 범위(월~일)는 그대로 뒀다. AI 리뷰 프롬프트에 "이번 주(월~일)"가
박혀 있어 범위를 바꾸면 요약 결과의 의미가 달라진다. 캘린더 표시와는 별개 개념이다.

## 검증

`flutter analyze` clean, 528개 통과 (캘린더 테스트를 일요일 기준으로 갱신 +
주말 색 테스트 추가). 디버그 빌드로 실제 렌더 확인 — Su~Sa 순서, 토·일 주황.
