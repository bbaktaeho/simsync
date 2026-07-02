---
title: Mobile 코드 정리 및 성능 최적화
description: 백그라운드 폴링 정지, 리뷰 파일 경로 필터 포팅, 캐시 쓰기 방어 포팅
type: develop
created: 2026-07-03
related:
  - .agent/plan/013-2026-07-03-mobile-cleanup-perf/plan.md
---

# 2026-07-03 Mobile 코드 정리 및 성능 최적화

## 작업 내용

- **백그라운드 폴링 정지 (battery)**: `_AppShellState`에 `WidgetsBindingObserver`
  적용. paused/hidden에서 sync 폴링과 세션 체크 정지, resumed에서
  `_applySyncPreference` 경유 재시작 (`start()`가 즉시 `syncNow()`를 호출해
  백그라운드 동안의 원격 변경을 바로 따라잡는다). inactive는 알림창 등 일시
  중단이라 무시. 세션 모니터에 `_sessionMonitorActive` 플래그를 추가해 검증
  in-flight 중 stop이 무효화되는 레이스 제거.
- **리뷰 파일 경로 필터 포팅**: desktop의 `_isDailyNotePath`
  (`^notes/\d{4}-\d{2}/\d{1,2}/[^/]+\.md$`)를 `github_note_storage.dart`에
  포팅. desktop이 같은 repo에 커밋하는 위클리/먼슬리 리뷰 파일이 mobile 노트
  목록에 섞이고 불필요하게 fetch/파싱되던 문제 해결.
- **캐시 쓰기 방어 포팅**: `github_note_cache.dart` `_writeNow`에 인스턴스별
  tmp 파일명 + `FileSystemException` 흡수 적용. 일시적 디스크 오류 한 번이
  `_saveInFlight` 체인을 오염시켜 앱 수명 동안 캐시 저장이 전부 중단되던
  문제 방지.

## 제외/정정 사항

- `lastCommitSha` 영속화는 mobile에 이미 구현되어 있음을 확인 (분석 단계
  보고가 오류였음). `readTextFile`/`writeTextFile`은 리뷰 기능 전용이라
  미포팅. search 계열 파일과 pubspec은 미머지 `feature/mobile-feature-port`
  브랜치와의 충돌을 피해 제외.

## 검증

- 신규 테스트 4개: 리뷰 파일 제외(blob fetch 자체가 없어야 함), `N주차` 폴더
  tolerant listDates, 캐시 쓰기 실패 후 후속 저장 정상, 캐시 라운드트립.
- `flutter analyze` clean, `flutter test` 전체 통과 (mobile).
