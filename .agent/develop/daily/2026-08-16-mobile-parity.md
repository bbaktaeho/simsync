---
title: Mobile Parity (Design / Auth / Editor)
description: 모바일을 데스크탑에 맞춤 — 디자인 시스템, device flow 인증, 인라인 마크다운 에디터
type: develop
created: 2026-08-16
---

# Mobile Parity

AI 분석을 제외한 데스크탑의 디자인·인증·기능을 모바일(Android)에 맞췄다.

## 1. 디자인 시스템

- `app_colors.dart`를 데스크탑 것으로 교체. **모바일에는 다크 팔레트 자체가
  없었다.** `calendarWeekend`도 함께 들어왔다.
- 라디우스 별칭(`borderRadius`/`Sm`/`Lg`, 그리고 스케일 밖 `cardBorderRadius=10`)
  56곳을 정식 토큰으로 옮기고 별칭 삭제. 10은 `radiusComfortable`(12)로 흡수.
- `buildDarkTheme`, `filledButtonTheme`, `outlinedButtonTheme` 추가.
  버튼 최소 높이는 모바일 터치 타깃에 맞춰 44.
- 설정에 `themeMode`(시스템/라이트/다크) + Appearance 섹션 신설. MaterialApp
  위의 `ValueNotifier<ThemeMode>`로 앱 전체에 적용 (데스크탑과 같은 구조).
- 캘린더 주말 색 적용.

## 2. 인증 — device flow

- `auth_provider`/`auth_service`/`github_oauth_provider`를 데스크탑에서 이식.
  **클라이언트 시크릿이 더는 필요 없다** — 공개 client id만 쓴다.
- 로그인 화면에 코드 다이얼로그 추가(코드 자동 복사 + GitHub 열기 + 취소).
- `simsync://callback` 딥링크 처리와 `app_links` 의존성 제거, 안드로이드
  매니페스트의 인텐트 필터도 삭제.
- 데스크탑의 인증 테스트 5종을 그대로 이식.

## 3. 에디터 — 인라인 렌더링

미리보기 탭과 별개로, 본문 편집기를 데스크탑과 같은 인라인 렌더링으로 바꿨다.

- `markdown_editing`(서비스), `markdown_editing_controller`,
  `editor_block_decorations`, `editor_overlay_layout`, `inline_table_view`를
  데스크탑에서 **수정 없이** 이식 (테마 토큰이 같아지자 그대로 컴파일됐다).
- 모바일 `EditorPanel` 재작성: 인라인 렌더 + 코드/인용문/규칙선 데코 +
  표 오버레이 + 탭하면 토글되는 체크박스. 호버/툴팁/Tab은 없고, 체크박스는
  그림 크기는 그대로 두고 탭 영역만 손가락 크기로 넓혔다.
- 리스트 자동 이어쓰기, `> ` details 스켈레톤, `[]` 단축 입력 포매터 연결.

## 검토에서 잡은 것

1. **표/이미지가 사라질 뻔했다.** 컨트롤러는 표·이미지 줄을 "오버레이가 그릴
   것"이라 보고 숨긴다. 오버레이 없이 컨트롤러만 이식하면 그 줄이 통째로
   투명해진다. 표는 오버레이를 이식해 해결했고, 이미지는 모바일에 저장 API
   (`noteDirPath`/`readBinaryFile`/`writeBinaryFile`)가 없어 컨트롤러에
   `renderInlineImages` 플래그를 두고 모바일에서 원문을 그대로 렌더한다.
   (데스크탑 컨트롤러에 플래그를 추가해 두 파일을 동일하게 유지했다.)
2. **콘텐츠 배율이 굳는다.** 에디터가 설정을 구독하지 않아 배율을 바꿔도 다른
   이유로 리빌드될 때까지 반영되지 않았다. `ListenableBuilder`로 감쌌다.
3. **죽은 위젯 4개.** `CalendarWidget`, `NoteListWidget`, `SearchResultsWidget`,
   `MarkdownToolbar`가 화면에서 전혀 쓰이지 않았다 — 화면들이 각자 인라인으로
   구현하고 있었다. 특히 **주말 색을 처음에 죽은 `calendar_widget.dart`에
   넣어서** 실제 화면에는 반영되지 않았다. 진짜 캘린더인 `calendar_screen.dart`에
   다시 적용하고 죽은 파일 4개 + 죽은 `conflict_resolver.dart`를 삭제했다.
   (반대로 `SyncEngine` 추상은 두 화면이 타입으로 써서 살아 있다 — 데스크탑에서
   지웠다고 따라 지우지 않았다.)

## 검증

- `flutter analyze` clean (양쪽), 모바일 143개 / 데스크탑 528개 통과.
- 모바일 테스트는 68(마크다운 서비스) + 34(렌더링) + 8(에디터 위젯) + 인증 5종을
  새로 이식/추가한 결과다.
- `flutter build apk --debug` 성공 — **시크릿 없이 빌드된다**.

## 남은 것

- 이미지 첨부/표시: 스토리지 바이너리 API(`readBinaryFile` 등)를 모바일 쪽에
  구현해야 한다. 데이터 경로를 건드리는 작업이라 이번 범위에서 분리했다.
- AI 분석(위클리/먼슬리 리뷰)은 요청대로 제외했다.

## 4. 하단 마크다운 툴바 (모바일 입력 보조)

모바일은 타이핑이 비싸다. 자주 쓰는 문법을 전부 하단 버튼으로 뺐다.

**기존 툴바의 문제** — 손보기 전에 잡은 것:

- `_insertAtLineStart`가 프리픽스를 **그냥 덧붙였다**. 목록 버튼을 두 번 누르면
  `- - `, 체크박스에 목록을 누르면 `- - [ ] `가 됐다.
- 인용 버튼이 `> `를 넣었다. 이 앱의 인용 문법은 `| `이고 `> `는 details 생성
  트리거다 (타이핑할 때만 포매터가 변환하므로 버튼으로 넣으면 레거시 인용문이
  그대로 남는다).
- 들여쓰기 버튼이 없었다. 데스크탑은 Tab으로 하는데 **모바일에는 Tab이 없다**.

**바꾼 것**:

- 데스크탑 `editor_panel`에만 있던 `_wrapSelection`/`_toggleLinePrefix`를
  `services/markdown_editing.dart`로 올려 순수 함수(`wrapSelection`,
  `toggleLinePrefix`)로 만들고 양쪽이 같이 쓴다. 데스크탑도 이 함수를 호출하도록
  바꿨다 — 두 플랫폼의 서식 동작이 어긋날 수 없다.
- 버튼 구성(자주 쓰는 순): 할 일 · 목록 · 번호 목록 | 내어쓰기 · 들여쓰기 |
  H1 · H2 · H3 | B · I · 취소선 · 형광펜 · 인라인 코드 | 인용 · 링크 ·
  코드 블록 · 표 · 구분선, 그리고 오른쪽 고정으로 키보드 닫기.
- 들여쓰기/내어쓰기는 데스크탑 Tab과 같은 `indentListSelection`을 쓴다.
- 아이콘만으로 뜻이 안 보이는 버튼에는 길게 눌러 뜨는 설명을 붙였다.

검증: 툴바 동작 테스트 6개 추가(토글/교체/들여쓰기/인용 문법/표/감싸기).
모바일 149개 통과.

## 5. 검토 3회 (툴바 포함 전체)

### 검토 1 — 기능 매트릭스

데스크탑 기능을 하나씩 대조했다. AI 제외 후 모바일에 없던 것:

- **로컬↔동기화 노트 전환** (`note_conversion.dart`) — 없었다
- **이미지 첨부/표시** — 없었다
- `update_checker`(스토어 배포라 무의미), `agent_harness`(데스크탑 스토어 기능),
  `note_merge`(모바일 에디터는 `_isDirty || _isSaving` 가드로 이미 보호 중) — 제외 확정

앞의 두 개는 뿌리가 같았다: 스토리지의 바이너리 파일 API가 모바일에 없었다.
`getRawFile`/`putBinaryFile`(API 클라이언트), `readTextFile`/`writeTextFile`/
`readBinaryFile`/`writeBinaryFile`/`noteDirPath`(NoteStorage 인터페이스 + 로컬/
GitHub/NoteService 구현)를 이식하고 나니 둘 다 열렸다.

- 이미지: `ImageAssetService` + `InlineImageView` 이식, 에디터 화면에서 로더 주입.
  로더가 없으면 `renderInlineImages=false`로 원문을 그대로 보여준다(안전 기본값).
- 전환: 노트 롱프레스 메뉴에 "동기화/로컬 노트로 전환" 추가. 데스크탑 테스트
  8개를 그대로 이식해 통과.

### 검토 2 — 모바일 적합성

- **체크박스 그림이 6px 밀려 있었다.** 탭 영역을 넓히려고 `EdgeInsets.all`을
  줬는데, 오버레이는 위젯의 왼쪽 끝을 `[` 위치에 맞춘다. 왼쪽 여백만큼 그림이
  밀린 것. 여백을 오른쪽·상하로만 주도록 고치고, **그림 기준**으로 위치를
  검증하는 테스트를 추가했다 (기존 테스트는 텍스트 메트릭만 봐서 못 잡았다).
- **표 위에서 스크롤이 죽었다.** 오버레이가 히트 테스트를 가져가는데 필드의
  Scrollable은 오버레이의 조상이 아니다. 데스크탑은 휠/트랙패드용으로 이미
  해결해 둔 문제의 터치판이다. 세로 드래그를 에디터 스크롤로 넘기는 래퍼를
  표·이미지·체크박스에 씌웠다. (표는 화면 폭을 다 쓰므로 체감이 컸다.)
- 툴바 버튼 터치 타깃 36 → 44 (툴바 높이 48 안에서 최대).

### 검토 3 — 정합성

- 서비스 계층(`markdown_editing.dart`)은 양쪽이 같은 파일이다. 서식 연산
  (`wrapSelection`/`toggleLinePrefix`)도 여기로 올려 두 플랫폼이 갈라질 수 없다.
- 모바일 `SyncEngine` 추상은 두 화면이 타입으로 쓰므로 유지 (데스크탑에서
  지웠다고 따라 지우지 않았다).
- 테스트 페이크 2종에 새 인터페이스 메서드를 채웠다.

## 최종 검증

- `flutter analyze` clean (양쪽)
- 모바일 **159개** / 데스크탑 **528개** 통과
- `flutter build apk --debug` 성공 (시크릿 없이)
