---
title: Memo Tab Restore (Desktop)
description: 좌측 사이드바 노트 리스트에 daily | memo 탭 복원. frontmatter is_memo 필드로 영속화.
type: develop
created: 2026-05-02
status: active
related:
  - .agent/plan/006-2026-05-02-memo-tab-restore/plan.md
---

# Memo Tab Restore — 개발 일지

## 배경

`feat/memo-and-storage-refactor` 브랜치(commit `61cff5e`, 2026-03-19)에서 만들었던 메모 탭이 develop/main 에 머지되지 않은 채 사라져 있었다. 사용자는 "예전에 만들어뒀던 메모용 탭이 사라졌다"고 인식.

원본 커밋은 메모 + local-first git clone 리팩토링이 묶여 있었으나, 현재 아키텍처(Contents API + persistent cache 기반)와 안 맞으므로 **메모 부분만** 가져왔다.

## 구현 개요

### 데이터 모델
- `Note.isMemo: bool` (default `false`) 필드 추가 — desktop + mobile 동일
- frontmatter `is_memo: <bool>` 한 줄 추가 (`is_default` 다음)
- `parseNote` 는 `is_memo` 누락된 markdown 을 false 로 처리 → 기존 노트 무영향

### Storage 호환
- `desktop/storage/github/github_note_storage.dart` (serialize + parse)
- `desktop/storage/local/local_note_storage.dart` (parser 결과 그대로 전달)
- `desktop/services/note_service.dart` (legacy local FS 경로용 자체 ser/de)
- `mobile/storage/...` 도 동일하게 round-trip 지원 (UI 변경 없음, 데이터만)

### UI
- `NoteListSection` 헤더 직후에 `daily | memo` 탭 바 추가 (active underline 강조)
- 우클릭 컨텍스트 메뉴: 현재 위치/탭에 따라 "메모로 이동" / "daily로 이동" + 기존 "삭제"
- `_buildEmptyState` 메모 탭 카피 분기 ("No memos yet / Right-click a daily note to move it here")

### DocumentScreen 흐름
- `_memoTabActive` state, `_memoNotes` getter (`isMemo == true`, `updatedAt` desc)
- `_visibleNotes` 우선순위: 검색 > memo 탭 > daily (`_notesForSelectedDate`)
- `_notesForSelectedDate` 가 이제 `isMemo == true` 노트 제외
- 탭 전환 시 검색을 클리어하고 `_currentPage = 0`, weekly view 끔
- 날짜 선택/새 노트 생성 시 자동으로 daily 탭으로 복귀
- `_setMemoFlag(note, isMemo)`: `_canMutateNote` 가드 → `copyWith` → `saveNote` → state 갱신 + search index upsert

## 의식적으로 빠뜨린 것

- 모바일 메모 UI: 데이터 round-trip 만 보장. 별도 PR 로 분리 (사용자 요청은 desktop 한정)
- 메모 별도 디렉토리 분리: `notes/{YYYY-MM}/{DD}/` 그대로 두고 frontmatter flag 만으로 구분
- 키보드 단축키 (Cmd+1/2 등): 별도 작업
- `_datesWithNotes` 에서 memo 제외: dot 표시는 그대로 두는 게 자연스럽다고 판단

## 검증

- `flutter analyze`: desktop + mobile clean
- `flutter test`:
  - desktop 96 통과 / 1 실패 (`Changing local path immediately clears old local notes before new ones load` — develop 에서도 똑같이 실패하는 pre-existing 회귀, 본 PR 무관)
  - mobile 6/6 통과
- 신규 테스트:
  - `serializeNote → parseNote` `isMemo` round-trip
  - `is_memo` 누락 markdown → `isMemo == false` 기본값
  - DocumentScreen `daily | memo` 탭 토글이 노트 리스트 가시성을 정확히 분기

## 결정 로그

| 결정 | 근거 |
|------|------|
| memo 별도 디렉토리 X | 파일 경로 변경은 마이그레이션 부담 ↑. frontmatter flag 만으로 충분 |
| 검색 > 탭 우선순위 | search 활성 시 사용자는 전체 검색을 기대. tab 은 보조 navigation |
| 탭 전환 시 검색 클리어 | 사용자가 의도적으로 탭을 누르면 검색을 풀고 새 컨텍스트로 진입하는 게 자연스러움 |
| 새 노트는 항상 daily | memo 노트는 "이동" 액션으로만 생성. 기존 생성 흐름 단순 유지 |
| memo 탭에서 날짜 dot X 변경 | dot 는 "노트 있음" 만 의미. memo 도 노트라 dot 표시는 오히려 일관됨 |

## Out of scope (다음 PR 후보)

- 모바일 메모 탭 UI (long-press menu / editor popup)
- 키보드 단축키 (Cmd+1 daily, Cmd+2 memo)
- memo 노트 검색 결과 시각 구분 (배지 등)
