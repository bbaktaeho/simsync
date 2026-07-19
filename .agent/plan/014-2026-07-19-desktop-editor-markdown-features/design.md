---
title: 데스크톱 에디터 마크다운 기능 확장 설계
description: 이미지 첨부/뷰어, details 접기 + 인용문 `|`, 코드 언어 자동 감지, 포맷팅 단축키 설계
type: design
created: 2026-07-19
status: draft
---

# 데스크톱 에디터 마크다운 기능 확장 설계

## 배경

데스크톱 에디터는 단일 TextField + 3층 렌더링 구조다. 원본 마크다운을 그대로 유지하면서:

1. `MarkdownEditingController.buildTextSpan` — 인라인 스타일링 (문자 보존 invariant: 스팬 연결 == 원본 텍스트)
2. `EditorBlockDecorationPainter` — 필드 뒤 CustomPaint로 코드 박스/인용 바 배경
3. Positioned overlay — 테이블 마크다운을 투명 처리하고 위에 `InlineTableView` 위젯을 겹침

이번 기능은 모두 이 구조 위에 얹는다. 이미지 뷰어와 details 접기는 3번 overlay 패턴을 따른다.

## 확정 요구사항 (소유자 승인)

| # | 요구사항 | 결정 |
|---|---------|------|
| 1 | 이미지 첨부/뷰어 | 로컬 + synced(GitHub) 노트 모두 지원 |
| 2 | 이미지 크기 조절 | `<img src width height>` HTML로 저장 (GitHub 웹에서도 크기 반영) |
| 3 | details 접기 | `<details><summary>` HTML로 저장, 에디터에서 `>` 입력이 생성 트리거 |
| 4 | 인용문 | `> ` 대신 `\| ` 프리픽스 |
| 5 | 코드 하이라이팅 | 이미 존재. fence 언어 미지정 시 자동 감지 추가 |
| 6 | 포맷팅 단축키 | cmd+B 등. cmd+X는 Cut 충돌로 cmd+shift+X 채택 |

## 1. 이미지 첨부 및 뷰어

### 첨부 흐름

- **붙여넣기**: 클립보드에 이미지가 있으면 가로채서 저장 + 태그 삽입. 의존성 `pasteboard` 추가 (Flutter 기본 Clipboard는 텍스트 전용. `super_clipboard`는 Rust 툴체인이 필요해 제외)
- **파일 첨부**: 툴바 이미지 버튼, 기존 `file_picker` 재사용
- 지원 확장자: png, jpg/jpeg, gif, webp. 클립보드 붙여넣기는 png로 저장

### 저장

- 경로: 노트의 날짜 디렉토리 하위 `assets/`
  - synced: `notes/{YYYY-MM}/{DD}/assets/img-{yyyyMMdd-HHmmss}-{난수4}.png`
  - 로컬: `~/.simsync/documents/{YYYY-MM-DD}/assets/img-...png`
  - 마크다운에는 노트 파일 기준 상대 경로(`assets/...`)로 기록 → GitHub 웹에서도 렌더링됨
- `NoteStorage` 인터페이스에 bytes API 추가: `writeBinaryFile(path, bytes)`, `readBinaryFile(path)`. 구현체 3개(`NoteService`, `LocalNoteStorage`, `GithubNoteStorage`) 모두 구현
- `GithubApiClient`는 현재 utf8 강제 인코딩(`putFile`이 `base64(utf8.encode(...))`)이라 raw bytes를 base64로 직접 올리는 `putBinaryFile` 추가
- 업로드 시점: 붙여넣기/첨부 즉시 (현재 노트 저장이 remote-first이므로 일관). 실패 시 태그 삽입하지 않고 에러 표시
- 이미지 태그 삭제 시 파일은 남는다 (orphan 정리는 범위 외)

### 렌더링 / 크기 조절

- 저장 문법: `<img src="assets/xxx.png" width="300" height="200">`
  - height까지 저장하는 이유: 에디터가 이미지 파일을 디코딩하기 전에 해당 줄의 세로 공간을 예약해야 하기 때문 (핵심 레이아웃 제약)
- 렌더링은 테이블 overlay 패턴 그대로:
  - img 태그 줄은 buildTextSpan에서 투명 처리 + 줄 높이를 이미지 표시 높이로 예약
  - 그 위에 Positioned overlay로 이미지 위젯 표시
- 상호작용: 클릭 → 선택 상태 → 모서리 드래그 핸들 → 비율 고정 리사이즈 → 드롭 시 width/height 속성 재기록
- synced 노트 이미지 로딩: Contents API로 fetch → 메모리 + 디스크 캐시 (경로+sha 키)

## 2. details 접기 + 인용문 `|`

### details

- 저장 포맷: `<details><summary>제목</summary>` … `</details>`. GitHub 웹에서 네이티브 접힘 동작
- 접힘 상태는 `<details open>` 속성으로 파일에 지속 → 디바이스 간, GitHub 웹과 상태 공유
- 입력: 줄 시작에서 `> ` 입력 시 details 스켈레톤 자동 삽입 (기존 `MarkdownListInputFormatter` 패턴의 input formatter)
- 렌더링: summary 줄 왼쪽에 ▸/▾ 토글 + 제목 강조 스타일. (최종 2026-07-19) 에디터 내 본문 접힘은 실제 높이 0으로 동작한다 — 측정 아키텍처를 미러 TextPainter에서 RenderEditable 직접 조회로 전환하고 극소 명시 스트럿을 도입해 해결(plan 02 문서 번복 기록). 접힘 상태는 open 속성으로 파일에 저장되어 GitHub 웹/타 디바이스와 공유
- 하위 호환: 기존 노트의 `> ` 줄은 계속 인용문으로 렌더링. 마이그레이션 없음. `>`는 입력 트리거로만 details 생성

### 인용문 `|`

- `| ` 프리픽스로 변경. 수정 지점 3곳:
  - `markdown_editing_controller.dart` `_blockquote` 정규식
  - `editor_block_decorations.dart` `_quote` 정규식
  - `editor_panel.dart` `_blockPrefixes`
- 테이블과 구분: 테이블 감지에 구분선 행(`|---|`) 필수 규칙 적용. 구분선 없는 `| 텍스트` 줄은 인용문
- GitHub 웹에서는 `| 텍스트` 그대로 노출됨 (비표준 감수 — 소유자 승인됨)

## 3. 코드 언어 자동 감지

- fence(``` ```)에 언어가 없으면 블록 전체 텍스트로 `highlight` auto-detection 1회 실행
- 감지 결과를 블록 내용 키로 캐시 (기존 줄 단위 파스 캐시와 별도)
- relevance가 낮으면 무채색 유지 (오탐 방지)

## 4. 포맷팅 단축키

| 기능 | 단축키 | 동작 |
|------|--------|------|
| bold | cmd+B | `**` 감싸기 토글 |
| italic | cmd+I | `*` 감싸기 토글 |
| 취소선 | cmd+shift+X | `~~` 감싸기 토글 |
| 인라인 코드 | cmd+E | `` ` `` 감싸기 토글 |
| 링크 | cmd+K | `[텍스트](url)` 삽입/감싸기 |
| 체크박스 | cmd+shift+C | `- [ ] ` 줄 프리픽스 토글 |
| 하이라이트 | cmd+shift+H | `==` 감싸기 토글 |

- `ShortcutAction` enum + `defaultShortcutBindings` 확장 (`settings/shortcut_binding.dart`)
- 동작은 툴바가 쓰는 `_wrapSelection` / `_toggleLinePrefix` 재사용
- 설정 화면 리바인딩은 기존 구조 그대로 지원

## 테스트

- char-preservation invariant 테스트를 신규 렌더링(img 줄, details 영역, `|` 인용문)에 확장
- 단위 테스트: img 태그 파싱/속성 재기록, details 영역 파싱/open 토글, `|` 인용문 vs 테이블 구분, 단축키 매칭, 바이너리 스토리지 API(utf8 우회 base64 왕복)
- `flutter analyze` clean 유지

## 범위 외

- mobile 적용 (인라인 에디터 구조 자체가 없음)
- 드래그&드롭 첨부
- orphan 이미지 정리
- 이미지 압축/최적화
- 클립보드 이미지 외 파일 타입 첨부

## 가정

- 로컬 노트는 `NoteService`(`~/.simsync/documents/`) 경유, synced 노트는 `GithubNoteStorage` 경유 — 두 경로 모두 이미지 지원
- 로컬-first 동기화 재작업(별도 계획)과 충돌하지 않도록, 이미지 업로드도 노트 저장과 동일한 스토리지 인터페이스만 사용
