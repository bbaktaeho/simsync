---
title: Weekly Review Persistence + Background Generation
description: 위클리 리뷰를 notes/월/N주차에 저장·조회하고 생성을 백그라운드화 (Phase 2)
type: plan
created: 2026-06-29
status: active
---

# Weekly Review Persistence (Phase 2)

## Goal

위클리 리뷰를 생성하면 `notes/{YYYY-MM}/{N}주차/weekly-review.md`에 로컬+GitHub
양쪽으로 저장하고, 기존 리뷰가 있으면 위클리 뷰 진입 시 로드해 표시한다. 생성은
화면 전환(위클리 뷰 닫기/다른 노트)에도 백그라운드로 계속 진행된다.

## Decisions (confirmed/proposed)

- **N주차**: 주 시작(월요일)이 속한 달의 `((weekStart.day - 1) ~/ 7) + 1`.
  월 경계를 넘는 주는 "월요일이 있는 달"로 단일 귀속.
- **경로**: `notes/{YYYY-MM}/{N}주차/weekly-review.md` (local + GitHub 동일).
- **리뷰 격리**: 리뷰는 frontmatter 없는 순수 마크다운 → `parseNote`가 null 반환
  (자연 격리). 추가로 GitHub `_listAllNotesFromTree`가 일자(DD) 디렉토리 패턴만
  Note로 인식하도록 필터(defense-in-depth, 불필요한 blob fetch도 방지).
- **백그라운드**: 생성 상태/실행을 `ReviewController`(ChangeNotifier)로 추출,
  `DocumentScreen` state가 소유 → 위클리 패널 unmount와 무관하게 생존.

## File structure

- `lib/services/review_paths.dart` — 경로/주차 계산 (순수 함수, 신규)
- `lib/services/review_service.dart` — 저장/조회 (storage 래퍼, 신규)
- `lib/services/review_controller.dart` — 백그라운드 생성 상태 (ChangeNotifier, 신규)
- `lib/storage/note_storage.dart` — `readTextFile`/`writeTextFile` 추가
- `lib/storage/github/github_note_storage.dart` — 구현 + 노트 목록 격리 필터
- `lib/storage/local/local_note_storage.dart` — 구현
- `lib/widgets/weekly_view_panel.dart` — controller 구독 방식으로 전환
- `lib/screens/document_screen.dart` — controller/service 통합, 진입 시 로드

## Tasks (TDD)

1. `review_paths` + 테스트 — weekOfMonth, weeklyReviewPath, weekLabel
2. `NoteStorage.read/writeTextFile` + 두 구현체 + GitHub 노트 격리 필터 + 테스트
3. `ReviewService`(save/load weekly) + 테스트
4. `ReviewController`(generating→done/error, 백그라운드 지속) + 테스트
5. `DocumentScreen` + `WeeklyViewPanel` 통합 + 위젯 테스트(백그라운드 지속·조회 표시)

## Out of scope

Phase 3(먼슬리)는 별도 plan/PR. `ReviewController`/`ReviewService`/`review_paths`를
monthly로 확장하고 주별 병렬→월별 종합(Claude Code)을 얹는다.
