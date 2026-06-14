---
title: Current State Audit
description: 디자인 토큰 사용 현황과 하드코딩 분포 (grep 기반)
type: plan
created: 2026-05-01
status: draft
related:
  - .agent/plan/001-2026-05-01-design-system-refresh/plan.md
---

# Current State Audit

> 모든 수치는 2026-05-01 기준 grep 결과. 재실행 명령은 각 섹션 끝에 첨부.

## 요약

| 카테고리 | 토큰화 상태 | 인라인 개수 |
|---------|------------|-----------|
| Color | 양호 (169곳에서 `context.colors` 사용) | **5** (theme/ 외 하드코딩 `Color(0x...)`) |
| Typography | **부재** — `TextTheme` 정의는 있으나 위젯이 무시 | **398** (인라인 `fontSize:`/`fontWeight:`) |
| Border radius | **부재** — `AppDimensions.borderRadius` 등 정의는 있으나 미사용 | **129** (인라인 `BorderRadius.circular`/`Radius.circular`) |
| Spacing | **부재** — `AppDimensions.spacingXs..Xxl` 정의는 있으나 미사용 | **185** (인라인 `EdgeInsets.{all,symmetric,only,fromLTRB}`) |
| Shadow | 부재 | **6** (인라인 `BoxShadow`) |
| **합계** | — | **723곳** |

→ DESIGN.md 적용은 **723곳 마이그레이션 작업**이다. (PR2의 실제 무게)

## Color 하드코딩 5곳

```
desktop/lib/screens/login_screen.dart:103:           Color(0x20000000)   # shadow tint
desktop/lib/screens/repo_selection_screen.dart:245:  Color(0x20000000)   # shadow tint
mobile/lib/screens/login_screen.dart:107:            Color(0x20000000)
mobile/lib/screens/repo_selection_screen.dart:234:   Color(0x20000000)
mobile/lib/widgets/search_results_widget.dart:284:   Color(0xFFFDE68A)   # yellow highlight
```

→ 4곳은 shadow tint, 1곳은 검색 하이라이트. PR1에서 `context.colors.shadow` / `context.colors.highlight` 토큰으로 교체.

## Typography 인라인 분포 (상위 15)

| count | file |
|-------|------|
| 48 | desktop/lib/screens/settings_screen.dart |
| 37 | mobile/lib/screens/search_screen.dart |
| 30 | mobile/lib/screens/calendar_screen.dart |
| 27 | mobile/lib/screens/editor_screen.dart |
| 26 | mobile/lib/widgets/markdown_preview.dart |
| 24 | desktop/lib/screens/repo_selection_screen.dart |
| 23 | desktop/lib/widgets/markdown_preview.dart |
| 23 | desktop/lib/widgets/editor_panel.dart |
| 19 | mobile/lib/widgets/note_list_widget.dart |
| 19 | mobile/lib/screens/repo_selection_screen.dart |
| 19 | desktop/lib/widgets/note_list_section.dart |
| 18 | mobile/lib/screens/settings_screen.dart |
| 15 | desktop/lib/widgets/weekly_view_panel.dart |
| 14 | mobile/lib/widgets/search_results_widget.dart |
| 11 | desktop/lib/screens/document_screen.dart |

## Border Radius 인라인 분포 (상위 10)

| count | file |
|-------|------|
| 19 | desktop/lib/screens/settings_screen.dart |
| 17 | desktop/lib/screens/repo_selection_screen.dart |
| 15 | mobile/lib/screens/search_screen.dart |
| 14 | mobile/lib/screens/repo_selection_screen.dart |
| 10 | mobile/lib/screens/calendar_screen.dart |
| 9 | desktop/lib/widgets/note_list_section.dart |
| 5 | mobile/lib/widgets/note_list_widget.dart |
| 5 | desktop/lib/widgets/note_search_section.dart |
| 4 | mobile/lib/widgets/search_results_widget.dart |
| 4 | mobile/lib/screens/editor_screen.dart |

## Dark Mode 호출처

```
desktop/lib/main.dart:92    ThemeMode _themeMode = ThemeMode.light;
desktop/lib/main.dart:98    _themeMode = _themeMode == ThemeMode.dark ? ... : ...
desktop/lib/main.dart:110   darkTheme: buildDarkTheme(),
desktop/lib/main.dart:111   themeMode: _themeMode,
mobile/lib/main.dart:101    ThemeMode _themeMode = ThemeMode.light;
mobile/lib/main.dart:107    (toggle)
mobile/lib/main.dart:119    darkTheme: buildDarkTheme(),
mobile/lib/main.dart:120    themeMode: _themeMode,
```

→ PR1에서 다음 모두 제거: `_themeMode` 상태, 토글 호출처, `darkTheme:`, `buildDarkTheme()` 함수, `AppColorsExtension.dark` 정의.
→ Settings 화면에 다크 토글 UI가 있을 가능성 — PR1에서 grep으로 추가 확인 필요.

## 기존 토큰 사용 169곳

`context.colors.*` (또는 `AppColorsExtension`/`AppDimensionsExtension`) 패턴이 169곳에서 사용 중. 즉 **색상은 PR1에서 팔레트만 교체하면 자동 반영**.

## Reproduce

```bash
# 하드코딩 카운트
grep -rn "Color(0x" desktop/lib/ mobile/lib/ | grep -v "/theme/" | wc -l
grep -rn "BorderRadius\.circular\|Radius\.circular" desktop/lib/ mobile/lib/ | grep -v "/theme/" | wc -l
grep -rn "EdgeInsets\.\(all\|symmetric\|only\|fromLTRB\)" desktop/lib/ mobile/lib/ | grep -v "/theme/" | wc -l
grep -rn "fontSize:\|fontWeight:" desktop/lib/ mobile/lib/ | grep -v "/theme/" | wc -l
grep -rn "BoxShadow" desktop/lib/ mobile/lib/ | grep -v "/theme/" | wc -l

# 토큰 사용
grep -rn "context\.colors\|AppColorsExtension\|AppDimensions" desktop/lib/ mobile/lib/ | grep -v "/theme/" | wc -l

# 다크모드 호출처
grep -rn "themeMode\|darkTheme\|ThemeMode\.dark\|buildDarkTheme" desktop/lib/ mobile/lib/
```
