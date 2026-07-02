---
title: Mobile 코드 정리 및 성능 최적화
description: 백그라운드 폴링 정지, 리뷰 파일 경로 필터 포팅, 캐시 쓰기 방어 포팅
type: plan
created: 2026-07-03
status: active
---

# Mobile 코드 정리 및 성능 최적화

## 배경

desktop은 성능 작업(PR #21~#23)과 리뷰 기능을 거치며 storage 계층이 다듬어졌지만
mobile(Android)은 그 이후 개선이 포팅되지 않았다. mobile/lib 전수 분석 후
실효성이 검증된 항목만 반영한다.

## 확정 작업 (코드로 검증된 갭)

1. **백그라운드 폴링 정지 (battery)** — `main.dart`의 `_AppShellState`에
   `WidgetsBindingObserver`가 없어 앱이 백그라운드로 가도 GitHubSyncEngine
   폴링(기본 5초)과 세션 체크 타이머(60초)가 계속 돈다. paused/hidden에서
   정지, resumed에서 재시작(`start()`가 즉시 `syncNow()`를 호출해 자연스럽게
   따라잡기 폴링이 된다). 재시작은 `_applySyncPreference`를 통해 사용자의
   syncEnabled 설정을 존중한다.
2. **리뷰 파일 경로 필터 포팅 (correctness + perf)** — desktop
   `github_note_storage.dart`의 `_isDailyNotePath`
   (`^notes/\d{4}-\d{2}/\d{1,2}/[^/]+\.md$`)가 mobile에 없어, desktop이 같은
   repo에 커밋하는 위클리/먼슬리 리뷰 파일(`notes/YYYY-MM/N주차/...`,
   `notes/YYYY-MM/monthly-review.md`)이 mobile `listAllNotes()`에서 노트로
   fetch/파싱되어 목록에 섞인다. desktop 필터와 테스트를 포팅한다.
3. **캐시 쓰기 방어 포팅 (robustness)** — desktop `github_note_cache.dart`의
   `_writeNow`는 인스턴스별 tmp 파일명 + `FileSystemException` 흡수로 실패한
   쓰기가 `_saveInFlight` 체인을 오염시키지 않게 한다. mobile은 이 방어가
   없어 일시적 디스크 오류 한 번이 앱 수명 동안 모든 캐시 저장을 중단시킨다.
   mobile에서도 repo 재선택 시 storage bundle이 재생성되므로 같은 경로를 두
   인스턴스가 겹쳐 쓸 수 있다.

## 분석했지만 제외한 항목 (근거)

- `lastCommitSha` 영속화: 이미 mobile에 구현되어 있음 (main.dart
  `_defaultStorageFactory`가 loadCache → initialCommitSha → setLastCommitSha
  체인을 완성함). 분석 단계의 갭 보고는 오류였다.
- `readTextFile`/`writeTextFile` 인터페이스: desktop 리뷰 기능 전용. mobile에
  리뷰 기능이 없으므로 미리 추가하지 않는다 (MVP 원칙).
- 검색 관련 파일(`search_screen.dart`, `search/`)과 `pubspec.yaml`: 미머지
  브랜치 `feature/mobile-feature-port`가 수정 중이라 충돌 방지를 위해 제외.
- 캘린더/설정 화면 위젯 리빌드 최적화: 효과 대비 diff가 크고 회귀 위험이
  있어 이번 범위에서 제외.

## 검증

- 포팅 테스트: 리뷰 파일 제외(fetch 자체가 없어야 함), 캐시 쓰기 실패 후
  후속 저장 정상 동작.
- `flutter analyze` clean, `flutter test` 전체 통과 (mobile).
