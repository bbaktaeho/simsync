# SimSync 개선 및 기능 추가 설계

> 2026-03-11 | 상태: 확정

## 개요

4가지 영역의 개선/추가 작업을 다룬다.

| 구분 | 항목 | 우선순위 |
|------|------|---------|
| 개선 | 마크다운 프리뷰 (코드 하이라이팅, 헤더 간격) | 높음 |
| 개선 | 동기화 버그 (편집 중 노트 사라짐) | 높음 |
| 추가 | 노트 삭제 | 중간 |
| 추가 | 로컬 전용 노트 | 중간 |

iCloud/Google Cloud 스토리지는 후순위로 이 문서에서 다루지 않는다.

---

## 1. 마크다운 프리뷰 개선

### 코드 하이라이팅

- `flutter_highlight` 패키지를 `flutter_markdown`의 커스텀 code block builder로 연결
- 테마: GitHub Light / GitHub Dark (앱 테마 연동)
- 언어 감지: fence info string 있으면 해당 언어, 없으면 auto-detect
- inline code: 기존 스타일 유지 (JetBrains Mono, 배경색)
- code block: `HighlightView` 위젯으로 교체

### 헤더 간격

| 레벨 | top padding | bottom padding | 하단 divider |
|------|------------|---------------|-------------|
| H1 | 24px | 16px | 1px border |
| H2 | 24px | 16px | 1px border |
| H3 | 24px | 16px | 없음 |
| H4~H6 | 16px | 8px | 없음 |

변경 파일: `markdown_preview.dart` 1개

---

## 2. 동기화 버그 수정 (Dirty Flag 보호)

### 문제

편집 중 remote 변경이 감지되면 전체 노트를 remote에서 다시 가져와 로컬 미저장 변경이 덮어씌워진다. 노트 목록에서 노트가 일시적으로 사라지는 현상 발생.

### 해결: Dirty Flag

- Note 모델에 런타임 전용 `isDirty` 플래그 추가 (직렬화하지 않음)
- 사용자 입력 발생 → `isDirty = true`
- save 성공 → `isDirty = false`

### Remote 변경 수신 로직

```
onRemoteChanged() 호출 시:
  1. remote에서 노트 목록 fetch
  2. 각 노트에 대해:
     - isDirty == true → 로컬 상태 유지, remote 무시
     - isDirty == false → remote 데이터로 교체
  3. isDirty 노트의 save 완료 후 → 다음 sync 주기에서 remote에 push
```

### 경쟁 상태 방지

- save와 sync를 동시에 실행하지 않도록 Mutex 패턴 (단순 bool lock)
- save 진행 중이면 sync 대기, sync 진행 중이면 save는 큐에 적재

### 범위 밖

- 충돌 UI (MVP 범위 밖)
- 필드별 merge (전체 노트 단위 LWW 유지)

---

## 3. 노트 삭제

### UI

- 노트 목록 항목 우클릭 (데스크톱) → Context menu → "삭제"
- 노트 목록 항목 길게 누르기 (모바일) → Bottom sheet → "삭제"
- 에디터 헤더에는 추가하지 않음 (실수 방지)

### 삭제 플로우

1. 사용자가 삭제 선택
2. 확인 다이얼로그: "'{노트 제목}' 노트를 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다."
3. 확인 시:
   - 동기화 노트 → `GitHubNoteStorage.deleteNote()` (remote 파일 삭제)
   - 로컬 노트 → `LocalNoteStorage.deleteNote()` (로컬 파일 삭제)
4. 로컬 캐시 + 노트 목록에서 제거
5. 삭제된 노트가 현재 선택 노트면 → 같은 날짜의 다른 노트 선택, 없으면 에디터 빈 상태

### 삭제 실패 처리

- API 에러 (네트워크 등) → 스낵바 "삭제 실패" 알림, 노트 유지
- SHA mismatch (409) → 최신 SHA fetch 후 1회 재시도

---

## 4. 로컬 전용 노트

### 저장 구조

```
{사용자 선택 경로 또는 기본 경로}/
└── notes/
    └── {YYYY-MM}/
        └── {DD}/
            └── {title}.md
```

기본 경로:
- macOS: `~/Documents/SimSync/`
- Windows: `%USERPROFILE%\Documents\SimSync\`
- Linux: `~/Documents/SimSync/`

### LocalNoteStorage

기존 `NoteStorage` 인터페이스를 구현한다.

```dart
class LocalNoteStorage implements NoteStorage {
  final String basePath;
  // 파일 I/O로 CRUD
  // 마크다운 frontmatter(YAML)로 메타데이터 저장
  // 메모리 캐시 유지
}
```

### Note 모델 확장

```dart
enum StorageType { synced, local }

class Note {
  final StorageType storageType;  // 추가
  // 기존 필드 유지
}
```

### 레포 선택 화면 변경

```
RepoSelectionScreen 하단에 추가:
┌─────────────────────────────────────┐
│  로컬 노트 저장 경로                    │
│  ~/Documents/SimSync/    [변경]      │
└─────────────────────────────────────┘
```

- `file_picker` 패키지로 네이티브 디렉토리 피커 호출
- 선택한 경로는 `SharedPreferences`에 저장
- 선택하지 않으면 기본 경로 사용

### 노트 목록 통합 표시

- 같은 날짜의 노트를 하나의 리스트에 통합
- 동기화 노트: 기존 accent color
- 로컬 노트: 좌측 바 또는 dot을 amber/orange 계열로 표현

### 노트 생성 분기

기존 `+` 버튼 → 팝업 메뉴:
- "동기화 노트 생성" → `GitHubNoteStorage`에 저장
- "로컬 노트 생성" → `LocalNoteStorage`에 저장

### StorageBundle 확장

```dart
class StorageBundle {
  final NoteStorage remoteStorage;     // GitHub (기존)
  final NoteStorage? localStorage;     // Local (추가)
  final NoteService noteService;
  final SyncEngine? syncEngine;
}
```

`DocumentScreen`에서 두 storage의 노트를 합쳐서 `_allNotes`에 표시한다.

---

## 결정 사항 요약

| 항목 | 결정 |
|------|------|
| 마크다운 하이라이팅 | `flutter_highlight` + 커스텀 builder |
| 동기화 보호 | dirty flag + mutex lock |
| 삭제 범위 | remote + local 동시 삭제 |
| 로컬 노트 전환 | 불가 (생성 시 고정) |
| 로컬 경로 선택 | 레포 선택 화면 하단, 기본 ~/Documents/SimSync/ |
| 노트 구분 | 색상 인디케이터 (amber/orange for local) |
