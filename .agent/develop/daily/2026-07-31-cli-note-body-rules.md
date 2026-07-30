---
title: CLI 노트 본문 작성 규칙 상시 노출
description: note new가 본문 작성 규칙 요약을 항상 출력, note-format 가이드에 서식 규칙과 템플릿 예시 추가
type: develop
created: 2026-07-31
related:
  - .agent/plan/018-2026-07-31-cli-note-body-rules/plan.md
---

# 2026-07-31 — CLI 노트 본문 작성 규칙 상시 노출

## 요구사항

- CLI로 노트/메모 작성 시 항상 서식 템플릿이 제공될 것
- 서식: 헤더 필수, `- ` 리스트, `백틱` 강조, 코드블록, 정돈된 내용은 표
- "모든 명령에 --help 선행 강제(2회 호출)" 아이디어 검토 요청

## 결정

- 2회 호출 게이트는 채택하지 않음 (상태 추적 필요, 영구적 2배 비용, agent의
  즉시 우회 학습 — 상세는 plan 참고). 대신 쓰기 명령 출력에 규칙을 동봉해
  추가 호출 없이 노출을 보장한다.
- 스캐폴드 파일에 보일러플레이트 본문을 심지 않는다 — 규칙은 stdout으로.

## 구현

- `cli/guides/note-format.md` + 데스크톱 `agent_harness.dart` `_noteFormatMd`:
  "본문 작성 규칙" 섹션(5개 규칙) + 들여쓰기 코드블록 형태의 템플릿 예시.
  두 사본은 동일 유지 계약(guide.go 주석)에 따라 같은 내용.
- `cli/note.go`: 스캐폴드 직후 규칙 5줄 요약 출력. 마지막 줄 = 파일 절대
  경로 계약은 유지.
- `cli/main.go`: note new 설명에 "본문 작성 규칙 요약을 함께 출력" 명시.

## 알려진 한계

- 기존 스토어의 `.agents/note-format.md`는 create-only 하네스라 자동 갱신
  안 됨 + `guide`는 클론 우선. 작성 순간은 note new 출력이 커버. 기존
  스토어 갱신은 소유자 몫.

## 검증

- cli: go test 통과, go vet/gofmt clean
- desktop: flutter analyze clean, agent_harness/전체 테스트 통과
- v0.3.2 릴리즈 자산(CLI tarball 2종, DMG) 재빌드 후 교체 반영
