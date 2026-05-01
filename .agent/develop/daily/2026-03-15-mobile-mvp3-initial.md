---
title: Mobile MVP3 초기 구현
date: 2026-03-15
pr: "#13"
branch: feature/mobile-mvp3
---

# Mobile MVP3 초기 구현

## 목적

Flutter 모바일 앱(Android/iOS) 신규 구현. `desktop/` 비즈니스 로직을 `mobile/`로 복제하고 모바일 전용 UI를 작성.

## 주요 구현

### 인증
- GitHub OAuth + PKCE (Custom URL Scheme `simsync://callback`)
- `app_links` 패키지로 deep link 수신 (WidgetsBindingObserver 방식은 Android에서 동작하지 않음)
- 모바일 전용 GitHub OAuth App 필요 (redirect URI가 다르므로 desktop과 별도)

### 화면 구성 (Bottom Navigation)
- **CalendarScreen**: 접기/펼치기 가능한 월간 캘린더, 날짜별 노트 목록, 노트 dot 표시
- **SearchScreen**: 전문 검색, 날짜/태그 필터, 키워드 하이라이팅
- **SettingsScreen**: iOS 스타일 그룹 리스트 (동기화, 에디터, 계정)
- **EditorScreen**: 마크다운 툴바 (H1/H2/H3/B/I/code 등), 핀치 줌, 자동 저장
- **LoginScreen**: 반응형 카드 레이아웃
- **RepoSelectionScreen**: 저장소 생성/연결

### desktop에서 복제한 로직 (19 파일)
- models/, services/, storage/, search/, auth/ (session, policy, store), theme/

### 모바일 적응 변경
- `github_oauth_provider.dart`: loopback 서버 -> Custom URL Scheme + Completer
- `app_settings_controller.dart`: 단축키 관련 코드 제거
- `app_dimensions.dart`: 사이드바 상수 제거, 모바일 전용 상수 추가
- `main.dart`: `app_links` deep link, `getApplicationSupportDirectory()` 기반 경로

## 발견 및 수정한 이슈

| 이슈 | 원인 | 수정 |
|------|------|------|
| GitHub token 교환 실패 | Android INTERNET 권한 누락 | AndroidManifest.xml에 `uses-permission` 추가 |
| deep link 수신 안됨 | WidgetsBindingObserver가 custom scheme 미지원 | `app_links` 패키지로 교체 |
| RepoCache 파일 생성 실패 | Android에서 `Platform.environment['HOME']` = null | `getApplicationSupportDirectory()` 사용 |
| 캘린더 화면 렌더링 안됨 | `intl` 한국어 로케일 미초기화 | `initializeDateFormatting('ko')` 추가 |
| 연결 버튼 텍스트 잘림 | 고정 height: 36 | padding 기반으로 변경 |

## 변경 파일

- 신규 109 파일 (`mobile/` 전체, `docs/plan/006-*`)
- 수정 1 파일 (`.gitignore`)

## 검증

- `flutter analyze`: no issues
- `flutter test`: passed
- debug APK 빌드 및 실기기 테스트 완료
