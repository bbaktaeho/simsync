---
title: Desktop 월별 디렉토리 패널 개발 일지
description: 우측 월별 노트 리스트 패널, cmd+R/cmd+B 패널 토글 단축키 구현 기록
type: develop
created: 2026-08-17
related:
  - .agent/plan/021-2026-08-17-desktop-monthly-directory-panel/plan.md
---

# 2026-08-17 Desktop 월별 디렉토리 패널

## 작업 내용

- `widgets/directory_panel.dart` 신규: 저장 구조 `notes/{YYYY-MM}/DD/`의 월 폴더를
  `noteDate` 기준으로 재구성해 우측 패널에 표시. 월은 최신순, 월 안은 날짜·생성순.
  항목은 "DD: 제목", 메모(`isMemo`)는 `memoAccent`(teal) 색과 메모 아이콘으로 구분.
- 월 헤더 클릭으로 접기/펼치기, 헤더의 소형 버튼으로 전체 닫기. expand 상태는
  패널 내부 상태로만 유지(초기값: 선택된 날짜의 월만 펼침).
- `ShortcutAction.toggleSidebar`(cmd+B), `toggleDirectoryPanel`(cmd+R) 추가.
  타이틀바에 폴더 토글 버튼 추가(활성 시 accent 색).
- `memoAccent` 색 추가: light `#2A9D99`(DESIGN.md Teal), dark `#43B5B0`.

## 결정과 함정

- cmd+B는 기존 `formatBold`와 키가 겹친다. 바인딩 목록에서 패널 토글을 format
  뒤에 두고, 키 핸들러의 format 케이스가 에디터 포커스 부재로 소비하지 않을 때
  `return false` 대신 `continue` 하도록 바꿔 뒤쪽 바인딩(toggleSidebar)이 잡게
  했다. 에디터 포커스 중 cmd+B는 여전히 굵게다.
- `ShortcutAction`에 값을 추가하면 `editor_panel.applyFormat`과
  `menu_bar_panel._handleHardwareKeyEvent`의 exhaustive switch가 깨진다 — 두 곳에
  무시/비소비 케이스를 함께 추가해야 한다.
- 타이틀바에 버튼을 추가하자 좁은 폭(테스트 기본 800px)에서 Row가 7.8px 넘쳤다.
  검색창을 `SizedBox(width: 320)`+Spacer 2개에서 `Expanded > Center >
  ConstrainedBox(maxWidth: 320)`로 바꿔 넓은 창은 기존과 동일, 좁은 창은 검색창이
  먼저 줄어들게 했다.

## 추가 반영 (같은 날 2차)

- 로컬 노트 구분: 좌측 리스트와 같은 문법으로 `localAccent`(주황) 배경 틴트
  (기본 3% / hover 6% / 선택 10%) + 주황 글자·아이콘. 메모(teal 글자)와 로컬
  (주황 틴트)은 독립 축이라 로컬 메모는 둘 다 표현된다.
- 헤더에 닫기(X) 버튼 추가 — 단축키 없이 패널 안에서 닫을 수 있다.
  `DirectoryPanel.onClose`가 null이면 버튼이 숨는다.

## 추가 반영 (같은 날 3차, v0.4.1 재릴리즈)

- 헤더에 월 정렬 토글 버튼 추가(전체 닫기 왼쪽): 최신 월 우선(기본, 아래 화살표)
  ↔ 과거 월 우선(위 화살표). `groupNotesByMonth(newestFirst:)` 파라미터로 구현,
  월 안의 노트 순서(날짜·생성순 오름차순)는 방향과 무관하게 유지. 정렬 상태는
  expand 상태처럼 패널 내부 상태.
- v0.4.1 릴리즈에 끼워넣기 위해 태그를 새 main 커밋으로 강제 이동하고 DMG 자산을
  교체(`gh release upload --clobber`)했다. 앱 버전/빌드번호(0.4.1+13)는 그대로.

## 검증

1. `flutter analyze` clean, `flutter test` 550개 전부 통과(신규 13개 포함)
2. `flutter build macos` 성공
3. 런타임(설치 앱 제거 후 새 빌드): cmd+R/cmd+B 토글, 월 접기/펼치기, 전체 닫기,
   항목 클릭 시 탭 열림·날짜 이동·선택 하이라이트, 메모 teal 구분(라이트/다크),
   로컬 노트 주황 구분, 헤더 X 버튼으로 패널 닫힘 확인
