---
title: 데스크톱 에디터 마크다운 기능 확장 구현 계획
description: 이미지 첨부/뷰어, details 접기 + 인용문 |, 코드 자동 감지, 포맷팅 단축키 구현 계획 (task 15개)
type: plan
created: 2026-07-19
status: active
related:
  - .agent/plan/014-2026-07-19-desktop-editor-markdown-features/design.md
---

# 데스크톱 에디터 마크다운 기능 확장 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 데스크톱 에디터에 이미지 첨부/뷰어(리사이즈), `<details>` 접기(`>` 트리거) + `|` 인용문, 코드 언어 자동 감지, 포맷팅 단축키를 추가한다.

**Architecture:** 에디터는 단일 TextField + 3층 구조(인라인 스타일링 `buildTextSpan` / 배경 CustomPaint / Positioned 위젯 오버레이)다. 이미지와 details 토글은 테이블(`InlineTableView`)과 같은 오버레이 패턴을 따르고, 문자 보존 invariant(스팬 연결 == 원본 텍스트)를 절대 깨지 않는다. 스토리지는 `NoteStorage` 인터페이스에 bytes API를 추가해 로컬/GitHub 모두 지원한다.

**Tech Stack:** Flutter/Dart, highlight(하이라이팅), pasteboard(클립보드 이미지, 신규), file_picker, GitHub Contents API.

## Global Constraints

- 문자 보존 invariant: `buildTextSpan` 결과 스팬의 텍스트 연결은 항상 `controller.text`와 정확히 일치한다. 문자는 제거하지 않고 스타일만 바꾼다.
- 저장 포맷은 GitHub 웹 렌더링 호환 우선: `<details><summary>`, `<img src width height>` HTML. 인용문은 `| ` (비표준, 승인됨).
- `flutter analyze` clean 유지. 커밋은 conventional commit (`type: subject`, 한국어 subject 허용 — 기존 히스토리 관례).
- 변경 범위 최소화. 요청 밖 리팩토링 금지.
- 이모지 사용 금지 (코드 주석/문서).
- 테스트는 각 task에서 함께 작성 (TDD). 기존 테스트 깨뜨리지 않기.
- 브랜치: `feature/editor-markdown-features` (이미 생성됨), PR 대상은 `develop`.
- 모든 새 위젯/스타일은 `context.colors`(AppColorsExtension)와 `AppDimensions`를 사용.

## Task 목록 (상세는 개별 문서)

| Task | 내용 | 문서 |
|------|------|------|
| 1 | ShortcutAction enum 확장 + 기본 바인딩 | [01-shortcuts.md](01-shortcuts.md) |
| 2 | EditorPanelState 공개 + applyFormat + 전역 디스패치 | [01-shortcuts.md](01-shortcuts.md) |
| 3 | 취소됨 — 스트럿 전환 (02 문서 결정 기록 참조) | [02-quote-details.md](02-quote-details.md) |
| 4 | `\|` 인용문 (렌더링/데코/토글 + 테이블 구분) | [02-quote-details.md](02-quote-details.md) |
| 5 | findDetailsRegions 파싱 | [02-quote-details.md](02-quote-details.md) |
| 6 | details 렌더링 (접힘/펼침, 충돌 필터) | [02-quote-details.md](02-quote-details.md) |
| 7 | `> ` 입력 트리거 + 토글 오버레이 | [02-quote-details.md](02-quote-details.md) |
| 8 | 코드 언어 자동 감지 | [03-code-autodetect.md](03-code-autodetect.md) |
| 9 | NoteStorage bytes API + 로컬 2종 구현 | [04-images.md](04-images.md) |
| 10 | GitHubApiClient/GitHubNoteStorage 바이너리 | [04-images.md](04-images.md) |
| 11 | ImageAssetService (저장/로드/캐시) | [04-images.md](04-images.md) |
| 12 | findImageRegions + 에디터 높이 예약 | [04-images.md](04-images.md) |
| 13 | InlineImageView + 오버레이/리사이즈/삭제 | [04-images.md](04-images.md) |
| 14 | 붙여넣기 인터셉트 + 툴바 첨부 + 와이어링 | [04-images.md](04-images.md) |
| 15 | 통합 검증 + PR | 아래 |

의존 관계: Task 9 → 10 → 11 → 14 순서. Task 1 → 2. 나머지는 독립. (Task 3은 취소 — 이미지 높이 예약은 body 스트럿과 무관하게 동작)

## Task 15: 통합 검증 + PR

**Files:** 없음 (검증만)

- [ ] **Step 1: 정적 분석 + 전체 테스트**

Run: `cd /Users/bbaktaeho/github/simsync/desktop && flutter analyze && flutter test`
Expected: analyze 0 issues, 전체 테스트 PASS

- [ ] **Step 2: 수동 검증** (`flutter run -d macos`)

체크리스트:
1. cmd+B/I/E/K, cmd+shift+X/C/H 단축키 동작. cmd+X 잘라내기 정상 동작 유지
2. `| ` 인용문 렌더링(왼쪽 바), 기존 `> ` 노트 인용문 하위 호환
3. 줄 시작 `> ` 입력 → details 스켈레톤 생성, summary 좌측 chevron 토글로 에디터 안에서 본문이 실제로 접히고/펼쳐지며 `<details open>` 속성이 파일에 기록됨
4. 언어 미지정 ``` 블록에 dart/json 코드 입력 후 캐럿을 밖으로 → 자동 컬러링
5. 스크린샷 복사(cmd+ctrl+shift+4) 후 cmd+V → 이미지 표시, 텍스트 붙여넣기 정상, 우하단 핸들 리사이즈, X 삭제
6. 툴바 이미지 버튼 → 파일 첨부
7. synced 노트에 이미지 첨부 → GitHub repo에 `notes/{YYYY-MM}/{DD}/assets/` 커밋 확인, 웹에서 노트 열람 시 이미지/크기/details 접힘 확인
8. 회귀: 테이블 삽입/편집, 체크박스, 헤딩, 코드 박스, 빈 노트 캐럿 높이, 콘텐츠 줌(cmd+스크롤), 위클리 뷰
9. 앱 재시작 후 synced 이미지 로드 (디스크 캐시 확인)

- [ ] **Step 3: 커밋 정리 확인 및 PR 생성**

```bash
git log develop..HEAD --oneline   # task별 커밋 확인
git push -u origin feature/editor-markdown-features
gh pr create --base develop --title "feat: 에디터 이미지/details/코드 자동감지/포맷 단축키" --body "(설계/계획 문서 링크 + 요약 + 테스트 결과)"
```

Expected: PR 생성 완료. 병합은 소유자 확인 후.

## Self-Review 결과

- 스펙 커버리지: design.md의 6개 확정 요구사항 모두 task에 매핑됨 (이미지 1,9-14 / 크기 13 / details 5-7 / 인용문 4 / 자동감지 8 / 단축키 1-2)
- 스펙과 차이: 에디터 내 "본문 높이 접힘"은 실측 결과 제외됨 — 접힘 상태는 open 속성으로 파일/GitHub 웹에만 반영. 근거는 02 문서 결정 기록
- 타입 일관성: 인터페이스 시그니처는 각 문서 Interfaces 블록에 통일 기재
