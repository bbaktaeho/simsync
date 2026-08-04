---
title: Popover Multi-Monitor Anchor Fix
description: 트레이 popover가 멀티모니터/해상도 변경 시 엉뚱한 위치에 뜨던 버그 수정
type: develop
created: 2026-08-04
related:
  - .agent/plan/019-2026-08-04-popover-multi-monitor-anchor/plan.md
---

# Popover Multi-Monitor Anchor Fix

## Root Cause

- tray_manager `getBounds`는 y를 `NSScreen.main`(키 윈도우가 있는 화면) height로
  뒤집고, window_manager `setPosition`은 `NSScreen.screens[0]`(primary) height로
  되돌린다. 메인 창이 다른 모니터에 있거나 해상도가 다르면 y가 어긋난다.
- `menu_bar_manager.dart`의 `if (dx < 8) dx = 8` 클램프가 primary 왼쪽 모니터
  (전역 음수 x)의 popover를 primary로 끌고 왔고, `bounds.bottom > 0` 가드는
  primary 위쪽 모니터(음수 y)를 버렸다.

## Fix

- `desktop/macos/Runner/PopoverAnchor.swift` (신규): 클릭 시점 포인터가 있는
  화면을 찾아 그 화면의 `visibleFrame.maxY`(메뉴바 하단)를 popover 상단으로,
  아이콘 오른쪽 정렬 x를 해당 화면 안으로 클램프. window_manager의 좌표계
  (primary 기준 top-left flip)로 반환해 `setPosition` 왕복이 정확히 일치.
  Flutter import 없는 순수 계산이라 검증 스크립트가 단독 컴파일 가능.
- `MainFlutterWindow.swift`: 메인 엔진에 `simsync/tray` 채널(`popoverAnchor`)
  등록.
- `menu_bar_manager.dart`: dx/dy 자체 계산 제거, 네이티브 앵커 호출로 대체.
  `getBounds()`의 raw x(플립 없음, 신뢰 가능)는 정확한 아이콘 정렬 힌트로 전달
  하되, 포인터에서 50pt 이상 떨어진 힌트(다른 디스플레이의 status window)는
  네이티브에서 무시.

## Verification

1. `desktop/tool/popover_anchor_check.swift` — 실제 프로덕션 파일을 함께 컴파일해
   7개 시나리오 assert (노치 메뉴바, 왼쪽 모니터 음수 x, 위 모니터 음수 y, 상단
   엣지 핀, 힌트 불일치, 우측 클램프, 힌트 없음): 통과.
2. `flutter analyze` clean + `flutter test` 485개 전부 통과.
3. `flutter build macos --release` 성공 (pbxproj 등록 포함 Swift 컴파일 확인).

멀티모니터 실기기 확인은 develop 빌드로 소유자가 직접 진행 예정.
