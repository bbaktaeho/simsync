# 저장소 선택 화면 + Repo 관리 설계

> 작성일: 2026-03-10
> 상태: confirmed
> 브랜치: feat/github-sync

## 개요

로그인 후 노트 에디터 진입 전에 GitHub 저장소를 선택/생성하는 화면을 추가한다.
연동 이력을 로컬에 캐시하여 재방문 시 빠르게 선택할 수 있도록 한다.

## 앱 흐름

```
로그인 → 저장소 선택 → 노트 에디터
```

## 저장소 선택 화면

### 첫 사용 시
- "새 저장소 만들기" — repo 이름 입력, private으로 자동 생성
- "기존 저장소 연결" — `owner/repo` 직접 입력

### 재방문 시 (캐시된 연동 이력 있음)
- 이전에 연동했던 repo 리스트 표시 → 탭해서 바로 연결
- "새 저장소 만들기" / "기존 저장소 연결" 옵션도 여전히 표시
- 연동 해제 (캐시에서 제거, GitHub repo는 유지)

## Repo 관리 (GitHub API)

- **Create**: `POST /user/repos` — private repo 생성
- **Read**: 연동 이력은 로컬 캐시 (`~/.simsync/repos.json`)
- **Delete**: 캐시에서만 제거 (GitHub repo 삭제 안 함)

## OAuth scope 변경

`read:user user:email` → `read:user user:email repo`

기존 세션은 재로그인 필요.

## 프로필 이미지

노트 에디터 우측 최상단에 GitHub 프로필 이미지(아바타) 표시.
`AuthSession.user.avatarUrl` 활용.

## 캐시 구조 (`~/.simsync/repos.json`)

```json
[
  {
    "owner": "bbaktaeho",
    "repo": "simsync-notes",
    "branch": "main",
    "connectedAt": "2026-03-10T15:00:00Z"
  }
]
```
