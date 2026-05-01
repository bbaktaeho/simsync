---
title: Design System Refresh (Notion-inspired)
description: DESIGN.md를 desktop/mobile Flutter 앱에 적용. 라이트 단일, Inter 폰트, 2단계 PR
type: plan
created: 2026-05-01
status: draft
related:
  - DESIGN.md
  - .agent/plan/001-2026-05-01-design-system-refresh/01-current-state-audit.md
  - .agent/plan/001-2026-05-01-design-system-refresh/02-token-mapping.md
  - .agent/plan/001-2026-05-01-design-system-refresh/03-typography-and-font.md
  - .agent/plan/001-2026-05-01-design-system-refresh/04-pr1-foundation.md
  - .agent/plan/001-2026-05-01-design-system-refresh/05-pr2-migration.md
  - .agent/plan/001-2026-05-01-design-system-refresh/06-verification.md
---

# Design System Refresh

## Goal

`DESIGN.md` (Notion-inspired)을 desktop/mobile Flutter 앱 전체에 적용한다. **기능은 변경하지 않는다** — 사용자 인터랙션, 화면 흐름, 데이터 모델 모두 그대로.

## Confirmed Decisions

| 항목 | 결정 |
|------|------|
| 다크 모드 | **제거** — 라이트 단일. `ThemeMode.light` 고정, 토글 UI 제거 |
| 폰트 | **Inter** (`google_fonts` 패키지로 동적 로드, 이미 의존성 있음) |
| 단계 분리 | **2단계 PR** (C 옵션) — 토큰/폰트/색 → 인라인 마이그레이션 |
| 검증 | `flutter analyze` + `flutter test` + golden test 신규 + 사용자 수동 QA |
| 다크 팔레트 | DESIGN.md에 명세 없으므로 정의하지 않음 |

## Why 2-stage PR (C 옵션)

Audit 결과 인라인 스타일 712곳 (typography 398 + radius 129 + spacing 185). 단일 PR로 일괄 수정 시 회귀 위험이 매우 크다. 단계 분리로:

- **PR1 (Foundation)** — 토큰 시스템 확장 + 색상/폰트/다크 제거. 시각 변화 = "현재 위젯이 새 토큰을 자동 반영한 만큼"만 (≈ 색상 톤 + 폰트). 화면 깨짐 없음.
- **PR2 (Migration)** — 인라인 스타일을 새 토큰 참조로 점진 교체하며 DESIGN.md 디테일(typography hierarchy, radius scale, spacing scale, whisper border, multi-layer shadow) 적용. 화면별 PR 분리도 가능.

## Out of Scope

- 신규 화면/컴포넌트
- 비즈니스 로직 변경
- 동기화/스토리지/검색 등 비-UI 모듈
- 다크 모드 재설계
- NotionInter 폰트 라이선스 협상

## High-level Steps (workflow.md 14단계 적용)

1. **계획 수립** — 이 디렉토리의 plan + 6개 상세 문서. (현재 단계)
2. **계획 검토** — 사용자 검토/승인.
3. **PR1 구현** — 04-pr1-foundation.md 따라 토큰/폰트/색/다크 제거.
4. **PR1 검토** (4–13단계) — flutter analyze, flutter test, golden baseline 생성, 사용자 시각 QA.
5. **PR1 커밋·PR** — `feat: design system foundation` (develop 대상).
6. **PR2 구현** — 05-pr2-migration.md 따라 화면별 인라인→토큰 전환.
7. **PR2 검토 + 커밋·PR** — golden 회귀 자동 감지, 수동 QA.

## Document Map

| 파일 | 내용 |
|------|------|
| [01-current-state-audit.md](01-current-state-audit.md) | grep 결과로 본 현재 코드 상태 (하드코딩 분포, 토큰 사용도) |
| [02-token-mapping.md](02-token-mapping.md) | DESIGN.md 토큰 ↔ Flutter ThemeExtension 매핑표 |
| [03-typography-and-font.md](03-typography-and-font.md) | Inter 적용 방식, TextTheme + `AppTextStyles` 정의 |
| [04-pr1-foundation.md](04-pr1-foundation.md) | PR1 변경 범위·체크리스트 |
| [05-pr2-migration.md](05-pr2-migration.md) | PR2 화면별 마이그레이션 계획 |
| [06-verification.md](06-verification.md) | 검증 전략 (analyze, test, golden, 수동 QA 매트릭스) |

## Risks & Mitigations

| 위험 | 완화 |
|------|------|
| PR2에서 712곳 변경 중 회귀 발생 | 화면별 분리, 각 화면마다 golden 추가 후 PR |
| `google_fonts` 런타임 다운로드 실패 시 시스템 폰트 fallback이 DESIGN.md와 차이 | PR1에서 fallback 명시 + 빌드 시 `pretendToBeOffline` 검증 |
| 다크모드 호출처(예: settings 토글) 잔존 | PR1 중 `themeMode\|darkTheme` grep으로 모든 호출처 제거 확인 |
| DESIGN.md에 없는 화면 요소 (예: calendar dot, tag chip) | PR2에서 case-by-case로 가장 가까운 DESIGN.md 토큰을 채택, plan 문서에 결정 기록 |

## Open Questions

- PR2 화면별 분리를 어디까지 쪼갤지 (한 PR에 화면 11개 vs 화면 단위 11 PR vs 그룹). 04/05 문서에서 제안 후 확정.
- Inter font OpenType features (`lnum`, `locl`)을 Flutter `TextStyle.fontFeatures`로 적용할지 (효과는 미세함, 우선순위 낮음).
