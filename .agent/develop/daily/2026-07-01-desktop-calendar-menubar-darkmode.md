---
title: 데스크탑 캘린더 이웃-달 + macOS 메뉴바 앱 + 다크모드
description: 캘린더 인접 월 표시, macOS 상단바 트레이/popover, 다크모드(popover 포함) 개발 일지
type: develop
created: 2026-07-01
related:
  - .agent/plan/011-2026-07-01-desktop-calendar-and-menubar/plan.md
---

# 2026-07-01 개발 일지

## 작업 범위

한 브랜치(`feature/desktop-calendar-and-menubar`)에서 3개 요청을 순차 개발, 단일 PR(대상 `develop`).

1. 데스크탑 캘린더 고도화 — 인접 월(이전/다음) 날짜 표시
2. macOS 상단 메뉴바 앱 — 트레이 아이콘 + 우클릭 메뉴 + 좌클릭 popover(캘린더/노트리스트/에디터 오버레이)
3. 다크모드 — System/Light/Dark, 메뉴바 popover 포함

## 구현 요약

- **캘린더**: `calendar_section.dart` 그리드를 6주 가변 렌더로 재작성, 첫/마지막 주 빈칸을 인접 월 날짜(muted)로 채움. DST-safe하게 `DateTime(y, m, 1+offset)` 정규화 사용. 인접 월 날짜 클릭 시 표시 월 이동(`document_screen`).
- **메뉴바**: `tray_manager` + `window_manager` 추가. `MenuBarManager`가 트레이(아이콘·우클릭 메뉴)와 단일 창의 app↔panel 모드 전환(프레임리스·always-on-top·blur 시 hide, 닫기→hide)을 담당. `MenuBarController`(동일 storage 공유, 디바운스 저장, dirty 보호)와 `MenuBarPanel`(캘린더+점 → 날짜 리스트+메모탭 → 우클릭/+로 추가 → `EditorPanel` 오버레이). 트레이 아이콘은 로고 painter로 흑색 템플릿 PNG 생성(`tool/generate_app_icon.dart`).
- **다크모드**: `AppColorsExtension.dark` + `buildDarkTheme()`. `AppSettings.themeMode` 로컬 저장, 루트 `ValueNotifier<ThemeMode>`로 MaterialApp 배선, 설정 화면 Appearance 선택. popover는 `context.colors`라 자동 적용.

## 검토 (≥3회)

- **Round 1 (자체)**: 에디터 오버레이 헤더 제목이 `EditorPanel` 제목 필드와 중복 → 제거. IndexedStack이 미로드 popover의 무한 스피너를 항상 빌드 → `pumpAndSettle` 타임아웃 유발, `_panelMode`일 때만 빌드하도록 수정.
- **Round 2 (독립 서브에이전트)**: `load()`가 dirty 미보호로 blur→재오픈 시 미저장 편집 유실(HIGH) → dirty-merge + `updateNote` isDirty=true. 로그아웃 시 `_bundle!` 크래시 경로 → storage 게터 nullable + 패널 리셋. 창 전환 `_panelVisible` 정합성, `onWindowClose` 앱 표면 복원, `_NoteRow` key 추가.
- **Round 3 (홀리스틱)**: 요구사항 전 항목 커버 확인, 설정 화면 `AnimatedBuilder`로 테마 선택 즉시 반영 확인, 다크 팔레트 대비 점검(일부 미세조정 여지 기록), 디버그/TODO/시크릿 없음.

## 검증

- `flutter analyze` clean, `flutter test` 344개 통과.
- 신규 테스트: 캘린더 인접 월 렌더/클릭, `MenuBarController` 로직(필터·메모·CRUD·dirty 보호), `MenuBarPanel` UI(리스트→에디터 오버레이→뒤로, 메모탭), 테마 빌드/저장/동기화 제외.
- **소유자 수동 확인 필요**: 메뉴바 아이콘·popover 위치·blur 숨김·다크 팝오버 등 macOS 네이티브 상호작용(headless 검증 불가). 네이티브 설정은 추가 변경 불필요(샌드박스 off, 플러그인 자동 등록, 배포 타겟 10.15 ≥ 요구 10.11).

## 남은 개선 여지

- 트레이 아이콘 정확한 화면 좌표(멀티 모니터/메뉴바 높이) 미세조정.
- 다크 팔레트 색값(특히 today 셀 blue-on-deepblue 대비) 실기기 튜닝.
- panel 창 배경 초기 플래시(현재 Material fill로 커버).
