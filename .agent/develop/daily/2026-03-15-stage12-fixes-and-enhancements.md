# 2026-03-15 개발 일지

## 작업 목적

Stage 1+2에서 발견된 버그 3건을 수정하고, 단축키 설정 카테고리와 검색 UI 재설계를 구현한다.

## Confirmed Requirements

### Phase 1: 버그 수정

- RepoSelectionScreen이 SharedPreferences에 직접 접근하여 AppSettingsController와 동기화되지 않는 문제를 수정한다.
- 로컬 경로 변경 시 이전 local 노트가 UI에 남아있는 문제를 수정한다 (didUpdateWidget에서 즉시 제거).
- 검색 progress bar가 매 노트 저장 시 나타나는 문제를 제거한다 (in-memory rebuild는 즉각적이므로 불필요).

### Phase 2: 기능 추가

- ShortcutBinding 모델을 추가하고 Settings에 Shortcuts 카테고리를 넣는다.
- SearchResult 모델과 searchWithContext 메서드를 추가하여 매칭 라인 + context lines를 반환한다.
- 검색 UI를 상단 중앙 검색창 + 좌측 결과 패널 + 키워드 하이라이트 방식으로 재설계한다.
- Cmd+Shift+F 단축키로 검색 모드 진입을 지원한다.
- Settings Editor pane에 searchContextLines stepper를 추가한다.

## 변경 파일

### 수정 (12개)

| 파일 | 변경 내용 |
|------|----------|
| `lib/main.dart` | RepoSelectionScreen에 settingsController 전달 |
| `lib/screens/document_screen.dart` | didUpdateWidget local 노트 즉시 제거, _isSearchLoading 제거, searchWithContext 사용, 타이틀바 검색 UI, 결과 패널, ShortcutBinding 기반 키 핸들링 |
| `lib/screens/repo_selection_screen.dart` | SharedPreferences 직접 접근 제거, AppSettingsController 사용 |
| `lib/screens/settings_screen.dart` | Shortcuts pane 추가, 키 캡처 다이얼로그, searchContextLines stepper, nav rail 스크롤 가능하게 변경 |
| `lib/search/note_search_index.dart` | searchWithContext 메서드 추가 |
| `lib/settings/app_settings.dart` | searchContextLines 필드 추가 |
| `lib/settings/app_settings_controller.dart` | shortcut binding persistence, searchContextLines persistence 추가 |
| `lib/widgets/note_search_section.dart` | 타이틀바용 compact 형태로 리팩토링 (filter chips 제거, 높이 30px) |
| `test/search/note_search_index_test.dart` | searchWithContext 테스트 3건 추가 |
| `test/settings/settings_screen_test.dart` | Shortcuts nav 항목 검증 추가 |
| `test/widget_test.dart` | RepoSelectionScreen path 동기화, local 노트 즉시 제거 테스트 추가 |
| `test/widgets/note_search_section_test.dart` | compact 형태에 맞게 갱신 |

### 신규 (4개)

| 파일 | 내용 |
|------|------|
| `lib/search/search_result.dart` | SearchMatch, SearchResult 모델 |
| `lib/settings/shortcut_binding.dart` | ShortcutAction enum, ShortcutBinding 모델, defaultShortcutBindings |
| `lib/widgets/search_results_panel.dart` | 검색 결과 리스트 패널 (키워드 하이라이트, context lines, 줄번호) |
| `test/search/search_result_test.dart` | SearchMatch, SearchResult 필드 접근 테스트 |

## 검증 결과

- `flutter analyze`: No issues found
- `flutter test`: 85/85 passed

## 코드 리뷰 피드백

- Critical: 없음
- Important (수정 완료): SearchResultsPanel no-op 리사이즈 핸들 -> VerticalDivider 교체, shortcut_binding.dart dead code 제거
- Suggestions: shortcut_binding_test.dart 미생성, app_settings_controller_test.dart 미갱신, document_screen_test.dart 검색 UI 테스트 미추가

## PR

- https://github.com/bbaktaeho/simsync/pull/12
- base: develop
