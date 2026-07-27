# SimSync Note Store - Agent Guide

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
