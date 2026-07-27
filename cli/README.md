# SimSync CLI

SimSync 노트 스토어를 터미널에서 다루는 CLI. 1차 사용자는 AI agent다.
데스크톱 앱과 세션·스토어를 파일로 공유하므로 로그인은 한 번, 스토어는 앱과 항상 같다.

```
simsync auth login|logout|status     GitHub Device Flow 로그인 / 세션·만료 확인 (exit 0/1)
simsync store clone|status|sync      앱과 같은 스토어 클론 / 상태 / pull·push
simsync note new                     규칙대로 노트 스캐폴드 (frontmatter 자동)
simsync guide [note-format|guidelines]  노트 작성/작업 규칙 출력
simsync open                         데스크톱 앱 실행
simsync help                         전체 도움말 (명령별 용도·exit code 계약)
```

## 설치 — 어느 경로에서든 `simsync`로 실행되게 하기

핵심은 **바이너리를 PATH에 있는 디렉토리에 두는 것**이다. 셸은 명령어를 칠 때
PATH에 나열된 디렉토리만 순서대로 뒤진다 (`echo $PATH`로 확인).

### 방법 1: `/usr/local/bin` (권장, sudo 필요)

macOS 기본 PATH(`/etc/paths`)에 이미 들어 있어 추가 설정이 필요 없다. 셸 종류
(zsh/bash/fish)와도 무관하다.

```bash
# 릴리즈에서 받은 파일 압축 해제 (Apple Silicon은 arm64, Intel은 amd64)
tar xzf simsync-cli-<버전>-darwin-arm64.tar.gz

# Gatekeeper 격리 속성 제거 (서명되지 않은 바이너리)
xattr -d com.apple.quarantine simsync 2>/dev/null

chmod +x simsync
sudo mv simsync /usr/local/bin/simsync
```

### 방법 2: `~/.local/bin` (sudo 없이)

PATH에 없을 수 있으므로 셸 설정에 한 줄 추가한다.

```bash
mkdir -p ~/.local/bin
xattr -d com.apple.quarantine simsync 2>/dev/null
chmod +x simsync
mv simsync ~/.local/bin/

# zsh(macOS 기본)면 ~/.zshrc, bash면 ~/.bash_profile
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### 방법 3: 소스 빌드 (Go 1.26+)

```bash
git clone https://github.com/bbaktaeho/simsync.git
cd simsync/cli
go build -o simsync . && sudo mv simsync /usr/local/bin/

# 또는 go install — GOBIN(기본 ~/go/bin)에 설치되므로 PATH에 있어야 한다
go install .
echo 'export PATH="$HOME/go/bin:$PATH"' >> ~/.zshrc   # 필요 시
```

### 확인

```bash
which simsync      # 설치 경로가 나와야 한다
simsync version
cd /tmp && simsync help   # 다른 디렉토리에서도 동작하는지
```

`command not found`가 나면 바이너리가 PATH 밖에 있다는 뜻이다. `echo $PATH`로
나열된 디렉토리를 확인하고 그중 한 곳으로 옮긴다.

> **PATH에 설치했다면** `store clone`이 credential helper를 `simsync`라는
> 이름으로 등록하므로, 이후 바이너리를 PATH 안에서 옮기거나 새 버전으로
> 바꿔도 그대로 동작한다.
>
> **PATH 밖에서 직접 실행했다면** 절대 경로가 기록되므로, 바이너리를 옮긴 뒤
> `simsync store clone`을 한 번 다시 실행한다 (재클론 없이 설정만 갱신된다).

### 클론의 git 인증 격리

`store clone`은 클론의 **local** 설정에 credential helper 목록을 리셋(빈 값)한
뒤 SimSync helper를 등록한다. macOS의 Xcode git은 시스템 설정에
`credential.helper = osxkeychain`을 박아두는데, git은 system → global → local
순으로 helper를 시도하므로 리셋이 없으면 keychain이 먼저 답해 **SimSync 세션이
아닌 다른 신원으로 인증된다**. 리셋은 이 클론에만 적용되므로 다른 저장소에는
영향이 없다.

확인:

```bash
cd <클론 경로>
printf 'protocol=https\nhost=github.com\n\n' | GIT_TRACE=1 git credential fill
# → run_command: 'simsync auth git-credential get'
# → username=x-access-token
```

## 시작하기

```bash
simsync auth status     # 앱에 로그인돼 있으면 그대로 유효 (exit 0)
simsync store clone     # 인자 없이 = 앱에 연결된 스토어를 클론
simsync guide note-format
simsync note new --title "회의록"     # 마지막 줄이 생성된 파일 경로
# 본문 작성 후 클론에서 git add/commit
simsync store sync
```

## 공유 파일

| 상태 | 경로 | 비고 |
|------|------|------|
| 세션 | `~/Library/Application Support/com.simsync.simsync/auth/session.json` | 데스크톱 앱과 동일 파일 (0600) |
| 스토어 | `~/.simsync/repos.json` | 앱과 동일 파일, 첫 엔트리가 활성 스토어 |
| 클론 위치 | `~/.simsync/cli/config.json` | CLI 전용 |

앱이 실행 중일 때 CLI가 세션/스토어를 바꾸면 앱은 다음 시작에 반영한다.

## 개발

```bash
cd cli
go test ./...     # 테스트
go vet ./...      # 정적 분석
gofmt -l .        # 포맷 확인 (출력 없어야 함)
```
