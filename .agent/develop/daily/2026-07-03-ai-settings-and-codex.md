---
title: AI 설정 통합 + Codex CLI 지원
description: 위클리/먼슬리 리뷰 생성에 Codex CLI 추가, 설정 Weekly/Monthly 카테고리를 AI 카테고리로 통합
type: develop
created: 2026-07-03
related:
  - .agent/plan/012-2026-07-03-ai-settings-and-codex/plan.md
---

# 2026-07-03 AI 설정 통합 + Codex CLI 지원

## 작업 내용

- `services/cli_process.dart` 신설: claude/codex가 공유하는 프로세스 러너
  (임시 작업 디렉토리 격리, Finder 실행용 PATH 구성, stdin 파이프, 타임아웃).
  기존 `ClaudeProcessResult`/`ClaudeProcessRunner`는 typedef alias로 유지.
- `services/codex_cli_service.dart` 신설: `codex exec --sandbox read-only
  --skip-git-repo-check --ephemeral --color never --output-last-message <tmp>`
  + instruction 인자 + 노트 stdin(`<stdin>` 블록) 패턴. 최종 응답은 파일로
  수신하고 stdout 진행 로그는 무시. 모델은 CLI 기본값.
- 설정 모델: `claudeCodeEnabled`→`aiEnabled`, `weeklyProvider`→`aiProvider`
  (`api`/`cli`/`codex`), `codexCliPath` 추가. SharedPreferences는 신규 키 우선 +
  레거시 키 fallback, sync JSON import도 레거시 키 수용.
- 설정 화면: Weekly/Monthly 패널을 AI 패널 하나로 통합 — AI 활성화 토글,
  연동 방식 3종 칩, 선택된 provider별 필드(API 키+모델 / claude 경로 / codex
  경로)와 Test 버튼, 위클리/먼슬리 지침 편집기.
- `document_screen._runSummary` 3-way dispatch (api / claude cli / codex cli).

## 검증

- `flutter analyze` clean, `flutter test` 359개 전부 통과.
- codex-cli 0.142.5 실제 호출로 invocation 플래그 검증 완료. 이 기기에서는
  codex refresh token이 만료되어 있어(`codex login` 재로그인 필요) 생성
  end-to-end는 로그인 후 앱의 Test 버튼과 Weekly 버튼으로 확인해야 한다.
- 참고: 작업 중 `/opt/homebrew/bin/codex` 심볼릭 링크가 깨져 있어
  `brew reinstall --cask codex`로 복구했다 (0.128.0 → 0.142.5).

## 메모

- codex는 claude의 `--disallowedTools` 같은 도구 단위 차단이 없어 read-only
  샌드박스 + 빈 임시 작업 디렉토리로 격리를 대신한다.
- `codex login status`는 캐시된 auth 파일만 보고 토큰 유효성은 검증하지 않아
  Test 버튼은 claude와 동일하게 바이너리 확인(`--version`)만 한다. 인증 오류는
  생성 시점에 codex의 자체 메시지로 표면화된다.
