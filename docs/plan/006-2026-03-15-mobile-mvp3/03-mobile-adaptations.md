---
title: 데스크톱 대비 모바일 적응 포인트
type: design
created: 2026-03-15
---

# 모바일 적응 포인트

## OAuth

| 항목 | Desktop | Mobile |
|------|---------|--------|
| 방식 | Loopback redirect (127.0.0.1 로컬 서버) | ASWebAuthenticationSession (iOS) / Chrome Custom Tabs (Android) |
| 패키지 | url_launcher + dart:io HttpServer | flutter_appauth 또는 url_launcher + Custom URL Scheme |
| Redirect URI | http://127.0.0.1:{port}/callback | simsync://callback (Custom URL Scheme) |

## 로컬 저장소

| 항목 | Desktop | Mobile |
|------|---------|--------|
| 기본 경로 | ~/Documents/SimSync | getApplicationDocumentsDirectory()/SimSync |
| 경로 변경 | file_picker로 사용자 선택 가능 | 고정, 변경 불가 |
| 설정 UI | Change... 버튼 | 읽기 전용 표시 |

## 설정

| 항목 | Desktop | Mobile |
|------|---------|--------|
| UI 형태 | Dialog + master-detail (category rail + detail pane) | 전체 화면 그룹드 리스트 |
| 진입 방식 | Cmd+, 단축키 또는 메뉴 | Bottom Nav 설정 탭 |
| Shortcuts 카테고리 | 있음 (커스텀 바인딩) | 없음 |
| Content zoom 조작 | Cmd++/-, 마우스 휠, 트랙패드 핀치 | 핀치 줌 + 설정 stepper |

## 네비게이션

| 항목 | Desktop | Mobile |
|------|---------|--------|
| 레이아웃 | 3-panel (캘린더 사이드바 + 노트 목록 + 에디터) | Single screen + Bottom Nav |
| 에디터 진입 | 노트 목록에서 선택 시 같은 화면 내 에디터 패널 | Navigator.push로 전체 화면 전환 |
| 검색 | 상단 중앙 검색바 + 좌측 결과 패널 | 전용 탭 (SearchScreen) |
| 캘린더 | 사이드바, 접기/펼치기 | 메인 탭, 접기/펼치기 |

## 에디터

| 항목 | Desktop | Mobile |
|------|---------|--------|
| 마크다운 입력 보조 | 키보드 단축키 (Cmd+B, Cmd+I 등) | 키보드 위 마크다운 툴바 |
| 툴바 버튼 | 없음 (단축키 사용) | H1, H2, H3, B, I, code, ●, ☑, ❝, 🔗 |
| 줌 | Cmd++/-, 마우스 휠, 핀치 | 핀치 줌만 |

## 의존성 변경

### 제거 (모바일 불필요)
- `file_picker` (로컬 경로 고정)

### 추가 (모바일 전용)
- `flutter_appauth` 또는 동등한 OAuth 패키지 (ASWebAuth/ChromeCustomTabs)

### 유지
- `flutter_markdown`, `flutter_highlight`, `highlight`
- `http`, `shared_preferences`, `path_provider`
- `uuid`, `intl`, `yaml`, `crypto`, `markdown`
- `google_fonts`, `url_launcher`, `cupertino_icons`
