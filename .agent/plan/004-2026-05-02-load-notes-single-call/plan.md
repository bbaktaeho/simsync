---
title: Desktop _loadNotes Single-Call
description: 직렬 day-루프 listNotes 를 listAllNotes 한 번 호출로 통합. 검색 인덱스도 _allNotes 재사용.
type: plan
created: 2026-05-02
status: active
---

# Desktop `_loadNotes` Single-Call

## Problem

PR #21 (트리 캐시 + 병렬 blob fetch) 머지 후에도 desktop 첫 로딩이 **여전히 매우 느리다**.

원인: `document_screen.dart:175-258` `_loadNotes` 가 day 별로 `listNotes` 를 **직렬 await** 한다.
`listNotes` 안의 blob fetch 는 병렬화됐지만, day 끼리는 직렬이라 ~30 day batch RTT 가 누적.

## Mobile은 영향 없음

`mobile/lib/screens/calendar_screen.dart` 의 `_loadNotes` (L115) 는 `_selectedDate` 한 day만 fetch (lazy). 검색은 별도 `SearchScreen` 에서 `listAllNotes` 를 한 번에 빌드. 트리 캐시 위에서 충분히 빠르다.

→ **desktop only.**

## Confirmed Decisions

| 항목 | 결정 |
|------|------|
| 접근 | `_loadNotes` 가 storage / localStorage 각 `listAllNotes()` 한 번 호출 (`Future.wait` 동시 실행) |
| 검색 인덱스 | `_rebuildSearchIndex` 를 `_allNotes` 재사용으로 변경 (storage 두 번째 fetch 제거) |
| 캘린더 month 이동 | `_allNotes` 가 모든 month 노트를 담으므로 추가 fetch 불필요 |
| 메모리 | 1년 500노트 평균 1KB = ~500KB. 부담 없음 |
| dirty 보호 | 기존 merge logic 유지 |
| race protection | 기존 `_loadGeneration` 유지 |

## 비용 비교 (~150ms RTT, 한 달 30일/노트 30개 가정)

| 단계 | Before (PR #21) | After (옵션 A) |
|------|------|------|
| `_loadNotes` 트리 fetch | 2 RTT | 2 RTT |
| `_loadNotes` blob fetch | day 30 직렬 batch ≈ 30 RTT | ⌈30/10⌉ = 3 RTT (단일 batch) |
| `_rebuildSearchIndex` 추가 fetch | tree 2 RTT (캐시 hit이라 0) + listAllNotes 의 잔여 blob 0 (이미 캐시 hit) | 0 (in-memory 사용) |
| **합** | **~32 RTT ≈ 5초** | **~5 RTT ≈ 750ms** |

## Files Affected

- `desktop/lib/screens/document_screen.dart`
  - `_loadNotes`: month 별 직렬 루프 제거 → `listAllNotes()` 두 storage 동시 호출 (`Future.wait`)
  - `_rebuildSearchIndex`: storage 호출 제거 → `_searchIndex.replaceAll(_allNotes)`
- `desktop/test/screens/document_screen_test.dart` 또는 신규 test: `_FakeNoteStorage` 가 `listAllNotes` 만으로 노트를 노출해도 첫 화면이 정상 동작함을 검증

## Out of Scope

- mobile 첫 화면 변경
- Tarball / GraphQL 도입 (옵션 A 가 충분히 빠르면 보류, 부족하면 별도 PR)
- Lazy month-first (옵션 A 가 대안. 검색 인덱스 누락 위험 회피)

## Checklist

- [ ] desktop `_loadNotes` 단일 호출 리팩토링
- [ ] desktop `_rebuildSearchIndex` 메모리 재사용
- [ ] 테스트 (기존 `document_screen_test.dart` 회귀 + 신규 케이스)
- [ ] desktop `flutter analyze` + `flutter test` 회귀 없음
- [ ] mobile `flutter analyze` + `flutter test` 회귀 없음 (영향 없어야 함)
- [ ] PR 작성 + push
