---
title: Mobile 프로젝트 구조
type: design
created: 2026-03-15
---

# 프로젝트 구조

## 디렉토리 레이아웃

```
mobile/
├── lib/
│   ├── main.dart
│   ├── auth/                      # desktop에서 복사 + OAuth 방식 변경
│   │   ├── auth_models.dart
│   │   ├── auth_service.dart
│   │   ├── auth_provider.dart
│   │   ├── github_oauth_provider.dart
│   │   ├── session_policy.dart
│   │   └── session_store.dart
│   ├── models/
│   │   └── note.dart              # 그대로 복사
│   ├── services/
│   │   └── note_service.dart      # 그대로 복사
│   ├── storage/                   # 그대로 복사
│   │   ├── note_storage.dart
│   │   ├── sync_engine.dart
│   │   ├── conflict_resolver.dart
│   │   ├── github/
│   │   │   ├── github_api_client.dart
│   │   │   ├── github_note_storage.dart
│   │   │   ├── github_sync_engine.dart
│   │   │   └── repo_cache.dart
│   │   └── local/
│   │       └── local_note_storage.dart
│   ├── search/                    # 그대로 복사
│   │   ├── note_search_index.dart
│   │   ├── note_search_query.dart
│   │   └── search_result.dart
│   ├── settings/                  # shortcuts 제거
│   │   ├── app_settings.dart
│   │   └── app_settings_controller.dart
│   ├── theme/                     # dimensions 모바일 조정
│   │   ├── app_colors.dart
│   │   ├── app_theme.dart
│   │   └── app_dimensions.dart
│   ├── screens/                   # 모바일 전용 신규 작성
│   │   ├── login_screen.dart
│   │   ├── repo_selection_screen.dart
│   │   ├── home_screen.dart
│   │   ├── calendar_screen.dart
│   │   ├── search_screen.dart
│   │   ├── settings_screen.dart
│   │   └── editor_screen.dart
│   └── widgets/                   # 모바일 전용 신규 작성
│       ├── calendar_widget.dart
│       ├── note_list_widget.dart
│       ├── editor_panel.dart
│       ├── markdown_preview.dart
│       ├── markdown_toolbar.dart
│       └── search_results_widget.dart
├── test/
├── pubspec.yaml
├── analysis_options.yaml
├── android/
└── ios/
```

## 코드 복사 전략

### 그대로 복사 (변경 없음)
- `models/note.dart`
- `services/note_service.dart`
- `storage/note_storage.dart`, `sync_engine.dart`, `conflict_resolver.dart`
- `storage/github/` 전체
- `search/` 전체
- `theme/app_colors.dart`, `theme/app_theme.dart`

### 복사 후 수정
- `auth/github_oauth_provider.dart`: loopback → ASWebAuth/ChromeCustomTabs
- `storage/local/local_note_storage.dart`: 경로를 `getApplicationDocumentsDirectory()` 고정
- `settings/app_settings.dart`: shortcuts 관련 필드 제거
- `settings/app_settings_controller.dart`: shortcuts 관련 로직 제거
- `theme/app_dimensions.dart`: 모바일 spacing/sizing 값 조정

### 신규 작성
- `main.dart`
- `screens/` 전체 (7개 파일)
- `widgets/` 전체 (6개 파일)
