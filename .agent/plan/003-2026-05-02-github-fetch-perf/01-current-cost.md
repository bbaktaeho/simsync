---
title: Current GitHub Fetch Cost
description: 현재 첫 로드/검색 인덱싱 시 발생하는 GitHub API 호출 패턴 정량 분석
type: plan
created: 2026-05-02
status: active
related:
  - .agent/plan/003-2026-05-02-github-fetch-perf/plan.md
---

# Current GitHub Fetch Cost

## 호출 흐름

### 첫 화면 진입 (`DocumentScreen._loadNotes`)

```dart
final dates = await _storage.listDates(currentMonth);   // 1
for (final date in dates) {
  final dayNotes = await _storage.listNotes(date);       // D
}
```

`GitHubNoteStorage`:
- `listDates(yearMonth)`: `_client.listDirectory('notes/YYYY-MM')` — 1 RTT (해당 월 안에 day dir 목록)
- `listNotes(date)`: `_client.listDirectory('notes/YYYY-MM/DD')` — 1 RTT, 그 후 각 .md 파일별로 `getFile(path)` — N RTT (sha 변경 안 된 파일은 캐시 사용)

### 검색 인덱싱 (`listAllNotes`)

```dart
final monthEntries = await _client.listDirectory('notes');   // 1
for (final entry in monthEntries) {
  final dates = await listDates(entry.name);                  // M
  for (final date in dates) {
    notes.addAll(await listNotes(date));                       // D × (1 + N)
  }
}
```

## 정량 추정

| 시나리오 | 호출 수 | 직렬 latency (~150ms/req) |
|----------|--------|---------------------------|
| 한 달 30일, 노트 30개 (첫 화면) | 1 + 30 + 30 = **61** | ~9초 |
| 6개월 누적 노트 200개 (검색 인덱싱) | 1 + 6 + 60 + 200 ≈ **267** | ~40초 |
| 1년 누적 노트 500개 (검색 인덱싱) | 1 + 12 + 200 + 500 ≈ **713** | ~107초 |

GitHub API 인증 rate limit: 5000/시간. 단 호출 수가 직접 한계는 아니지만 latency 누적이 사용자 경험을 망친다.

## 호출이 직렬인 이유

`for` 루프 안에서 `await` 한 번에 하나씩. Dart 동기 흐름. 다른 day 의 listing 또는 다른 file 의 콘텐츠 fetch 는 서로 독립이지만 병렬화 안 됨.

## 캐시 효과 (현재)

`_shaCache` / `_noteCache` 가 SHA 일치 시 `getFile` 을 스킵.
- 두 번째 listing 호출부터 콘텐츠 fetch 0회 (다만 listing GET 은 매번 발생 → SHA 비교용)
- 따라서 첫 로드 비용이 가장 크고, 이후 polling 사이에는 콘텐츠 fetch 거의 없음

문제는 **첫 로드** + **새 commit 감지 시 (변경된 파일 + 캐시 miss)**.

## Trees API 도입의 효과

| 항목 | 현재 | Trees + 병렬 |
|------|------|------------|
| listing 호출 | M + D | 2 (branches + tree) |
| 콘텐츠 호출 | N 직렬 | N 병렬 (chunk 10) |
| 1년 / 노트 500 첫 로드 | ~107초 | 2 + 50 RTT × 150ms ≈ 8초 |
| 한 달 / 노트 30 첫 로드 | ~9초 | 2 + 3 RTT × 150ms ≈ 1초 |

(병렬은 HTTP/2 multiplex 시 더 빠를 수 있음. chunk 10은 conservative.)
