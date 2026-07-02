---
title: 메뉴바 popover 동기화 + 전체화면 표시 (NSPanel 전환)
description: popover 노트 동기화 미동작과 전체화면 위 미표시의 근본 원인 수정 일지
type: develop
created: 2026-07-02
related:
  - .agent/plan/011-2026-07-01-desktop-calendar-and-menubar/plan.md
  - .agent/develop/daily/2026-07-01-desktop-calendar-menubar-darkmode.md
---

# 2026-07-02 개발 일지

## 문제 (소유자 보고)

1. 메뉴바 popover가 동기화되지 않음 — 다른 곳에서 만든/수정한 노트가 popover에 반영되지 않음.
2. 전체화면 앱 위에서 트레이 클릭 시 popover가 계속 보이지 않음 (수차례 수정 시도에도 재발).

## 근본 원인

### 1. 동기화

- popover는 별도 Flutter 엔진에서 자체 `StorageBundle`을 만들지만 **`GitHubSyncEngine`을 시작하지 않았고 `onRemoteChanged`도 연결하지 않았다**.
- `GitHubNoteStorage.loadCache()`가 부팅 시 디스크 캐시로 `_treeMap`을 채우는데, invalidation이 없으니 `listAllNotes()`가 **부팅 시점 스냅샷을 영원히 반환**했다.
- 추가로 popover의 `MenuBarController.onChanged`가 빈 콜백이라 popover 편집이 메인 창에 통지되지 않았다 (메인 창 자체 폴링에만 의존).
- `SharedPreferences`는 엔진(isolate)별로 캐시되므로 popover의 `settings.load()`가 디스크 재독 없이는 메인 창의 설정 변경(테마/동기화 토글)을 보지 못했다.

### 2. 전체화면

- `desktop_multi_window`의 sub-window는 titled 일반 `NSWindow`(`CustomWindow`)다. `.nonactivatingPanel` styleMask는 **NSPanel에서만 유효**하므로 기존 네이티브 코드는 사실상 no-op이었고, titled 일반 NSWindow는 `.fullScreenAuxiliary`가 있어도 다른 앱의 전체화면 Space에 합류하지 못한다.

## 수정

- **NSPanel re-host** (`MainFlutterWindow.swift`): 창 생성 콜백에서 FlutterViewController를 plugin 창에서 꺼내 자체 `NonActivatingPanel`(NSPanel, `canBecomeKey=true`)로 이전.
  - styleMask `[.titled, .closable, .miniaturizable, .fullSizeContentView, .nonactivatingPanel]`, `level=.statusBar`, `collectionBehavior=[.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`, `hidesOnDeactivate=false`, `isMovable=false`.
  - `PopoverBridge`가 패널을 **강한 참조로 소유** (미표시 NSWindow는 소유자가 없으면 dealloc → 엔진까지 연쇄 파괴됨. 실측으로 확인한 함정).
  - Dart 쪽 `WindowOptions`에서 `titleBarStyle` 제거 — window_manager `setTitleBarStyle`은 close 버튼 계층을 force-unwrap하므로 버튼 없는 패널에서 플랫폼 스레드가 죽는다(`.closable` 추가로도 방어).
- **popover 동기화 배선** (`popover_window.dart`):
  - `defaultStorageFactory(onRemoteChanged:)` 연결 → 원격 커밋 감지 시 tree cache invalidation 후 `MenuBarController.load()` 재실행.
  - show 시 `_refreshExternalState()`: `SharedPreferences.reload()` → `settings.load()` → `syncEngine.updateInterval(...)` → syncEnabled면 `start()`(즉시 1회 폴 + 표시 중 주기 폴), dismiss 시 `stop()` (메인 창 폴링과 중복 트래픽 방지).
  - popover 편집 저장 시 `notes_changed`를 멀티윈도우 채널로 메인 창에 통지 (`MenuBarManager`가 수신해 `refreshSignal` 증가 → DocumentScreen 재로딩).

## 디버깅 기록 (재발 방지용)

- 1차 시도에서 패널이 생성 직후 사라짐: `NSApp.windows`에 패널 부재 + "Communicating on a dead channel" → weak 참조 문제. lldb로 확인.
- 2차 시도에서 popover Dart가 `waitUntilReadyToShow`에서 정지: lldb backtrace로 window_manager `setTitleBarStyle`의 force-unwrap 크래시 확인 (titled NSPanel도 `.closable` 없으면 close 버튼이 없음).

## 검증 (실기기)

- `flutter analyze` 클린, `flutter test` 348개 통과, macOS 디버그 빌드 성공.
- 런타임: 트레이 클릭 → 패널이 layer 25(statusBar), 332x500, 트레이 아래 표시 (CGWindowList로 확인).
- **전체화면**: 전체화면 앱(Zed) Space에서 상단 호버로 메뉴바 표출 → 트레이 클릭 → popover가 전체화면 위에 표시됨 (스크린샷 확인).
- **동기화**: popover 엔진 부팅 이후 GitHub API로 원격 저장소에 노트 파일 커밋 → popover 재열람 시 해당 노트(`SYNC-TEST`)가 리스트에 표시됨. 테스트 노트는 검증 후 원격에서 삭제.
- 남은 소유자 확인 항목: 전체화면 위 popover 에디터 오버레이에서의 타이핑(비활성 앱 non-activating panel 키 입력), popover 편집 → 메인 창 즉시 반영 체감.

## 주의

- 로컬에 설치된 `/Applications/simsync.app`은 스테일 빌드일 수 있다. 테스트 전 삭제하거나 새 빌드로 교체할 것.

## 리뷰 반영 (2026-07-03, PR 전체 diff 정밀 검토)

8개 관점(라인 스캔/제거된 동작/크로스파일/재사용/단순화/효율/altitude/컨벤션) 병렬 리뷰 후 수정.

### 정합성 수정

- `notes_changed` 수신 시 메인 엔진 tree cache를 invalidate하지 않아 즉시 리로드가 스테일 데이터를 반환하던 버그 수정 (5개 관점이 동시 지적).
- popover 번들이 부팅 시점 세션/레포 스냅샷에 고정되던 문제: show마다 세션/레포/로컬 경로를 재파생해 드리프트 시 번들 교체 (로그인 전 popover가 영구 "로그인하세요"에 갇히는 문제, 레포 전환 후 이전 레포에 커밋하는 문제 해소). 오프라인 시 기존 번들 유지.
- popover 부팅 중 트레이 재클릭 시 `CHANNEL_UNREGISTERED` 예외를 창 소멸로 오판해 popover 창이 복제되던 버그: 부팅 중 클릭은 무시.
- 두 엔진이 같은 캐시 파일의 동일한 `.tmp` 스테이징을 사용해 rename 경합 → 실패한 future에 체이닝돼 저장 체인이 영구 마비되던 버그: 인스턴스별 tmp 이름 + 실패 격리.
- 동기화 OFF일 때 popover에서 동기화 노트가 편집·커밋되던 구멍: `_canMutateNote` 규칙 적용 (에디터 read-only + updateNote 가드).
- `MenuBarController.load()` 실패 시 무한 스피너 + unhandled async error: catch 추가.
- 트레이 "앱 종료"가 debounce 중인 popover 편집을 버리던 문제: 종료 전 popover에 flush 요청(3초 타임아웃).
- 자기 앱 창(메인 창) 클릭 시 popover가 닫히지 않던 문제: 네이티브 local monitor 추가.

### 최적화/구조

- popover 폴링 제거: 메인 엔진 폴링이 `remote_changed`를 popover로 push (기존 설계는 표시 중 API 호출이 2배). popover는 show 시 1회 `syncNow`만 수행.
- 기하 단일화: `MenuBarManager.popoverSize/popoverEditSize`가 유일한 소스, popover 위치 dy를 고정 26pt 대신 트레이 아이콘 bounds 하단에서 파생 (노치/스케일 디스플레이 대응).
- `main.dart` ↔ `popover_window.dart` 순환 import 제거: 부트스트랩(`StorageBundle`, `defaultStorageFactory` 등)을 `app_bootstrap.dart`로 분리, main은 re-export로 하위 호환.
- dirty-merge(Last-Write-Wins 보호)를 `services/note_merge.dart`로 공용화 — DocumentScreen과 popover가 같은 구현 사용.
- popover 부트 병렬화(창 셰이핑/설정/세션 동시), 이중 초기 로드 제거, ThemeData 재생성 제거, 트레이 메뉴는 다크 상태가 실제로 바뀔 때만 재빌드.
- 네이티브 dead code(`hide` 채널 케이스) 제거, `adopt()`의 단일 popover 가정 문서화.

### 미반영 (소유자 판단 필요)

- `desktop_multi_window` 의존성이 계획서 승인 기록 없이 추가됨 → 2026-07-03 소유자 사후 승인,
  계획서 Confirmed Requirements에 기록 완료.
- MenuBarController가 DocumentScreen의 파생 리스트/노트 생성 규칙을 복제 — 전면 상태 추출은 계획서 D1에서 기각된 리팩토링이라 유지. 노트 팩토리/파생 리스트 공용화는 후속 과제.
- 메인 창 에디터의 debounce 저장은 여전히 "앱 종료"와 경합 가능(2초 debounce, 실사용 위험 낮음).
