---
title: PR2 — Inline → Token Migration
description: 712곳 인라인 스타일을 토큰 참조로 교체하며 DESIGN.md 디테일 적용
type: plan
created: 2026-05-01
status: draft
related:
  - .agent/plan/001-2026-05-01-design-system-refresh/02-token-mapping.md
  - .agent/plan/001-2026-05-01-design-system-refresh/04-pr1-foundation.md
---

# PR2 — Inline → Token Migration

## 목표

인라인 `TextStyle`/`BorderRadius`/`EdgeInsets`/`BoxShadow` 712곳을 PR1에서 도입한 토큰 참조로 교체한다. DESIGN.md의 디테일(typography hierarchy, radius scale, whisper border, multi-layer shadow, pill badge)을 화면별로 정확히 반영한다.

## Branch / PR 분할 전략

화면별 분리 권장 (회귀 격리). 권장 구조 — **사용자 검토 시 단일 vs 분할 선택**:

### 옵션 A: 단일 PR (1개)
- 모든 화면/위젯 한 번에. 리뷰 부담 큼, 회귀 시 롤백 단위가 큼.

### 옵션 B: 그룹별 PR (4개) ← 추천
| PR | 범위 |
|----|------|
| PR2a | **공통 위젯 라이브러리 신설** — `Buttons`/`Card`/`Badge`/`Input` 컴포넌트 (DESIGN.md 4번 섹션) |
| PR2b | **Desktop 화면 4개** — login, repo_selection, document, settings |
| PR2c | **Mobile 화면 7개** — login, repo_selection, home, calendar, editor, search, settings |
| PR2d | **마무리** — markdown_preview, editor_panel 등 공유 위젯, golden 회귀 픽스 |

### 옵션 C: 화면 단위 PR (11+개)
- 가장 안전, 가장 느림. 매 PR마다 리뷰/QA 사이클.

## 변경 패턴 (모든 PR2 공통)

### 1. Inline TextStyle → TextTheme
```diff
- Text('Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))
+ Text('Settings', style: Theme.of(context).textTheme.headlineSmall)
```

DESIGN.md hierarchy 매핑은 [03-typography-and-font.md](03-typography-and-font.md) 참고.

### 2. BorderRadius.circular(N) → 토큰
```diff
- borderRadius: BorderRadius.circular(8)
+ borderRadius: BorderRadius.circular(AppDimensions.radiusStandard)
```

매핑:
- `circular(4)` → `radiusMicro` (buttons, inputs)
- `circular(5)` → `radiusSubtle` (links, list items)
- `circular(8)` → `radiusStandard` (small cards)
- `circular(12)` → `radiusComfortable` (standard cards)
- `circular(16)` → `radiusLarge` (hero/featured)
- `circular(9999)` 또는 `StadiumBorder()` → `radiusPill` (badges)

### 3. EdgeInsets → spacing 토큰
```diff
- padding: EdgeInsets.all(16)
+ padding: EdgeInsets.all(AppDimensions.spacingLg)
```

`EdgeInsets.symmetric(horizontal: 24, vertical: 12)` → `EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl, vertical: AppDimensions.spacingMd)`.

### 4. BoxShadow → AppShadows
```diff
- boxShadow: [BoxShadow(color: ..., blurRadius: 8, offset: ...)]
+ boxShadow: AppShadows.card
```

### 5. Whisper border 적용 (cards/containers)
DESIGN.md: card는 `1px solid rgba(0,0,0,0.1)` border + multi-layer shadow.
```dart
Container(
  decoration: BoxDecoration(
    color: context.colors.surface,
    border: Border.all(color: context.colors.border, width: 1),
    borderRadius: BorderRadius.circular(AppDimensions.radiusComfortable),
    boxShadow: AppShadows.card,
  ),
  ...
)
```

### 6. Pill badge 적용
- 태그 chip, 상태 indicator 등이 대상
- `radiusPill` + `surfaceLight` 배경 + 12px 600 weight + 0.125 letter-spacing

## 화면별 변경 무게 (audit 기준)

| 화면 | typography | radius | total |
|------|-----------|--------|-------|
| desktop/screens/settings_screen.dart | 48 | 19 | 67 |
| mobile/screens/search_screen.dart | 37 | 15 | 52 |
| mobile/screens/calendar_screen.dart | 30 | 10 | 40 |
| mobile/screens/editor_screen.dart | 27 | 4 | 31 |
| mobile/widgets/markdown_preview.dart | 26 | — | 26 |
| desktop/screens/repo_selection_screen.dart | 24 | 17 | 41 |
| desktop/widgets/markdown_preview.dart | 23 | — | 23 |
| desktop/widgets/editor_panel.dart | 23 | — | 23 |
| (기타 11개 파일) | … | … | 합계 712 |

→ settings_screen / search_screen / calendar_screen이 가장 부담 큰 화면. 시간 안배 반영.

## DESIGN.md 디테일 적용 체크리스트 (각 화면별)

- [ ] 헤더 타이틀이 적절한 hierarchy (Section Heading / Sub-heading / Card Title)
- [ ] 본문이 16px weight 400 line-height 1.50
- [ ] 모든 카드/컨테이너에 whisper border + radius 12 + (필요 시) shadow card
- [ ] 모든 버튼이 radius 4 (Micro)
- [ ] 모든 입력이 radius 4 + `border: 1px solid rgba(0,0,0,0.1)`
- [ ] 태그/상태 chip이 pill (9999) + 12px 600 + 0.125 letter-spacing
- [ ] 캘린더 today/selected가 Notion Blue 또는 Badge Blue Bg
- [ ] focus ring (`#097fe8`)이 모든 interactive 요소에 적용
- [ ] section padding 16/24/32 단위 (8px base 비배수 회피)

## Out of Scope (PR2)

- 신규 화면
- 기능 변경
- 다크 모드 재도입

## Checklist (전체 PR2 종합)

### 구현
- [ ] (PR2a) 공통 컴포넌트 (`PrimaryButton`, `SecondaryButton`, `GhostButton`, `PillBadge`, `NotionCard`, `NotionInput`) 신설
- [ ] (PR2b) Desktop 4 화면 마이그레이션
- [ ] (PR2c) Mobile 7 화면 마이그레이션
- [ ] (PR2d) 공유 위젯 마이그레이션
- [ ] grep으로 인라인 잔재 확인 (감사 명령은 01-current-state-audit.md 참고)

### 검증 (각 PR마다)
- [ ] flutter analyze clean
- [ ] flutter test 통과
- [ ] golden test 회귀 없음 (PR1에서 baseline 생성)
- [ ] 사용자 수동 QA (06-verification.md 매트릭스)

### 종료 조건
- [ ] 인라인 `fontSize:` count = 0 (theme/ 외)
- [ ] 인라인 `BorderRadius.circular`/`Radius.circular` count = 0 (theme/ 외)
- [ ] 인라인 `BoxShadow` count = 0 (theme/ 외)
- [ ] 인라인 `EdgeInsets` 중 매직 넘버 사용처 = 0
- [ ] 모든 hardcoded `Color(0x...)` 제거 (theme/ 외)
