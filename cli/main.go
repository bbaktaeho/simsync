package main

import (
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"time"
)

const version = "0.3.2"

// AI agent가 1차 사용자다: 각 명령은 "무엇을 하는지"와 "언제 쓰는지(용도)"를
// 함께 설명하고, exit code 계약을 명시한다. 인수 없이 실행하면 이 도움말이
// 나온다 (agent가 탐색 중 GUI 앱을 실수로 띄우지 않도록 — 앱 실행은 open).
const usage = `simsync - SimSync 노트 스토어 CLI (AI agent용)

SimSync 데스크톱 앱과 같은 GitHub 노트 스토어를 터미널에서 다룬다.
세션과 스토어 선택을 앱과 "공유"한다: 앱에 로그인돼 있으면 CLI 로그인이
필요 없고, 앱에 연결된 저장소가 곧 CLI의 스토어다 (반대 방향도 같음 —
CLI에서 로그인/스토어 연결하면 앱이 다음 시작에 그대로 사용한다).

AI agent 권장 워크플로:
  1. simsync auth status            세션 확인 (없거나 만료면 auth login — 사람 승인 필요)
  2. simsync store clone            앱에 연결된 스토어를 클론 (최초 1회)
  3. simsync guide note-format      노트 작성 규칙 확인
  4. simsync note new --title "…"   규칙대로 스캐폴드 생성 (마지막 줄이 파일 경로)
  5. (본문 작성 후 클론에서 git add/commit)
  6. simsync store sync             pull --rebase + push

명령:
  open           SimSync 데스크톱 앱을 실행한다 (macOS).
                 용도: 사람이 GUI로 노트를 보거나 편집하려 할 때만. agent 작업에는 불필요.

  auth login     GitHub Device Flow로 로그인해 세션을 만든다. 터미널에 일회용
                 코드와 URL이 표시되며, 사람이 브라우저에서 승인해야 완료된다.
                 세션은 앱과 공유된다 — 앱에 이미 로그인돼 있으면 필요 없다
                 (auth status로 먼저 확인). 실행하면 새 세션으로 교체된다.
                 용도: 앱/CLI 모두 세션이 없거나 만료됐을 때. AI agent는 코드를
                 사용자에게 전달하고 승인을 기다린다.

  auth status    세션 상태를 출력한다: 계정, scope, 발급/만료 시각(남은 시간),
                 GitHub API 라이브 토큰 검증.
                 exit 0 = 세션 유효, exit 1 = 미로그인/만료/무효 토큰.
                 용도: 어떤 작업이든 시작하기 전 첫 명령. exit code로 분기한다.

  auth logout    공유 세션 파일을 삭제한다 — 앱도 다음 시작에 로그아웃된다.
                 용도: 토큰 폐기, 계정 전환 전.

  store clone [owner/repo] [dir]
                 노트 스토어를 클론한다. 인자가 없으면 앱에 연결된 스토어를
                 쓴다 (권장). 앱에 스토어가 없으면 owner/repo 지정으로 클론하며
                 앱에도 같은 스토어가 연결된다. 앱 스토어와 다른 repo 지정은
                 거부된다 — 스토어는 앱과 CLI가 항상 같아야 한다.
                 인증은 클론의 credential helper(simsync auth git-credential)로
                 연결되어, 클론 안의 맨 git pull/push도 공유 세션으로 동작한다.
                 기본 위치: ~/.simsync/store/<owner>/<repo>
                 용도: 최초 1회. 클론을 열면 AGENTS.md/.agents/ 지침이 함께 온다.

  store status   스토어 상태를 출력한다: 앱과 공유되는 활성 스토어, 클론
                 경로/존재, 앱-클론 불일치 경고.
                 용도: 작업 환경 확인. auth status 다음으로 실행하면 좋다.

  store sync     클론을 원격과 정합시킨다 (pull --rebase 후 push).
                 커밋되지 않은 변경이 있으면 실패한다 — 먼저 커밋하라는 뜻.
                 용도: 노트 커밋 후 마무리로 항상 실행. 앱은 폴링으로 곧 반영한다.

  note new [--date YYYY-MM-DD] [--title 제목] [--memo] [--tags a,b]
                 클론 안에 노트 파일을 규칙대로 스캐폴드한다 (경로·frontmatter 자동).
                 본문 작성 규칙 요약을 함께 출력한다. stdout 마지막 줄이 생성된
                 파일의 절대 경로다.
                 용도: 노트 생성의 시작점. frontmatter는 손대지 말고 본문만
                 작성하며, 출력된 본문 작성 규칙을 따른다.

  guide [overview|note-format|guidelines]
                 노트 작성/작업 규칙을 출력한다. 클론의 .agents/가 있으면 그쪽을,
                 없으면 CLI 내장본을 보여준다 (출처는 stderr에 표시).
                 용도: note new 전에 note-format, 작업 전에 guidelines를 읽는다.

  version        CLI 버전을 출력한다.
  help           이 도움말을 출력한다.

환경변수:
  SIMSYNC_GITHUB_CLIENT_ID   포크에서 자체 OAuth App client_id 오버라이드

공유 파일 (데스크톱 앱과 같은 파일):
  세션    ~/Library/Application Support/com.simsync.simsync/auth/session.json
  스토어  ~/.simsync/repos.json (첫 엔트리가 활성 스토어)
CLI 전용: ~/.simsync/cli/config.json (클론 위치)

앱이 "실행 중"일 때 CLI가 세션/스토어를 바꾸면 앱은 다음 시작에 반영한다.
세션 만료 정책은 앱과 동일한 30일. 앱이 세션 복원에 성공할 때마다 만료가
now+30일로 연장된다(sliding window). open/store/note 명령은 실행 시 세션
만료를 자동 점검해 stderr로 경고한다 (만료됐거나 2시간 미만 남았을 때).`

const authUsage = `사용법: simsync auth <login|logout|status>

  login    GitHub Device Flow 로그인 (브라우저 승인 필요, 앱과 세션 공유)
  logout   공유 세션 삭제 (앱도 다음 시작에 로그아웃)
  status   세션/만료/토큰 상태 확인 (유효하면 exit 0, 아니면 exit 1)`

// cmdLaunch는 데스크톱 앱을 연다. macOS의 LaunchServices(open -a)를 쓰므로
// 설치 위치와 무관하게 동작한다.
func cmdLaunch() error {
	if runtime.GOOS != "darwin" {
		return fmt.Errorf("현재 macOS만 지원합니다 (%s)", runtime.GOOS)
	}
	out, err := exec.Command("open", "-a", "simsync").CombinedOutput()
	if err != nil {
		detail := strings.TrimSpace(string(out))
		if detail == "" {
			detail = err.Error()
		}
		return fmt.Errorf("SimSync 앱을 실행하지 못했습니다: %s", detail)
	}
	fmt.Println("SimSync 앱을 실행했습니다.")
	return nil
}

// cmdStatus는 세션 상세를 출력한다. 미로그인/만료/무효 토큰이면 exit 1 —
// `simsync auth status || simsync auth login` 같은 스크립트 연동을 위해서다.
func cmdStatus() error {
	s, err := loadSession()
	if err != nil {
		return err
	}
	if s == nil {
		fmt.Println("로그인되어 있지 않습니다. 'simsync auth login'으로 로그인하세요.")
		os.Exit(1)
	}

	now := time.Now()
	state := validateToken(s.AccessToken)

	fmt.Printf("계정:      %s (%s)\n", s.User.Login, s.Provider)
	fmt.Printf("scope:     %s\n", s.Scope)

	switch state {
	case tokenValid:
		fmt.Println("토큰 검증: 유효 (GitHub API)")
	case tokenInvalid:
		fmt.Println("토큰 검증: 무효 — GitHub에서 취소되었습니다. 다시 로그인하세요.")
	case tokenUnknown:
		fmt.Println("토큰 검증: 확인 불가 (네트워크/GitHub 오류)")
	}

	fmt.Printf("발급:      %s\n", formatTime(s.IssuedAt))
	if s.expired(now) {
		fmt.Printf("만료:      %s (%s 지남)\n",
			formatTime(s.ExpiresAt), formatDuration(now.Sub(s.ExpiresAt)))
		fmt.Println("\n세션이 만료되었습니다. 'simsync auth login'으로 다시 로그인하세요.")
		os.Exit(1)
	}
	fmt.Printf("만료:      %s (%s 남음)\n",
		formatTime(s.ExpiresAt), formatDuration(s.ExpiresAt.Sub(now)))
	if state == tokenInvalid {
		os.Exit(1)
	}
	return nil
}

func runAuth(args []string) error {
	sub := ""
	if len(args) > 0 {
		sub = args[0]
	}
	switch sub {
	case "login":
		return cmdLogin()
	case "logout":
		return cmdLogout()
	case "status":
		return cmdStatus()
	case "git-credential":
		// 내부용: store clone이 등록하는 git credential helper.
		return cmdGitCredential(args[1:])
	default:
		fmt.Fprintln(os.Stderr, authUsage)
		os.Exit(2)
		return nil
	}
}

func runStore(args []string) error {
	sub := ""
	if len(args) > 0 {
		sub = args[0]
	}
	switch sub {
	case "clone":
		return cmdStoreClone(args[1:])
	case "sync":
		return cmdStoreSync()
	case "status":
		return cmdStoreStatus()
	default:
		fmt.Fprintln(os.Stderr, "사용법: simsync store <clone|status|sync>")
		os.Exit(2)
		return nil
	}
}

func main() {
	cmd := ""
	if len(os.Args) > 1 {
		cmd = os.Args[1]
	}

	var err error
	switch cmd {
	case "", "help", "--help", "-h":
		fmt.Println(usage)
	case "open":
		warnIfStale()
		err = cmdLaunch()
	case "auth":
		err = runAuth(os.Args[2:])
	case "store":
		warnIfStale()
		err = runStore(os.Args[2:])
	case "note":
		warnIfStale()
		err = runNote(os.Args[2:])
	case "guide":
		err = cmdGuide(os.Args[2:])
	case "version", "--version", "-v":
		fmt.Println("simsync version " + version)
	default:
		fmt.Fprintf(os.Stderr, "알 수 없는 명령: %s\n\n%s\n", cmd, usage)
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "오류:", err)
		os.Exit(1)
	}
}
