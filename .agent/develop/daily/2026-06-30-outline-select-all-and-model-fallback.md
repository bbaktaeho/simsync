---
title: 1단계 리뷰 전체 선택 + 2단계 모델 폴백 개발 일지
description: 위클리/먼슬리 stage-1 체크리스트 전체 선택/해제 추가 + stage-2 리뷰 모델 미존재 시 default 폴백
type: develop
created: 2026-06-30
---

# 1단계 리뷰 전체 선택 + 2단계 모델 폴백

## 작업 범위 (desktop only)

기능 1건 + 버그 1건.

## 기능: stage-1 체크리스트 전체 선택/해제

- 요구: 위클리/먼슬리 1단계(핵심 정리) 리뷰에서 체크박스를 한 번에 전체 체크.
- 구현:
  - `services/review_outline.dart`: 순수 헬퍼 `setAllOutlineItems(outline, checked)`(모든 체크박스 라인 set, prose는 보존), `allItemsChecked(outline)` 추가. 기존 `toggleOutlineItem` 패턴과 동일.
  - `screens/document_screen.dart`: `_onToggleAllWeeklyOutlineItems(bool)`, `_onToggleAllMonthlyOutlineItems(bool)` 추가 — 단일 toggle 핸들러와 같은 영속화 경로(`setXxxOutlineContent` + `saveXxxOutline`)를 사용.
  - `widgets/weekly_view_panel.dart`: `WeeklyViewPanel`/`MonthlyViewPanel` → `_TwoStageReviewSection` → `_OutlineChecklist`로 `onToggleAll` 콜백을 연결. 체크리스트 우상단에 "전체 선택"/"전체 해제" 인라인 링크(accent) 추가. 모두 체크되어 있으면 "전체 해제", 아니면 "전체 선택"으로 토글.
- 결정: dead-end를 막기 위해 단순 체크-only가 아니라 전체 선택 ↔ 전체 해제 토글로 구현(단일 컨트롤). 개별 항목 toggle은 그대로 유지.
- 테스트: `test/services/review_outline_test.dart`에 `setAllOutlineItems`/`allItemsChecked` 케이스 추가.

## 버그: 2단계 최종 리뷰 모델 미존재 시 오류

- 근본 원인: stage-2는 `settings.anthropicModel`을 사용. 빈 값은 이미 전 경로에서 default로 폴백되지만, 사용자가 설정한 모델 id가 존재하지 않거나(오타·구버전 default·sync import) 서버가 거부하면 Anthropic API가 404 `not_found_error`를 반환 → 그대로 에러로 표면화되어 2단계가 실패.
- 수정(`services/anthropic_api_service.dart`):
  - `AnthropicApiException`에 `modelUnavailable` 플래그 추가.
  - 요청 로직을 `_generate(...)`로 분리하고, `_isModelError(response)`로 모델 미존재 오류(404/`not_found_error`/메시지에 "model")를 식별.
  - `summarizeWeek`는 설정 모델로 먼저 시도하고, 모델 미존재 오류이면서 시도 모델이 default가 아닐 때만 default 모델로 1회 폴백. 유효한 모델은 그대로 존중(고정 모델 강제 아님), 무효일 때만 교체. 무한 재시도 없음.
- 적용 범위: 위클리/먼슬리 stage-1·stage-2 모두 API provider 경로에서 자동 적용. CLI provider는 별도 변경 없음(빈 모델은 `--model` 생략).
- 투명성: 폴백이 조용히 일어나는 문제를 보완하기 위해 `summarizeWeek`에 `onModelFallback(requested, used)` 콜백 추가. 폴백이 실제로 성공했을 때만 호출되며, `document_screen._onModelFallback`이 mounted 가드 후 SnackBar로 "AI 모델 'X'를 사용할 수 없어 기본 모델 'Y'로 생성했습니다"를 1회 노출. 첫 시도 성공 시에는 호출되지 않음.
- 테스트: 무효 모델 → default 폴백 성공(+콜백 1회 호출) / 첫 시도 성공 시 콜백 미호출 / default가 무효일 때 재시도 안 함 / 비-모델 오류(401)는 재시도 안 함 케이스 추가.

## 검증

- `flutter analyze`: clean
- `flutter test`: 320 passed

## 후속 관찰 (미수정)

- `screens/settings_screen.dart` 모델 안내 문구가 "기본값은 claude-opus-4-8"라고 하지만 실제 `defaultAnthropicModel`은 `claude-sonnet-4-6`로 불일치. 이번 범위 밖이라 변경하지 않음.
