---
title: Verification Strategy
description: 정적 분석 + 유닛/위젯 테스트 + golden + 사용자 수동 QA
type: plan
created: 2026-05-01
status: draft
related:
  - .agent/plan/001-2026-05-01-design-system-refresh/04-pr1-foundation.md
  - .agent/plan/001-2026-05-01-design-system-refresh/05-pr2-migration.md
---

# Verification Strategy

> "기능이 변경되지 않음"을 보장하기 위한 4-layer 검증.

## 1. 정적 분석

```bash
cd desktop && flutter analyze
cd mobile  && flutter analyze
```

- PR1, PR2의 매 커밋에서 **clean** (warning/info 무시 X)
- workflow.md Code Review Checklist의 Flutter 항목과 동일

## 2. 유닛/위젯 테스트

```bash
cd desktop && flutter test
cd mobile  && flutter test
```

- 기존 테스트가 통과해야 한다 (디자인 변경이 로직에 영향 없음을 확인)
- 신규 테스트는 PR2의 신규 컴포넌트 (`PrimaryButton` 등)에 한해 추가

## 3. Golden Tests (신규 도입)

PR1에서 baseline 생성, PR2에서 회귀 자동 감지.

### baseline 대상 (PR1 작업 후 생성)

| 화면 | 위치 |
|------|------|
| Login (desktop) | `desktop/test/golden/login_test.dart` |
| Document Workspace (desktop) | `desktop/test/golden/document_test.dart` |
| Settings (desktop) | `desktop/test/golden/settings_test.dart` |
| Login (mobile) | `mobile/test/golden/login_test.dart` |
| Calendar (mobile) | `mobile/test/golden/calendar_test.dart` |
| Editor (mobile) | `mobile/test/golden/editor_test.dart` |
| Search (mobile) | `mobile/test/golden/search_test.dart` |

### baseline 생성

```bash
cd desktop && flutter test --update-goldens
cd mobile  && flutter test --update-goldens
```

→ `.png` 파일이 `test/golden/` 아래 생성. 사용자가 한 번 시각 검토 후 커밋.

### 회귀 검증 (PR2 매 커밋)

```bash
cd desktop && flutter test
cd mobile  && flutter test
```

→ 픽셀 차이 시 테스트 실패 + diff 이미지 출력. 의도한 변경이면 `--update-goldens`로 baseline 갱신, 의도치 않으면 코드 수정.

### 주의

- 폰트 로딩이 비결정적이면 golden이 flaky해진다. PR1에서 Inter를 정적 번들 권장 (CDN-only이면 테스트 환경에서 fallback 폰트로 그려질 수 있음)
- macOS / Android / Linux에서 픽셀 미세 차이 가능 — CI 환경 일치 권장 (현 시점 CI 미정이면 로컬 macOS 기준)

## 4. 사용자 수동 QA

### Matrix

| 흐름 | desktop (macOS) | mobile (Android) |
|------|----------------|------------------|
| 앱 첫 실행 → OAuth 로그인 | ☐ | ☐ |
| Repo 선택 | ☐ | ☐ |
| 새 노트 생성 (날짜 선택 → 작성 → 저장) | ☐ | ☐ |
| 기존 노트 수정 | ☐ | ☐ |
| 노트 삭제 | ☐ | ☐ |
| 캘린더 월 이동 / today 표시 / 노트 있는 날짜 표시 | ☐ | ☐ |
| 태그 추가/삭제 | ☐ | ☐ |
| 태그 필터 | ☐ | ☐ |
| 검색 (날짜/태그/본문) | ☐ | ☐ |
| 검색 결과 하이라이트 | ☐ | ☐ |
| 동기화 (push/pull) | ☐ | ☐ |
| 충돌 발생 시 거동 (Last-Write-Wins) | ☐ | ☐ |
| 설정 변경 (로컬 경로, 동기화 토글 등) | ☐ | ☐ |
| 로그아웃 → 재로그인 | ☐ | ☐ |

### 시각 점검 포인트 (PR2 종료 시)

- [ ] 모든 카드가 whisper border + multi-layer shadow
- [ ] 본문이 Inter 16/400/1.50으로 보임
- [ ] 헤딩이 Inter 700 + negative letter-spacing
- [ ] CTA 버튼이 Notion Blue (`#0075de`) 단일 색
- [ ] 태그/상태가 pill 형태 + tinted blue bg
- [ ] 입력 필드가 1px 회색 border + 4px radius
- [ ] focus ring이 파란색 (`#097fe8`)
- [ ] section 간 vertical rhythm이 충분 (mobile 48 / desktop 80)
- [ ] 다크 모드 토글 UI 흔적 없음

## 5. 회귀 발생 시 대응

1. golden test 실패 → diff 이미지 확인
2. 의도한 변경이면: `flutter test --update-goldens` 후 baseline 갱신, PR 설명에 변경 사유 명시
3. 의도치 않으면: 코드 수정 후 재실행
4. 수동 QA에서 발견된 회귀: GitHub issue 등록 → 핫픽스 PR 분리

## Reference

- workflow.md 5단계 (잠재적 버그·크리티컬 이슈·보안 검토)
- workflow.md 8단계 (사이드 이펙트 검토)
- workflow.md 12단계 (사용자 흐름에서 문제가 없는지 확인)
