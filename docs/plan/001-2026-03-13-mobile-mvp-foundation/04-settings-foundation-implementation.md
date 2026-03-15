---
title: Settings Foundation Implementation
description: Stage 1 settings foundation 상세 구현 계획
type: plan
created: 2026-03-13
---

# Settings Foundation Implementation

## Goal

- authenticated 상태에서 settings screen을 열 수 있게 한다.
- editor/preview 전용 content zoom을 저장하고 단축키와 pointer gesture로 조절할 수 있게 한다.
- GitHub sync interval을 설정에서 바꾸고 현재 sync engine에 반영한다.
- local note path와 synced repo source를 settings에서 확인할 수 있게 한다.

## Files

- Create: `desktop/lib/settings/app_settings.dart`
- Create: `desktop/lib/settings/app_settings_controller.dart`
- Create: `desktop/lib/screens/settings_screen.dart`
- Create: `desktop/test/settings/app_settings_controller_test.dart`
- Modify: `desktop/lib/main.dart`
- Modify: `desktop/lib/screens/document_screen.dart`
- Modify: `desktop/lib/widgets/editor_panel.dart`
- Modify: `desktop/lib/widgets/markdown_preview.dart`
- Modify: `desktop/lib/storage/github/github_sync_engine.dart`
- Modify: `desktop/test/widget_test.dart`

## Implementation Notes

- `SharedPreferences`를 settings persistence 저장소로 사용한다.
- `local_note_path` key는 기존 값을 그대로 재사용한다.
- content zoom은 editor/preview에만 적용하고 sidebar/title bar에는 적용하지 않는다.
- settings 진입은 버튼과 `cmd + ,` 둘 다 지원한다.
- content zoom 조절은 `cmd + +`, `cmd + -`, `cmd + mouse wheel`, trackpad pinch를 지원한다.
- sync interval은 초 단위 값으로 저장하고 `GitHubSyncEngine.updateInterval`로 런타임 반영한다.
