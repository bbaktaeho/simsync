---
title: Desktop 일일 정리 알림
description: 정해진 시간에 macOS 알림으로 "오늘 정리" 리마인더 발송, 설정에서 토글/시간 조절, 알림에 SimSync 열기 버튼
type: plan
created: 2026-09-10
status: active
---

# Desktop 일일 정리 알림

## 요구사항 (confirmed)

- 정해진 시간에 맥북에 알림이 온다.
- 설정에서 시간을 조절할 수 있고, 켜고 끄는 토글이 있다.
- 멘트는 "오늘 할 일과 했던 일을 정리하세요" 취지를 다듬어 쓴다.
- 가능하면 알림에 "SimSync 열기" 버튼을 넣는다.

## 결정 사항 (proposed)

- 새 패키지 없이 macOS `UNUserNotificationCenter`를 직접 쓴다. `simsync/notifications`
  method channel(`schedule(hour, minute)` / `cancel`)을 `MainFlutterWindow.swift`에 등록한다.
- 스케줄은 OS에 맡긴다: 고정 identifier로 `UNCalendarNotificationTrigger(repeats: true)`를 등록하면
  매일 그 시각에 발송된다. Dart 타이머 없음. 시간 변경은 같은 identifier로 재등록, 끄기는 pending 제거.
- 알림 카테고리에 `open` 액션("SimSync 열기")을 붙인다. 액션/본문 클릭 모두 메인 창을 띄운다.
- 앱이 전면일 때도 배너가 보이도록 `willPresent`에서 `.banner`를 반환한다.
- 설정 필드 `reminderEnabled`(기본 false), `reminderMinutes`(자정 기준 분, 기본 18:00).
  테마처럼 디바이스 로컬이며 동기화 JSON에서 제외한다(알림은 기기별 성격).
- 멘트: 제목 "오늘을 정리할 시간입니다", 본문 "오늘 한 일과 남은 할 일을 노트에 정리해 보세요."
- 설정 UI: "Reminder" 네비 항목 + 카드 하나(Switch + 시간 표시 + Change... → `showTimePicker`).

## 변경 파일

| 파일 | 변경 |
|------|------|
| `desktop/macos/Runner/MainFlutterWindow.swift` | `ReminderChannel` 등록 |
| `desktop/macos/Runner/AppDelegate.swift` | `UNUserNotificationCenterDelegate` (willPresent/didReceive → 창 표시) |
| `desktop/lib/settings/app_settings.dart` | `reminderEnabled`, `reminderMinutes` |
| `desktop/lib/settings/app_settings_controller.dart` | 로드/저장 + setter |
| `desktop/lib/services/reminder_notifications.dart` | 신규. 채널 호출 래퍼 |
| `desktop/lib/main.dart` | 설정 리스너에서 스케줄 반영 |
| `desktop/lib/screens/settings_screen.dart` | Reminder 패널 |

## 검증

1. `flutter analyze` clean + `flutter test` (설정 저장/로드, JSON 제외 테스트)
2. `flutter build macos` 후 설치 앱 제거, 1분 뒤 시각으로 켜서 배너 확인
