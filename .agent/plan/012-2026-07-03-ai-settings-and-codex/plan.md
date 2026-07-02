---
title: AI 설정 통합 + Codex CLI 지원
description: 위클리/먼슬리 리뷰 생성에 Codex CLI를 추가하고, 설정의 Weekly/Monthly 카테고리를 AI 카테고리 하나로 통합
type: plan
created: 2026-07-03
status: active
---

# AI 설정 통합 + Codex CLI 지원

## 확정 요구사항 (소유자 요청)

1. 위클리/먼슬리 리뷰 생성 시 Codex CLI도 사용할 수 있어야 한다.
2. 설정에서 Weekly/Monthly 두 카테고리로 나누지 말고 AI 카테고리 하나 안에서
   위클리/먼슬리 지침을 작성할 수 있어야 한다.
3. AI 카테고리에 AI 활성화 토글과 사용할 CLI 선택 + CLI 테스트를 함께 둔다.

## 현재 구조 (조사 결과)

- 생성 경로는 `document_screen.dart`의 `_runSummary` 하나로 모인다.
  provider가 `cli`면 `ClaudeCodeService.summarizeWeek`(claude --print, 노트는 stdin),
  아니면 `AnthropicApiService.summarizeWeek`(Messages API).
- 설정 필드: `claudeCodeEnabled`(활성화), `weeklyProvider`(`api`/`cli`),
  `claudeCliPath`, `anthropicApiKey/Model`, `weeklyInstruction`, `monthlyInstruction`.
- 설정 화면: `_SettingsPane.weekly`(지침 + AI 요약 연동 카드 + Test 버튼),
  `_SettingsPane.monthly`(지침만). Monthly는 "연동 방식은 Weekly 설정을 공유"라고 안내.

## 제안 결정

| 항목 | 결정 | 근거 |
|------|------|------|
| provider 값 | `api` / `cli`(Claude Code) / `codex` 3종 | 기존 값 유지로 마이그레이션 최소화 |
| 필드 이름 | `claudeCodeEnabled`→`aiEnabled`, `weeklyProvider`→`aiProvider` | AI 카테고리 통합과 도메인 일치. 저장 키는 신규 키 우선 + 레거시 키 fallback으로 호환 유지 |
| codex 호출 | `codex exec --sandbox read-only --skip-git-repo-check --ephemeral --color never -o <tmp> <instruction>` + 노트 stdin | codex-cli 0.142.5 `exec --help` 확인: instruction 인자 + stdin이 `<stdin>` 블록으로 결합. 최종 응답은 `-o` 파일로 수신 (stdout은 진행 로그) |
| codex 모델 | CLI 기본 모델 사용 (`--model` 미전달) | stage 2의 `cliUseDefaultModel` 동작과 동일. Anthropic 모델 id는 codex에 무의미 |
| codex 격리 | read-only 샌드박스 + 빈 임시 작업 디렉토리 | claude의 tool-deny와 달리 codex는 도구 단위 차단이 없어 샌드박스 정책으로 대체 |
| 프로세스 실행 공통화 | `services/cli_process.dart` 추출, claude/codex 서비스가 공유 | 중복 방지. 기존 `ClaudeProcessResult`/`ClaudeProcessRunner`는 typedef alias로 유지해 테스트 호환 |
| CLI 테스트 | 선택된 연동의 가용성 확인: api→`validateKey`, cli→`claude --version`, codex→`codex --version` | 기존 probe 패턴 재사용 |
| 타임아웃 | codex 요약 300s (claude 180s 유지) | reasoning 모델 특성상 여유 확보 |

## 가정

- 모바일에는 AI 연동이 없으므로 이 작업은 desktop 한정이다.
- `settings/settings.json` 동기화 JSON은 신규 키(`aiEnabled`/`aiProvider`)로 내보내되,
  import는 레거시 키(`claudeCodeEnabled`/`weeklyProvider`)도 받아들인다.

## 변경 파일

- 신규: `desktop/lib/services/cli_process.dart`, `desktop/lib/services/codex_cli_service.dart`,
  `desktop/test/services/codex_cli_service_test.dart`
- 수정: `app_settings.dart`, `app_settings_controller.dart`, `claude_code_service.dart`(공통 러너 사용 + 문구),
  `document_screen.dart`(3-way dispatch + prop), `weekly_view_panel.dart`(prop/안내 문구),
  `settings_screen.dart`(weekly/monthly pane → ai pane), 설정 관련 테스트 3종

## 검증

- `flutter analyze` clean, `flutter test` 전체 통과
- codex 실제 호출 1회로 invocation 플래그 검증 (최소 프롬프트)
