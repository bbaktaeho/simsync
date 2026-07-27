# Note Format

## 경로 규칙

- 일일 노트: `notes/{YYYY-MM}/{DD}/{filename}.md` (DD는 2자리, 예: `notes/2026-07/27/회의록.md`)
- `filename`은 제목에서 `/ \ : * ? " < > |` 를 제거한 문자열. 제목이 비어 있으면 노트 `id`.
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

## 이미지

- 본문에서 `![...](assets/파일명)` 상대 경로로 참조한다.
- 실제 파일은 노트와 같은 날짜 디렉토리의 `assets/`에 있다.
