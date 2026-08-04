---
title: Popover Multi-Monitor Anchor Fix
description: 트레이 popover가 멀티모니터/해상도 변경 시 엉뚱한 위치에 뜨는 버그의 근본 원인 수정
type: plan
created: 2026-08-04
status: active
---

# Popover Multi-Monitor Anchor Fix

## Problem

메뉴바 트레이 아이콘 클릭 시 popover가 아이콘 바로 아래에 떠야 하는데, 멀티모니터
연결이나 해상도 변경 후에는 다른 모니터 또는 화면 하단에 그려진다.

## Root Cause

popover 위치는 `trayManager.getBounds()` 결과로 계산해 `windowManager.setPosition()`
에 넘기는데, 두 플러그인의 macOS 좌표 변환 기준 화면이 다르다.

1. **tray_manager 0.5.3** `getBounds`: y를 `NSScreen.main`(키 윈도우가 있는 화면 —
   포커스 따라 계속 바뀜)의 height로 뒤집는다. 화면 origin offset도 무시한다.
2. **window_manager 0.5.1** `setPosition`: y를 `NSScreen.screens[0]`(항상 primary)의
   height로 되돌린다.

메인 창이 다른 모니터에 있거나 모니터 해상도가 서로 다르면 두 변환이 어긋나 y가
틀어진다 (하단/다른 모니터 증상). 추가로 앱 코드 `menu_bar_manager.dart`의
`if (dx < 8) dx = 8` 클램프는 primary 왼쪽에 배치된 모니터(전역 음수 x)에서
popover를 primary 모니터로 끌고 온다. `screen_retriever`의 커서 API도 자체 좌표
버그(`min(maxY)` 기준 flip)가 있어 대안이 못 된다.

## Fix

플러그인의 y 값을 신뢰하지 않고, 이미 소유한 네이티브 코드에서 앵커를 직접 계산한다.

- `desktop/macos/Runner/PopoverAnchor.swift` (신규, 순수 계산): 마우스 위치가 있는
  화면을 찾고, 그 화면의 `visibleFrame.maxY`(= 해당 화면 메뉴바 하단)를 popover
  상단으로, 아이콘 오른쪽 정렬 x를 화면 범위 안으로 클램프해서 window_manager의
  좌표계(primary 기준 top-left flip)로 반환. Flutter import 없이 CoreGraphics만
  사용해 검증 스크립트가 단독 컴파일 가능.
- `MainFlutterWindow.swift`: 메인 엔진에 `simsync/tray` 채널 등록. 클릭 시점
  `NSEvent.mouseLocation` + `NSScreen.screens`로 위 계산을 호출.
- `menu_bar_manager.dart`: dx/dy 자체 계산과 `dx < 8` 클램프 제거, 네이티브 앵커
  호출로 대체. `getBounds()`의 raw x(신뢰 가능)는 정확한 오른쪽 정렬 힌트로 전달.
- 이후 파이프라인(생성 args, `show` 채널, `_applyEditorSize`)은 동일 좌표계의 선형
  연산이므로 변경 없음.

## Verification

1. `desktop/tool/popover_anchor_check.swift`: 실제 `PopoverAnchor.swift`를 함께
   컴파일해 멀티모니터 시나리오(왼쪽 모니터 음수 x, 위 모니터 음수 y, 노치 메뉴바,
   화면 우측 클램프, 힌트 불일치) assert.
2. `flutter analyze` + `flutter test` (desktop).
3. `flutter build macos --release` 빌드 성공 (pbxproj 등록 포함 Swift 컴파일 확인).
