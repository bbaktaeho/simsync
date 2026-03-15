---
title: Search Foundation Implementation
description: Stage 2 search foundation 상세 구현 계획
type: plan
created: 2026-03-13
---

# Search Foundation Implementation

## Goal

- local note와 synced note 전체를 대상으로 검색 가능한 read model을 만든다.
- full-text, tag, date range filter를 같은 검색 흐름에서 처리한다.
- 검색 결과를 기존 sidebar note list에 통합해 별도 화면 없이 탐색할 수 있게 한다.

## Files

- Create: `desktop/lib/search/note_search_query.dart`
- Create: `desktop/lib/search/note_search_index.dart`
- Create: `desktop/lib/widgets/note_search_section.dart`
- Create: `desktop/test/search/note_search_index_test.dart`
- Modify: `desktop/lib/storage/note_storage.dart`
- Modify: `desktop/lib/storage/github/github_note_storage.dart`
- Modify: `desktop/lib/storage/local/local_note_storage.dart`
- Modify: `desktop/lib/screens/document_screen.dart`
- Modify: `desktop/lib/widgets/note_list_section.dart`

## Implementation Notes

- 첫 단계는 외부 search engine 없이 `in-memory index`로 간다.
- index entry는 note의 `title`, `content`, `tags`, `noteDate`, `storageType`만 정규화해서 보관한다.
- 검색어가 비어 있고 filter가 없으면 기존 selected-date note list 동작을 유지한다.
- tag filter는 exact match, text search는 case-insensitive substring match로 시작한다.
- date range는 inclusive range로 처리한다.
- 검색 index는 앱 진입 후 필요 시 전체 스캔으로 구축하고, note create/update/delete 시 증분 갱신한다.
