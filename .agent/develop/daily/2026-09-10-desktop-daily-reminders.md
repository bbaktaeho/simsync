---
title: Desktop 일일 알림(리마인더) 개발 일지
description: 사용자가 시각·멘트를 정하는 macOS 일일 알림, 설정 Reminders 패널, 알림 클릭 시 앱 열기
type: develop
created: 2026-09-10
related:
  - .agent/plan/022-2026-09-10-desktop-daily-reminder/plan.md
---

# 2026-09-10 Desktop 일일 알림

## 작업 내용

- `Reminder` 모델(id, minutes, message, enabled)과 `AppSettings.reminders` 추가.
  shared_preferences `reminders` 키에 JSON 배열로 저장. 테마처럼 디바이스 로컬이라
  동기화 JSON에는 넣지 않는다.
- `ReminderNotifications.sync(list)` → `simsync/notifications` 채널. 네이티브
  `ReminderChannel`(MainFlutterWindow.swift)이 `simsync.reminder.` 접두사 pending 요청을
  모두 지우고 켜진 항목마다 `UNCalendarNotificationTrigger(repeats: true)`로 재등록한다.
  Dart 타이머 없음. `main.dart`가 설정 리스너에서 리스트가 바뀔 때만 호출한다.
- `AppDelegate`가 `UNUserNotificationCenterDelegate`: 앱이 전면이어도 배너 표시,
  배너 클릭/"SimSync 열기" 액션 시 메인 창 표시.
- 설정에 Reminders 패널: "+ 추가"로 항목 생성(기본 18:00, 기본 멘트), 시각 버튼은
  `showTimePicker`, 멘트는 TextField(제출/포커스 이탈 시 커밋), 개별 Switch, 삭제.

## 검증

- `flutter analyze` clean, `flutter test` 통과(555).
- 릴리즈 빌드로 런타임 확인: 권한 프롬프트 허용 후 예정 시각에 "SimSync / 멘트" 배너
  발송, 창을 숨긴 상태에서 알림 클릭 시 메인 창 복귀, 패널 추가/타임 피커 동작.
  "SimSync 열기" 액션 버튼은 카테고리 등록으로 존재하나 접근성 자동화로는 눌러보지 못했다.

## 함정

- `defaults write`로 JSON 문자열을 넣을 때는 `-string`을 붙여야 한다(없으면 plist로 파싱 시도).
- 첫 `requestAuthorization` 프롬프트는 알림 배너 형태라 System Events의
  `NotificationCenter` 프로세스 액션으로 허용할 수 있다.
