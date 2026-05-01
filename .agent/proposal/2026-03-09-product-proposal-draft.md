# SimSync Product Proposal Draft

> 상태: draft
>
> 기준일: 2026-03-09
>
> 문서 성격: 제품 아이디어와 방향을 정리한 제안서 초안

---

## 1. 제품 한 줄 정의

SimSync는 날짜 기반으로 문서를 기록하고, 여러 디바이스에서 자연스럽게 이어서 작업하며, 누적된 기록을 AI가 주간, 월간, 연간 단위로 정리해주는 개인용 markdown document app이다.

---

## 2. 왜 이 제품을 만들려는가

개인 기록 도구는 많지만, 실제 사용 흐름은 대체로 둘로 갈린다.

- 메모는 빠르지만 시간이 지나면 맥락이 약해진다.
- 문서 도구는 구조화에 강하지만, 일상적인 기록과 회고까지 이어지지 않는다.

SimSync가 노리는 지점은 그 중간이다.

- 하루 단위로 빠르게 기록할 수 있어야 한다.
- 문서 단위로 충분히 정리되고 다시 찾을 수 있어야 한다.
- 데스크탑과 모바일을 오갈 때 작업이 끊기지 않아야 한다.
- 쌓인 기록은 다시 읽는 데서 끝나지 않고, AI가 주기적으로 정리해줘야 한다.

즉, SimSync는 단순 메모 앱이 아니라 `기록 -> 축적 -> 동기화 -> 회고`까지 이어지는 개인 문서 workflow를 목표로 한다.

---

## 3. 제품 비전

### 핵심 비전
- 사용자는 날짜를 기준으로 생각하고 기록한다.
- 사용자는 문서를 기준으로 내용을 쌓고 다듬는다.
- 사용자는 디바이스를 옮겨도 같은 맥락을 이어간다.
- 사용자는 일정 기간이 지나면 AI 요약으로 자신의 기록을 빠르게 되돌아본다.

### 기대하는 사용자 경험
- 오늘 해야 할 기록을 바로 열 수 있다.
- 특정 날짜의 문서를 금방 찾을 수 있다.
- 작성 중인 문서를 다른 디바이스에서 이어서 볼 수 있다.
- 주간, 월간, 연간 단위로 "내가 무엇을 했는지" 한 번에 정리된다.

### 제품의 핵심 가치
- `date-oriented writing`
- `multi-device continuity`
- `AI-powered reflection`

---

## 4. 제품 포지셔닝

SimSync는 다음 성격을 동시에 가진 제품을 지향한다.

- 메모 앱보다 구조적이다.
- 전통적인 문서 앱보다 가볍고 빠르다.
- Obsidian류 툴보다 날짜 기반 진입이 강하다.
- Notion류 툴보다 개인 기록과 회고 흐름에 더 집중한다.

장기적으로는 개인 업무 로그, 일지, 회고, 경량 지식 관리의 중간 지점을 차지하는 제품이 될 수 있다.

---

## 5. 핵심 사용자

### Primary User
- 업무 기록을 남기고 싶은 개인 사용자
- 날짜를 기준으로 작업 내역을 관리하는 사용자
- markdown 기반 문서 작성이 익숙하거나 선호하는 사용자
- 여러 디바이스를 오가며 작업하는 사용자
- 일정 기간의 작업을 요약해 회고하고 싶은 사용자

### 대표 시나리오
1. 사용자는 데스크탑에서 오늘 날짜를 선택하고 작업 기록을 쓴다.
2. 이동 중 모바일에서 같은 계정으로 접속해 방금 작성하던 문서를 이어서 본다.
3. 며칠 뒤 특정 날짜의 기록을 다시 찾는다.
4. 주말이나 월말에 AI 요약으로 누적 기록을 빠르게 정리한다.

---

## 6. 제품 구조 초안

제품은 크게 3개의 축으로 구성된다.

### 1) Writing
- 날짜를 선택한다.
- 해당 날짜의 문서를 확인한다.
- 문서를 작성, 수정, 미리보기한다.

### 2) Sync
- 같은 계정으로 로그인한 여러 디바이스가 문서를 공유한다.
- 한 디바이스에서 수정한 문서가 다른 디바이스에 반영된다.
- 사용자는 "내 작업이 이어지고 있다"는 감각을 받아야 한다.

### 3) Summary
- 일정 기간의 문서를 수집한다.
- AI가 기간별 요약을 생성한다.
- 사용자는 요약과 원문을 오가며 회고한다.

---

## 7. 화면 초안

## 7.1 Login Screen

### 목표
앱 진입을 단순하게 만들고, 이후 동기화와 개인 데이터 분리를 위한 계정 기반 흐름의 출발점이 된다.

### 요구사항
- 중앙 정렬된 이메일 입력란
- 중앙 정렬된 비밀번호 입력란
- 주요 CTA인 `Sign in`
- 다크모드 기준의 심플하고 모던한 분위기
- 데스크탑 우선이되 모바일 safe area 대응 가능

### UX 메모
- 키보드만으로 입력과 제출이 가능해야 한다.
- 에러 메시지는 짧고 명확해야 한다.
- 시각적으로 과장된 브랜딩보다 안정감과 신뢰를 우선한다.

## 7.2 Document Workspace Screen

### 목표
캘린더 기반 탐색과 단일 문서 편집을 한 흐름 안에서 처리하는 메인 작업 화면이다.

### 기본 구조
- 좌측: 탐색
- 우측: 편집

### 좌측 영역
- 열고 닫을 수 있는 sidebar
- 상단에는 열고 닫을 수 있는 calendar
- 하단에는 선택 날짜 기준 document list

### 우측 영역
- `title`
- `tags`
- `updated_at`
- markdown editor
- markdown preview toggle

### 기대 동작
- 오늘 날짜는 별도 시각 상태를 가진다.
- 문서가 있는 날짜는 별도 표시가 된다.
- 날짜를 클릭하면 해당 날짜 문서 목록이 바뀐다.
- 문서를 선택하면 우측 편집 영역이 바뀐다.
- 문서가 10개 이상이면 pagination이 필요하다.
- 태그는 문서 목록 우측에 보이고, 많을 경우 `+N`으로 요약한다.

### 레이아웃 방향
- 데스크탑: 2-pane 기본
- 모바일: same IA, different layout

---

## 8. 핵심 기능 제안

## 8.1 Date-Oriented Document Writing
- 날짜 선택 기반 진입
- 날짜별 다중 문서 관리
- markdown 작성
- preview 전환
- title/tag/metadata 분리

## 8.2 Multi-Device Sync
- 계정 기반 문서 동기화
- 여러 디바이스에서 동일 문서 이어쓰기
- near-real-time sync 지향
- 최소한의 conflict handling 필요

## 8.3 AI Periodic Summary
- `weekly` summary
- `monthly` summary
- `yearly` summary
- summary와 source document 연결
- 사용자의 회고와 정리 workflow를 돕는 보조 계층

## 8.4 Retrieval and Recall
- 날짜 기준 재탐색
- 태그 기반 재탐색
- 최근 수정 문서 접근
- 장기적으로는 기간 기반 검색 확장 가능

---

## 9. 요구사항 초안

## 9.1 Functional Requirements

### Document
- 문서는 기본 콘텐츠 단위다.
- 문서는 `title`, `content`, `tags`, `created_at`, `updated_at`를 가진다.
- 문서는 하나의 `document_date`에 속한다.
- 한 날짜에는 여러 문서가 존재할 수 있다.

### Calendar
- 월 단위 탐색을 지원해야 한다.
- 오늘 날짜는 구분되어야 한다.
- 문서가 있는 날짜는 구분되어야 한다.
- 선택 날짜 state가 분명해야 한다.

### Document List
- 선택 날짜 기준으로 문서 목록을 표시해야 한다.
- 작성일 또는 수정일 기준 정렬 정책이 필요하다.
- 10개 이상일 때 pagination을 지원해야 한다.
- 태그 요약 표현을 지원해야 한다.

### Editor
- markdown plain text 작성이 가능해야 한다.
- preview 전환이 가능해야 한다.
- 저장 상태와 마지막 수정 시각이 사용자에게 전달되어야 한다.

### Authentication
- 이메일/비밀번호 로그인 흐름이 필요하다.
- 개인 데이터 분리를 위한 계정 단위 접근 제어가 필요하다.

### Sync
- 같은 계정의 여러 디바이스 간 데이터 동기화가 필요하다.
- 문서 metadata와 본문이 함께 동기화되어야 한다.
- 디바이스 전환 시 사용자가 끊김을 적게 느껴야 한다.

### AI Summary
- 주간, 월간, 연간 단위 요약이 가능해야 한다.
- 요약은 원본 문서와 분리 저장되어야 한다.
- 요약은 원본 문서와 다시 연결될 수 있어야 한다.
- AI 호출에는 사용자 동의가 필요하다.

## 9.2 Non-Functional Requirements

### UX
- 심플하고 모던해야 한다.
- 다크모드는 필수다.
- 데스크탑 우선 UX가 안정적이어야 한다.
- 모바일에서도 정보 구조가 무너지지 않아야 한다.

### Performance
- 날짜 전환이 즉각적으로 느껴져야 한다.
- 문서 로딩이 빠르게 느껴져야 한다.
- sync는 장기적으로 near-real-time 수준을 목표로 한다.

### Reliability
- 저장 실패와 로딩 실패를 명확히 알려야 한다.
- sync 상태 혼란을 줄여야 한다.
- 문서와 요약 데이터의 연결 정합성이 유지되어야 한다.

### Security
- 사용자 데이터는 계정 단위로 격리되어야 한다.
- 인증 정보는 안전하게 저장되어야 한다.
- AI 전송 범위와 동의가 명확해야 한다.

---

## 10. MVP와 장기 방향

### MVP 1단계
- 로그인
- 날짜 기반 문서 탐색
- 문서 작성/수정
- markdown preview
- 태그 표시
- 다크모드
- 데스크탑 중심 안정적인 workspace

### 다음 단계
- multi-device sync
- sync status
- 모바일 연속성 강화

### 장기 단계
- `weekly`, `monthly`, `yearly` AI summary
- summary archive
- source document traceability

이 문서의 목적은 장기 방향까지 함께 잡는 것이므로, 실제 구현 순서는 이 구조를 그대로 따르지 않아도 된다.

---

## 11. 기능 후보 백로그

### Writing
- auto save
- draft recovery
- pinned document
- template document
- focus mode

### Navigation
- tag filter
- recent documents
- activity heatmap
- date range search

### Sync
- manual refresh
- device status
- offline re-sync
- conflict history

### AI
- tag-based summary
- project-based summary
- action item extraction
- summary as markdown document

### Knowledge
- revision history
- document link
- backlink
- archive
- export/import

---

## 12. 기술 요구사항 방향

이 문서는 기술 설계를 확정하는 문서는 아니지만, 제품 방향상 다음 정도의 구조는 예상할 수 있다.

### Client
- desktop와 mobile을 함께 고려할 수 있는 client 구조
- calendar, list, editor, preview, auth, sync status를 다룰 수 있는 상태 관리

### Backend
- 인증 처리
- document CRUD
- date 기반 조회
- tag 및 metadata 처리
- multi-device sync를 위한 변경 추적
- AI summary 생성과 저장

### Data
- `User`
- `Device`
- `Document`
- `Tag`
- `DocumentTag`
- `Summary`
- `SummarySource`

---

## 13. 아직 열어둘 결정

- 날짜별 기본 문서 1개를 강제할지
- 목록 정렬 기준을 `created_at`으로 볼지 `updated_at`으로 볼지
- preview를 full toggle로 갈지 split view까지 허용할지
- sync 초기 목표를 near-real-time으로 둘지 단계적으로 갈지
- AI summary를 수동 생성부터 시작할지 자동 생성까지 볼지

---

## 14. 정리

SimSync의 핵심은 예쁜 markdown 에디터 자체가 아니다.

- 날짜를 중심으로 기록할 수 있어야 한다.
- 문서를 중심으로 내용을 쌓을 수 있어야 한다.
- 디바이스를 바꿔도 작업이 이어져야 한다.
- 시간이 지나면 AI가 기록을 다시 읽기 쉬운 형태로 정리해줘야 한다.

즉, SimSync는 `personal document app`이면서 동시에 `cross-device work log`이고, 장기적으로는 `AI-assisted reflection tool`이 되는 방향을 제안한다.
