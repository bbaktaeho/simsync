import '../storage/github/github_api_client.dart';

/// 노트 스토어 repo에 심는 AI agent 지침 하네스.
///
/// 라우팅 체인: `CLAUDE.md`/`GEMINI.md`(symlink) → `AGENTS.md`(실체) →
/// `.agents/README.md`(개요 + 라우팅) → `.agents/*` 상세 지침.
/// 어떤 AI 도구가 repo를 열어도 같은 지침 하나로 수렴한다.
///
/// [ensureAgentHarness]는 앱 시작(스토리지 번들 생성)마다 호출해도 되는
/// 비용이다: AGENTS.md GET 1회로 존재를 확인하고, 없을 때만 전체를 단일
/// 커밋으로 만든다. 신규 repo도 생성 직후 같은 경로를 지나므로 무조건 심긴다.

const String _agentsMd = '''# SimSync Note Store

이 저장소는 [SimSync](https://github.com/bbaktaeho/simsync) 앱이 동기화 저장소로 사용하는 개인 노트 스토어다.
파일 경로와 형식의 규칙은 앱이 소유한다 — 어기면 앱에서 노트가 사라져 보이거나 중복된다.

AI agent 상세 지침: [.agents/README.md](.agents/README.md)

## 핵심 규칙

- 노트 파일의 YAML frontmatter 구조를 유지하고, `id` 필드는 절대 수정하지 마라.
- 노트 파일을 임의로 이동하거나 이름을 바꾸지 마라. 경로는 앱이 제목과 날짜로부터 유도한다.
- 이 저장소의 내용은 개인 기록이다. 요청 없이 수정하지 말고, 외부로 복사하지 마라.
''';

const String _agentsReadme = '''# SimSync Note Store - Agent Guide

SimSync(마크다운 기반 개인 노트 앱)가 이 repo를 동기화 저장소로 사용한다.
노트의 생성/수정/삭제는 대부분 앱이 수행한다. agent가 파일을 직접 다룰 때는
아래 문서의 규칙을 먼저 확인한다.

## Routing

| 문서 | 읽어야 할 때 |
|------|--------------|
| [guidelines.md](guidelines.md) | 어떤 작업이든 시작하기 전 - 허용/금지, 동시성, 개인정보 |
| [note-format.md](note-format.md) | 노트 파일을 읽거나 쓸 때 - 경로 규칙, frontmatter 스키마 |

## Repository Layout

```
notes/
└── YYYY-MM/
    ├── DD/                    # 일일 노트 디렉토리 (DD는 2자리)
    │   ├── {title|id}.md      # 노트 파일 (YAML frontmatter + 마크다운 본문)
    │   └── assets/            # 노트 본문이 참조하는 첨부 이미지
    ├── N주차/                 # 주간 AI 리뷰 (weekly-outline.md / weekly-review.md)
    ├── monthly-outline.md     # 월간 AI 리뷰 1단계
    └── monthly-review.md      # 월간 AI 리뷰 2단계
```

숫자가 아닌 폴더(`N주차` 등)와 월 폴더 바로 아래의 .md는 노트가 아니라 리뷰 파일이다 —
앱의 노트 목록에는 `notes/YYYY-MM/DD/*.md`만 잡힌다.
''';

const String _noteFormatMd = '''# Note Format

## 경로 규칙

- 일일 노트: `notes/{YYYY-MM}/{DD}/{filename}.md` (DD는 2자리, 예: `notes/2026-07/27/회의록.md`)
- `filename`은 제목에서 `/ \\ : * ? " < > |` 를 제거한 문자열. 제목이 비어 있으면 노트 `id`.
- 제목이 바뀌면 앱이 파일을 새 경로로 옮긴다 — agent가 파일명을 직접 바꾸면 앱과 어긋난다.

## Frontmatter 스키마

```yaml
---
id: "1753500000000"
title: "노트 제목"
note_date: 2026-07-27
is_default: false
is_memo: false
tags: ["work", "idea"]
created_at: 2026-07-27T09:00:00+0900
updated_at: 2026-07-27T09:30:00+0900
---
본문 마크다운...
```

## 필드 규칙

- `id`: 필수, 불변, 저장소 전체에서 유일. 새 노트는 생성 시각 밀리초 타임스탬프 문자열을 쓴다.
- `note_date`: 파일이 위치한 `YYYY-MM/DD` 디렉토리와 일치해야 한다.
- `is_default`: 해당 날짜의 기본 노트 여부. 같은 날짜에 true는 1개만.
- `is_memo`: true면 날짜와 무관한 메모로 취급되어 앱의 메모 탭에 표시된다.
- `updated_at`: 본문을 수정하면 함께 갱신한다.
- frontmatter 파싱에 실패한 파일은 앱이 무시한다 — 노트가 사라진 것처럼 보인다.

## 본문 작성 규칙

- 본문은 `##` 헤더로 시작하고, 주제가 바뀌면 헤더로 섹션을 나눈다.
- 나열은 `- ` 리스트로 쓴다.
- 키워드나 핵심 값은 `백틱`으로 강조한다.
- 명령어, 코드, 로그는 코드블록(```)에 넣는다.
- 같은 꼴의 항목이 반복되는 정돈된 내용은 표로 정리한다.

템플릿 예시 (본문 골격):

    ## 주제

    - 핵심을 `- ` 리스트로 나열하고, 중요한 값은 `백틱`으로 강조
    - 하위 항목은 두 칸 들여쓴 `- ` 리스트

    ## 상세

    | 항목 | 값 |
    |------|-----|
    | 상태 | `확정` |

    ```bash
    echo "명령어와 코드는 코드블록에"
    ```

## 이미지

- 본문에서 `![...](assets/파일명)` 상대 경로로 참조한다.
- 실제 파일은 노트와 같은 날짜 디렉토리의 `assets/`에 있다.
''';

const String _guidelinesMd = '''# Agent Guidelines

## 해도 되는 것

- 노트 읽기, 검색, 분석, 요약, 회고 작성 보조
- 요청받은 노트의 본문(content) 수정 — frontmatter 구조는 유지
- note-format.md 스키마를 지킨 새 노트 생성
- `notes/{YYYY-MM}/{N}주차/weekly-*.md`, `notes/{YYYY-MM}/monthly-*.md` 위치의 리뷰 파일 작성

## 하면 안 되는 것

- `id` 수정, frontmatter 필드 삭제, 노트 파일 이동/이름 변경
- 요청 없이 노트 내용을 수정하거나 삭제
- 노트 내용(개인 기록)을 다른 저장소, 이슈, 외부 서비스로 복사
- `notes/` 밖에 임의 파일 생성 (이 하네스 파일들은 예외)

## 동시성

- 앱이 이 repo에 수시로 커밋한다 (Last-Write-Wins).
- 커밋 전 최신 상태를 받아오고, 충돌하면 최신 원격 내용을 기준으로 다시 작업한다.

## 요약 / AI 결과물

- 요약과 리뷰는 원본 노트와 별도 파일로 저장한다. 원본을 요약으로 덮어쓰지 않는다.
''';

/// symlink 대상 — 실체 파일.
const String _entryPoint = 'AGENTS.md';

/// 하네스가 만드는 파일 전체. 시작점 파일(CLAUDE.md 등)은 AGENTS.md를 가리키는
/// symlink(mode 120000)다.
const List<CommitFileEntry> agentHarnessFiles = [
  (path: 'AGENTS.md', content: _agentsMd, mode: '100644'),
  (path: 'CLAUDE.md', content: _entryPoint, mode: '120000'),
  (path: 'GEMINI.md', content: _entryPoint, mode: '120000'),
  (path: '.agents/README.md', content: _agentsReadme, mode: '100644'),
  (path: '.agents/note-format.md', content: _noteFormatMd, mode: '100644'),
  (path: '.agents/guidelines.md', content: _guidelinesMd, mode: '100644'),
];

/// AGENTS.md가 없으면 하네스 전체를 단일 커밋으로 생성한다. 생성했으면 true.
///
/// 실패(오프라인, 권한 부족, ref 경합, 빈 repo)는 조용히 넘긴다 — 아무것도
/// 만들어지지 않았으므로 다음 앱 시작에서 자연히 재시도된다.
Future<bool> ensureAgentHarness({
  required GitHubApiClient client,
  required String branch,
}) async {
  try {
    await client.getFile('AGENTS.md');
    return false; // 이미 있음 — 손대지 않는다.
  } on GitHubNotFoundException {
    // 없음 — 아래에서 생성.
  } catch (_) {
    return false;
  }
  try {
    await client.commitFiles(
      branch: branch,
      message: 'chore: add AI agent instruction harness',
      files: agentHarnessFiles,
    );
    return true;
  } catch (_) {
    return false;
  }
}
