---
title: Desktop 월별 디렉토리 패널
description: 우측에 월별(YYYY-MM) 노트 리스트 패널 추가, cmd+R 토글, 좌측 사이드바 cmd+B 토글
type: plan
created: 2026-08-17
status: active
---

# Desktop 월별 디렉토리 패널

## 요구사항 (confirmed)

- 에디터 우측에 월별 디렉토리 리스트 패널을 추가한다.
- 월 디렉토리는 각각 열고 닫을 수 있고, 패널 자체는 cmd+R로 여닫는다.
- 좌측 사이드바(캘린더·노트 리스트)는 cmd+B로 여닫을 수 있게 한다.
- 패널 상단에 "열린 디렉토리 전체 닫기" 소형 버튼을 둔다.
- md 노트만 표시하고, 항목은 "날짜: 제목"으로 표현한다. 메모는 다른 컬러로 구분한다.

## 배경

- 실제 저장 구조가 `notes/{YYYY-MM}/{DD}/{title}.md` 이므로 노트의 `noteDate` 기준
  YYYY-MM 그룹핑이 곧 실제 월 디렉토리다. 파일시스템 재탐색 없이 `_allNotes`를 그룹핑한다.
- 메모(`isMemo`)도 같은 경로에 frontmatter로 저장되므로 같은 월 그룹에 넣고 색만 구분한다.

## 변경 파일

| 파일 | 변경 |
|------|------|
| `desktop/lib/settings/shortcut_binding.dart` | `ShortcutAction.toggleSidebar`(cmd+B), `toggleDirectoryPanel`(cmd+R) 추가. format 바인딩 뒤에 배치 |
| `desktop/lib/theme/app_colors.dart` | `memoAccent` 추가 (DESIGN.md Teal `#2A9D99`, dark는 밝힌 변형) |
| `desktop/lib/widgets/directory_panel.dart` | 신규. 월 섹션 expand/collapse, 전체 닫기, "DD: 제목" 항목, 메모 teal 표시 |
| `desktop/lib/screens/document_screen.dart` | `_directoryPanelOpen` 상태, Row 우측에 패널, 타이틀바 토글 버튼, 키 핸들러에 두 액션 추가 |

## 결정 사항 (proposed)

- cmd+B는 기존 `formatBold`와 키가 겹친다. 기존 동작(에디터 포커스 시 굵게)은 유지하고,
  에디터 포커스가 없을 때만 사이드바 토글로 동작한다. 핸들러 루프에서 format 계열이
  포커스 부재로 소비하지 않으면 `continue` 하여 뒤의 `toggleSidebar` 바인딩이 잡는다.
- 항목 라벨은 월 그룹 안이므로 `DD: 제목` (일 두 자리). 제목이 비면 `Untitled`.
- 월은 내림차순(최신 위), 월 안의 노트는 날짜·생성순 오름차순 정렬.
- expand 상태는 패널 위젯 내부 상태로만 유지(설정 저장 안 함). 초기값은 선택된 날짜의 월만 열림.
- 패널 폭은 260 고정(SearchResultsPanel 320 고정 선례). 리사이즈는 범위 외.
- 패널 열림 상태는 세션 메모리로만 유지(좌측 사이드바와 동일 정책).

## 검증

1. `flutter analyze` clean + `flutter test` 통과 (그룹핑/라벨/단축키 유닛 테스트 추가)
2. `flutter build macos` 성공
3. 설치 앱 제거 후 런타임 확인: cmd+R/cmd+B 토글, 전체 닫기, 메모 색, 항목 클릭 시 노트 열림
