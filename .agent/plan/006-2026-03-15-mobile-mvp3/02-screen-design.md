---
title: 화면별 상세 UI 설계
type: design
created: 2026-03-15
---

# 화면별 상세 UI 설계

## 네비게이션 흐름

```
LoginScreen → RepoSelectionScreen → HomeScreen (Bottom Nav)
                                        ├── CalendarScreen (탭 1)
                                        ├── SearchScreen (탭 2)
                                        └── SettingsScreen (탭 3)
                                              ↓
                                    EditorScreen (push)
```

- 세션 유효 + 캐시된 레포 → HomeScreen 직행
- 로그아웃 → LoginScreen으로 전체 교체

## 1. LoginScreen

- GitHub OAuth 로그인 버튼 (Continue with GitHub)
- ASWebAuthenticationSession (iOS) / Chrome Custom Tabs (Android) 사용
- 로그인 성공 시 RepoSelectionScreen 또는 HomeScreen으로 전환

## 2. RepoSelectionScreen

- 레포 생성 또는 기존 레포 연결
- 캐시된 레포 목록 표시
- 선택 후 HomeScreen으로 전환

## 3. HomeScreen

- Bottom Navigation Bar: 캘린더, 검색, 설정 (3탭)
- 각 탭은 IndexedStack으로 상태 유지

## 4. CalendarScreen

### AppBar
- GitHub 프로필 아바타 (좌측)
- 현재 년/월 표시
- 이전/오늘/다음 월 이동 버튼
- 동기화 상태 인디케이터 (우측)

### 캘린더 그리드
- 월간 뷰, 접기/펼치기 지원
- 펼침: 전체 캘린더 그리드 + "접기" 핸들
- 접힘: 선택된 날짜 뱃지 (요일 + 날짜 + 노트 개수) + "펼치기" 핸들
- 노트가 있는 날짜에 dot 표시
- 선택된 날짜 primary 색상 하이라이트

### 노트 목록
- 선택된 날짜의 노트 카드 리스트
- 카드: 제목 + storage type 뱃지(synced/local) + 내용 미리보기(2줄) + 태그 칩
- 탭 → EditorScreen push
- 스와이프 → 삭제 (확인 다이얼로그)
- "+ 새 노트" 버튼: 선택 날짜에 노트 생성 후 EditorScreen push

## 5. EditorScreen

### AppBar
- 뒤로 가기 (← + 날짜 표시)
- 저장 상태 인디케이터 (저장됨 / 저장 중...)
- 더보기 메뉴 (⋮): 삭제, storage type, 생성일/수정일

### 탭 바
- Editor | Preview | Tags (3탭 전환)

### Editor 탭
- 제목 입력 필드
- 마크다운 본문 편집 영역 (모노스페이스 폰트)
- 1초 debounce auto-save
- 핀치 줌 (0.8x ~ 2.0x)
- 뒤로 가기 시 미저장 변경 즉시 저장

### 마크다운 툴바 (키보드 위)
- 키보드 활성 시에만 표시
- 버튼 구성 (횡스크롤):
  - H1 | H2 | H3 | 구분선 | B | I | code | 구분선 | ● | ☑ | ❝ | 🔗
- 동작:
  - H1/H2/H3: 줄 앞에 #/##/### 삽입
  - B/I/code: 선택 영역 감싸기 (**/*/`)
  - ●: 줄 앞에 "- " 삽입
  - ☑: 줄 앞에 "- [ ] " 삽입
  - ❝: 줄 앞에 "> " 삽입
  - 🔗: [text](url) 삽입 (선택 영역을 text에 배치)

### Preview 탭
- flutter_markdown으로 렌더링
- 코드 블록 syntax highlighting
- 핀치 줌 지원

### Tags 탭
- 콤마 구분 태그 입력 (데스크톱과 동일)

## 6. SearchScreen

### 검색바
- 텍스트 입력 필드 + 필터 버튼
- 필터 활성 시 버튼에 dot 표시

### 활성 필터 칩
- 검색바 아래에 칩으로 표시 (태그, 날짜 범위)
- 칩의 X 버튼으로 개별 해제

### 필터 Bottom Sheet (필터 버튼 탭 시)
- 태그 필터: 전체 태그 목록에서 선택/해제
- 날짜 범위: 시작일/종료일 date picker + 빠른 선택 (오늘, 이번 주, 이번 달)

### 검색 결과
- 결과 카드: 제목 + 날짜 + 키워드 하이라이트 context lines + 줄번호 + 태그/storage type
- 탭 → EditorScreen push

## 7. SettingsScreen

iOS 스타일 그룹드 리스트.

### Storage
- 로컬 저장 경로: 읽기 전용 (앱 내부 저장소 고정)
- 동기화 저장소: GitHub 연결 레포 표시

### Editor & Preview
- 기본 배율: stepper (0.8x ~ 2.0x, 기본 1.0x)
- 검색 컨텍스트 줄 수: stepper (1 ~ 10, 기본 3)

### Sync
- GitHub 동기화: 토글 스위치
- 동기화 주기: stepper (5 ~ 300초, 기본 5초)

### Account
- GitHub 프로필 (아바타 + 사용자명)
- 로그아웃 버튼

### App Info
- 버전 표시
