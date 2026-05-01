---
title: PR1 — Design Foundation
description: 토큰 시스템 확장 + Inter 폰트 + Notion 색상 + 다크 모드 제거
type: plan
created: 2026-05-01
status: draft
related:
  - .agent/plan/001-2026-05-01-design-system-refresh/02-token-mapping.md
  - .agent/plan/001-2026-05-01-design-system-refresh/03-typography-and-font.md
---

# PR1 — Design Foundation

## 목표

새 디자인 토큰 시스템과 Notion 팔레트, Inter 폰트를 도입하고 다크 모드를 제거한다. **인라인 스타일은 건드리지 않는다** — 시각 변화는 "기존 토큰 사용 위젯에서 자동 반영되는 만큼"으로 한정.

## Branch

`feature/design-foundation` (develop에서 분기)

## Scope (변경 파일)

### desktop & mobile 동일 변경

| 파일 | 변경 |
|------|------|
| `desktop/lib/theme/app_colors.dart` | `light` 팔레트 Notion 매핑으로 교체. `dark` static 제거. 신설 필드 (`focus`, `badgeText`, `linkLight`, `highlight`, `shadowTint`) 추가 |
| `desktop/lib/theme/app_dimensions.dart` | radius 신설 (`radiusMicro`, `radiusSubtle`, `radiusStandard`, `radiusComfortable`, `radiusLarge`, `radiusPill`). 기존 (`borderRadiusSm/borderRadius/borderRadiusLg`)는 alias로 유지. spacing 신설 (`spacingXxxl=48`, `spacingHero=80`) |
| `desktop/lib/theme/app_shadows.dart` *(신설)* | `AppShadows.card`, `AppShadows.deep` (BoxShadow list) |
| `desktop/lib/theme/app_text_styles.dart` *(신설, 옵션)* | TextTheme 누락분 보완 |
| `desktop/lib/theme/app_theme.dart` | `buildDarkTheme()` 제거. `_buildTheme()`은 light 전용으로 단순화. `GoogleFonts.manropeTextTheme` → `GoogleFonts.interTextTheme`. TextTheme 슬롯을 03-typography-and-font 매핑대로 정의. `inputDecorationTheme`/`elevatedButtonTheme`/`textButtonTheme` radius를 새 토큰 사용으로 교체 |
| `desktop/lib/main.dart` | `_themeMode`/`themeMode`/`darkTheme:` 제거. `MaterialApp(theme: buildLightTheme())` 만 남김. 토글 호출처 제거 |
| `desktop/pubspec.yaml` | (옵션) Inter 정적 폰트 자산 추가 |
| `desktop/assets/fonts/Inter-*.ttf` | (옵션) 4개 weight 번들 |

> mobile/ 측도 동일 변경. 디렉토리만 `mobile/lib/theme/` `mobile/lib/main.dart` `mobile/pubspec.yaml`로 바뀜.

### 다크 모드 토글 UI 추가 제거 대상

settings_screen에 다크 토글 UI가 있을 가능성 — 실제 구현 시 grep으로 확인:
```bash
grep -rn "themeMode\|toggleTheme\|isDark\|brightness" desktop/lib/ mobile/lib/
```
발견된 모든 호출처에서 토글 위젯 + 호출 함수 제거.

## Out of Scope (PR1)

- 화면/위젯 코드의 인라인 `TextStyle`, `BorderRadius.circular`, `EdgeInsets`, `BoxShadow` 변경 → **PR2**
- 신규 컴포넌트 (badge widget, primary button widget 등) → **PR2 또는 별도**

## Checklist

### 구현
- [ ] `app_colors.dart` light 팔레트 교체 + `dark` 제거 + 신설 필드 추가
- [ ] `app_dimensions.dart` radius/spacing 토큰 추가
- [ ] `app_shadows.dart` 신설
- [ ] `app_theme.dart` Inter 적용, TextTheme 갱신, dark 분기 제거, 컴포넌트 테마 radius 갱신
- [ ] `main.dart` 다크 모드 상태/토글/`darkTheme:` 제거 (desktop + mobile)
- [ ] settings_screen 등 다크 토글 UI 호출처 제거
- [ ] `buildDarkTheme()` 함수 삭제
- [ ] (옵션) Inter `.ttf` 4개 번들 + pubspec 등록

### 검증
- [ ] `cd desktop && flutter analyze` clean
- [ ] `cd desktop && flutter test` 통과
- [ ] `cd mobile && flutter analyze` clean
- [ ] `cd mobile && flutter test` 통과
- [ ] `flutter run -d macos` 실행 후 사용자 시각 QA
- [ ] `flutter run` (Android emulator/device) 사용자 시각 QA
- [ ] golden test baseline 생성 — 핵심 화면 (login, document workspace, settings) 각 1개씩 (06-verification.md 참고)

### 기능 회귀 체크 (반드시 통과)
- [ ] OAuth 로그인 흐름 동일
- [ ] repo 선택 동일
- [ ] 노트 CRUD 동일
- [ ] 캘린더 탐색 동일
- [ ] 검색 동일
- [ ] 동기화 (push/pull) 동일
- [ ] 설정 변경 (다크 토글 제외) 동일

## Commit Plan

PR1 내에서도 의미 단위 커밋 분리 권장:

1. `feat(theme): swap to Notion light palette and add new tokens`
2. `feat(theme): switch font from Manrope to Inter via google_fonts`
3. `feat(theme): add multi-layer shadow tokens`
4. `feat: remove dark mode (light-only)`
5. (옵션) `chore: bundle Inter fonts as static assets`

## PR Description Skeleton

```
## Summary
- Apply Notion-inspired color palette to AppColorsExtension (light only)
- Switch font from Manrope to Inter (google_fonts)
- Add radius/spacing/shadow tokens per DESIGN.md
- Remove dark mode (DESIGN.md is light-only)

## Test plan
- [ ] flutter analyze clean (desktop, mobile)
- [ ] flutter test passing (desktop, mobile)
- [ ] Manual: OAuth → repo select → note CRUD → calendar → search → sync
- [ ] Visual QA on macOS desktop and Android device

## Out of scope
- Inline TextStyle/BorderRadius/EdgeInsets migration (PR2)
```
