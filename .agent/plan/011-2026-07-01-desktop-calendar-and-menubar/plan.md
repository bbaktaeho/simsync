---
title: 데스크탑 캘린더 이웃-달 표시 + macOS 메뉴바 앱
description: 캘린더에 이전/다음 달 날짜 표시, macOS 상단 메뉴바 트레이 + popover(캘린더/노트리스트/에디터 오버레이)
type: plan
created: 2026-07-01
status: active
related:
  - desktop/lib/widgets/calendar_section.dart
  - desktop/lib/screens/document_screen.dart
  - desktop/lib/main.dart
---

# 데스크탑 캘린더 고도화 + macOS 메뉴바 앱

## 개요

두 개의 독립적인 신규 기능을 한 브랜치에서 개발하고 **단일 PR**(대상 `develop`)로 묶는다.

1. **캘린더 이웃-달 날짜 표시** (작음, 저위험)
2. **macOS 상단 메뉴바(트레이) 앱** (큼, 신규 영역)

규모 차이가 크므로 1을 먼저 완료해 조기 확인점을 만들고, 이후 2를 단계적으로 진행한다.

## Confirmed Requirements (소유자 확정)

- 캘린더: 다음 월을 볼 때 해당 주에 걸친 **이전 월(및 대칭적으로 다음 월) 날짜까지** 캘린더에 표시.
- macOS 상단바에 SimSync 추가.
  - 우클릭: 앱 열기 / 설정 / 앱 종료
  - 좌클릭: 캘린더 popover
    - 캘린더에 문서(노트) 있는 날 표시(점)
    - 날짜 클릭 시 하단에 노트 리스트(메모 탭 동일 제공)
    - 캘린더 날짜 우클릭 시 노트 혹은 메모 추가
    - 노트/메모 추가 또는 리스트 클릭 시 **에디터를 오버레이로** 띄워 수정
- 디자인 시스템(DESIGN.md, Notion 계열) 준수, UX 중시.
- `tray_manager`, `window_manager` 패키지 추가 승인됨.
- 다크모드(System/Light/Dark) 지원 — 메뉴바 popover 포함(추가 요청).
- 완료 후 PR 1개.

## Assumptions (명시)

- 대칭적으로 마지막 주 뒤쪽 다음 달 날짜도 채워 항상 완전한 7열 주를 렌더한다(표준 달력 UX). 요청은 "이전 월"을 명시했으나 완결성을 위해 다음 월도 포함.
- 이웃-달 날짜는 흐린(muted) 스타일로 구분하고, 클릭 시 해당 날짜 선택 + 표시 월을 그 달로 이동.
- 메뉴바 popover는 **인증되어 storage가 있을 때만** 노트를 보여준다. 미인증 시 좌클릭은 앱 창을 연다(로그인 유도).
- 단일 사용자 PoC이므로 메인 창과 popover가 동시에 같은 노트를 편집할 때의 짧은 데이터 불일치는 수용한다.

## Proposed Decisions (추천안, 채택)

### D1. popover 데이터 공유 = 가벼운 독립 컨트롤러 (B안)

- 신규 `MenuBarController`(ChangeNotifier)가 `_AppShell`이 이미 보유한 **동일 `storage`/`localStorage` 인스턴스**를 공유해 자체 노트 목록/선택 상태를 관리.
- 쓰기(생성/저장/삭제/메모전환)는 같은 storage로 나가고, 완료 후 기존 `refreshSignal`(ValueNotifier<int>)을 올려 `DocumentScreen`도 재로딩.
- 반대로 메인 창의 변경도 popover가 열릴 때 재로딩으로 반영.
- 기각안 A: `document_screen.dart`에서 노트 상태를 전면 추출하는 리팩토링 → 중앙 파일 회귀 위험, MVP·비-리팩토링 원칙에 반해 기각.

### D2. 창/트레이 = 단일 Flutter 창 재활용

- 멀티 윈도우/멀티 엔진 없이 창 하나를 두 모드로 토글.
  - **App 모드**: 기존 `DocumentScreen`(정상 창).
  - **Panel 모드**: 프레임리스 · always-on-top · 컴팩트(~360×540) · 메뉴바 아래 위치 · blur 시 자동 hide.
- 루트에서 `IndexedStack`으로 두 화면을 트리에 유지 → 토글해도 `DocumentScreen` 상태 보존.
- 창 닫기 버튼은 `setPreventClose(true)` + `onWindowClose`로 가로채 **hide**(메뉴바 상주). 실제 종료는 우클릭 "앱 종료"에서 `destroy()`.

## Architecture

```
main.dart
 ├─ WidgetsFlutterBinding.ensureInitialized()
 ├─ windowManager.ensureInitialized() + 초기 WindowOptions
 └─ runApp(SimSyncApp)
       └─ _AppShell (auth/storage 소유)
             ├─ MenuBarManager (tray_manager + window_manager 배선)
             ├─ MenuBarController (popover 상태 + 노트 CRUD, storage 공유)
             └─ IndexedStack
                   ├─ [0] DocumentScreen (App 모드)
                   └─ [1] MenuBarPanel  (Panel 모드)
```

### 신규/수정 파일

| 파일 | 종류 | 내용 |
|------|------|------|
| `desktop/lib/widgets/calendar_section.dart` | 수정 | 이웃-달 날짜 렌더 + muted 셀 스타일 |
| `desktop/lib/screens/document_screen.dart` | 소폭 수정 | 이웃-달 클릭 시 표시 월 이동 |
| `desktop/lib/main.dart` | 수정 | 네이티브 초기화, 창 옵션, MenuBar 배선 |
| `desktop/lib/services/menu_bar_manager.dart` | 신규 | 트레이 아이콘/메뉴, 창 모드 전환, blur→hide |
| `desktop/lib/services/menu_bar_controller.dart` | 신규 | popover 상태 + 노트 로드/생성/저장/삭제/메모 |
| `desktop/lib/widgets/menu_bar_panel.dart` | 신규 | popover UI(캘린더/리스트/메모탭/에디터 오버레이) |
| `desktop/pubspec.yaml` | 수정 | `tray_manager`, `window_manager` 추가 |
| `desktop/macos/.../*` | 수정 | 메뉴바 아이콘 asset, 필요한 entitlement/Info |

## UX & Design System (DESIGN.md)

- popover: floating panel → Deep shadow(Level 3), whisper border(1px rgba(0,0,0,0.1)), radius 12px, 흰 surface.
- 기존 테마 토큰(`app_colors`/`app_text_styles`/`app_dimensions`/`app_shadows`) 및 `CalendarSection`·`NoteListSection`·`EditorPanel` 재사용으로 시각적 일관성.
- Notes/Memo 세그먼트 탭, 에디터 오버레이는 ← 로 리스트 복귀, 전환 애니메이션 `animFast`.
- 이웃-달 셀은 `textMuted`, 문서 점은 기존 `calendarDot` 유지.
- 접근성/상태: hover/pressed/focus는 기존 위젯 관례 준수.

## Phasing

1. **Phase 1 — 캘린더 이웃-달 표시**
   - `calendar_section.dart` `_buildWeeks` 재작성(6주 고정 그리드, 이웃-달 채움), muted 셀.
   - `document_screen.dart`에서 이웃-달 클릭 시 `_displayedMonth` 이동.
   - 위젯 테스트 추가.
2. **Phase 2 — 메뉴바 기반**
   - 패키지 추가 + `flutter pub get`.
   - `main.dart` 초기화, 창 옵션, prevent-close→hide.
   - `MenuBarManager`: 트레이 아이콘 + 우클릭 메뉴(앱 열기/설정/종료), 좌클릭 → panel 토글.
   - Panel 모드 창 크기/위치/always-on-top/blur-hide.
3. **Phase 3 — 메뉴바 popover 콘텐츠**
   - `MenuBarController` + `MenuBarPanel`.
   - 캘린더(점) → 날짜 리스트 + 메모탭 → 우클릭 추가 → 에디터 오버레이 편집/저장.
   - 컨트롤러 로직 단위 테스트.
4. **Phase 4 — 다크모드 (추가 요청)**
   - `AppColorsExtension.dark` + `buildDarkTheme()`(brightness 파라미터화).
   - `AppSettings.themeMode`(System/Light/Dark) 로컬 저장, 루트 `ValueNotifier<ThemeMode>`로
     MaterialApp 배선, 설정 화면에 Appearance 선택.
   - popover는 `context.colors`라 자동 적용. 테마 빌드/저장 테스트.

각 Phase 후 workflow.md 4–13단계 검토(목적 적합성/버그·보안/사이드이펙트/재사용/품질/사용자 흐름)를 최소 3회 반복.
검토 기록: Round 1 자체(에디터 헤더 중복·무한 스피너 수정), Round 2 독립 서브에이전트
(미저장 편집 보호·로그아웃 크래시·창 상태 정합성 수정), Round 3 홀리스틱(다크모드 대비·설정 즉시반영 확인).

## Testing & Verification

- `flutter analyze` clean, `flutter test` 통과.
- 자동 검증: 캘린더 이웃-달 렌더/클릭, `MenuBarController` 날짜 필터·메모 분리·CRUD.
- 수동 검증(소유자): 메뉴바 아이콘/좌우클릭/popover 위치/blur 숨김/에디터 오버레이 — headless 불가.

## Risks / Limitations

- 트레이 아이콘 정확한 화면 좌표 계산은 플랫폼 편차가 있어 기본 위치(우상단 메뉴바 아래) 후 미세조정.
- 네이티브 플러그인 추가로 `flutter build macos` 시 `pod install` 필요(소유자 환경).
- 단일 창 재활용 특성상 Panel↔App 전환 시 창 리사이즈가 발생.

## Out of Scope

- Windows/Linux 트레이(요청은 macOS 상단바). 코드는 크래시 없이 무시하도록 가드.
- mobile 프로젝트 반영.
- popover와 메인 창의 실시간 양방향 라이브 동기화(재로딩 기반으로 충분).

## Addendum (2026-07-02) — 구현 현황 갱신 + 후속 수정

초기 계획의 D2(단일 창 재활용)는 구현 과정에서 **desktop_multi_window 기반 별도 popover 창**으로 대체되었다
(메인 창을 건드리지 않기 위함). 이후 소유자 리포트 2건을 근본 원인 수준에서 수정했다.

1. **popover 동기화 미동작**: popover 엔진이 자체 `StorageBundle`을 쓰면서 `GitHubSyncEngine`을
   시작하지 않아 부팅 시점 캐시 스냅샷이 고정되던 문제. show 시 `SharedPreferences.reload()` +
   설정 재로딩 + `syncNow`(즉시 폴) + 표시 중 폴링/dismiss 시 중지로 수정. popover 편집은
   `notes_changed` 멀티윈도우 채널로 메인 창에 즉시 통지.
2. **전체화면 위 미표시**: sub-window가 titled 일반 NSWindow라 `.nonactivatingPanel`이 무효였던 문제.
   창 생성 콜백에서 Flutter 콘텐츠를 자체 `NonActivatingPanel`(NSPanel)로 re-host — statusBar level,
   canJoinAllSpaces + fullScreenAuxiliary. 실기기에서 전체화면 앱 위 표시 확인.

상세: [.agent/develop/daily/2026-07-02-menubar-sync-and-fullscreen-panel.md](../../develop/daily/2026-07-02-menubar-sync-and-fullscreen-panel.md)

Out of Scope에 있던 "실시간 양방향 라이브 동기화"는 이번 수정으로 사실상 해소됨
(popover 표시 중 폴링 + 편집 즉시 통지).
