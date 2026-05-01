---
title: Token Mapping
description: DESIGN.md ↔ Flutter ThemeExtension 매핑표
type: plan
created: 2026-05-01
status: draft
related:
  - DESIGN.md
  - .agent/plan/001-2026-05-01-design-system-refresh/plan.md
---

# Token Mapping

> DESIGN.md (Notion-inspired)의 디자인 토큰을 Flutter `ThemeExtension`으로 매핑한다. 라이트 단일.

## Color (`AppColorsExtension`)

기존 필드명 최대한 유지. 누락된 역할(badge, focus, semantic accents)은 신설.

| 기존 필드 | 새 값 (DESIGN.md) | DESIGN.md 출처 |
|----------|------------------|---------------|
| `scaffold` | `#ffffff` | Pure White (page background) |
| `surface` | `#ffffff` | Card 표면 |
| `surfaceLight` | `#f6f5f4` | Warm White (alt section bg) |
| `surfaceHover` | `rgba(0,0,0,0.05)` | Secondary button bg |
| `border` | `rgba(0,0,0,0.1)` | Whisper border |
| `borderSubtle` | `rgba(0,0,0,0.06)` | 더 약한 분리 |
| `accent` | `#0075de` | Notion Blue |
| `accentMuted` | `#005bab` | Active Blue (pressed) |
| `accentSubtle` | `#f2f9ff` | Badge Blue Bg |
| `textPrimary` | `rgba(0,0,0,0.95)` | Notion Black |
| `textSecondary` | `#615d59` | Warm Gray 500 |
| `textMuted` | `#a39e98` | Warm Gray 300 |
| `textOnAccent` | `#ffffff` | Button text on blue |
| `error` | `#dd5b00` | Orange (warning/attention) |
| `success` | `#1aae39` | Green |
| `calendarToday` | `#0075de` | Notion Blue |
| `calendarDot` | `#0075de` | Notion Blue |
| `calendarSelected` | `#f2f9ff` | Badge Blue Bg (subtle) |
| `localAccent` | `#dd5b00` | Orange (현재 로컬 노트 강조 의미와 호환) |

### 추가 신설 필드

| 새 필드 | 값 | 용도 |
|--------|---|------|
| `focus` | `#097fe8` | Focus ring (DESIGN.md 8.1) |
| `badgeText` | `#097fe8` | Pill badge text (#f2f9ff 위) |
| `linkLight` | `#62aef0` | 어두운 배경 위 링크 (현재 미사용일 가능성) |
| `highlight` | `#fde68a` | 검색 결과 하이라이트 (search_results_widget.dart 기존 색 그대로 유지) |
| `shadowTint` | `Color(0x0A000000)` | shadow의 base tint, 다층 BoxShadow에서 opacity 가산 |

> `dark` static은 PR1에서 **삭제**.

## Spacing (`AppDimensions`)

DESIGN.md 8px base + 비-rigid 스케일을 단순화해 매핑. 기존 명칭 유지.

| 기존 | 기존 값 | 새 값 | DESIGN.md 매핑 |
|------|--------|------|---------------|
| `spacingXs` | 4 | **4** | base/2 |
| `spacingSm` | 8 | **8** | base |
| `spacingMd` | 12 | **12** | base+0.5 |
| `spacingLg` | 16 | **16** | 2×base |
| `spacingXl` | 24 | **24** | 3×base |
| `spacingXxl` | 32 | **32** | 4×base |

추가:

| 새 토큰 | 값 | 용도 |
|--------|---|------|
| `spacingXxxl` | 48 | section 간 여백 (mobile) |
| `spacingHero` | 80 | section 간 여백 (desktop) |

## Border Radius (`AppDimensions`)

DESIGN.md 5단계 + pill + circle 매핑. 기존 명칭 정리.

| 기존 → 새 | 값 | DESIGN.md |
|----------|----|-----------|
| `radiusMicro` (신설) | 4 | Buttons, inputs, functional |
| `radiusSubtle` (신설) | 5 | Links, list items, menu items |
| `borderRadiusSm` → `radiusStandard` | 8 | Small cards, containers |
| `borderRadius` → `radiusComfortable` | 12 | Standard cards, feature containers |
| `borderRadiusLg` → `radiusLarge` | 16 | Hero cards, featured |
| `radiusPill` (신설) | 9999 | Badges, pills |
| `radiusCircle` (신설) | (BoxShape.circle 사용) | Avatars, tabs |

> 기존 이름(`borderRadiusSm`, `borderRadius`, `borderRadiusLg`)은 **호환을 위해 deprecated alias로 한 단계 유지** 후 PR2에서 제거. 또는 PR1에서 `find/replace`로 일괄 교체. (04 문서에서 결정)

## Shadow (`AppShadows` 신설)

DESIGN.md의 multi-layer 스택을 Flutter `BoxShadow` 리스트로 정의.

```dart
abstract final class AppShadows {
  /// Whisper border 대체용은 `Border.all(color: c.border)` 로 직접 사용.

  /// Soft Card (Level 2) — 4-layer
  static const card = <BoxShadow>[
    BoxShadow(color: Color(0x0A000000), offset: Offset(0,4), blurRadius: 18),
    BoxShadow(color: Color(0x07000000), offset: Offset(0,2), blurRadius: 7.85),
    BoxShadow(color: Color(0x05000000), offset: Offset(0,0.8), blurRadius: 2.93),
    BoxShadow(color: Color(0x03000000), offset: Offset(0,0.18), blurRadius: 1.04),
  ];

  /// Deep Card (Level 3) — 5-layer
  static const deep = <BoxShadow>[
    BoxShadow(color: Color(0x03000000), offset: Offset(0,1), blurRadius: 3),
    BoxShadow(color: Color(0x05000000), offset: Offset(0,3), blurRadius: 7),
    BoxShadow(color: Color(0x05000000), offset: Offset(0,7), blurRadius: 15),
    BoxShadow(color: Color(0x0A000000), offset: Offset(0,14), blurRadius: 28),
    BoxShadow(color: Color(0x0D000000), offset: Offset(0,23), blurRadius: 52),
  ];
}
```

(opacity 변환: 0.04≈0x0A, 0.027≈0x07, 0.02≈0x05, 0.01≈0x03, 0.05≈0x0D — 정확 값은 PR1 구현 시 확인)

## Typography

별도 문서: [03-typography-and-font.md](03-typography-and-font.md).

## 적용 우선순위 (코드 변경 순서)

1. `AppColorsExtension.light` 새 팔레트로 교체 (`dark` 삭제)
2. `AppDimensions`에 새 radius/spacing 토큰 추가 (기존은 일단 유지)
3. `AppShadows` 신설
4. `app_theme.dart`의 `inputDecorationTheme`/`elevatedButtonTheme`/`textButtonTheme`을 새 토큰 참조로 교체 (radius 4→`radiusMicro` 등)
5. `main.dart`에서 다크 모드 제거
