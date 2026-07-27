package main

import (
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"time"
)

const version = "0.1.0"

// AI agent가 1차 사용자다: 각 명령은 "무엇을 하는지"와 "언제 쓰는지(용도)"를
// 함께 설명하고, exit code 계약을 명시한다.
const usage = `simsync - SimSync 노트 스토어 CLI (AI agent용)

SimSync 데스크톱 앱과 같은 GitHub 노트 스토어를 터미널에서 다룬다.
AI agent 워크플로: 작업 전 'simsync auth status'로 세션을 확인하고,
로그인이 필요하면 'simsync auth login'을 실행한 뒤 표시되는 일회용 코드의
브라우저 승인을 사용자에게 요청한다.

사용법:
  simsync <명령> [하위명령]

명령:
  (없음)         SimSync 데스크톱 앱을 실행한다 (macOS).
                 용도: 사람이 GUI로 노트를 보거나 편집하려 할 때.

  auth login     GitHub Device Flow로 로그인해 세션을 만든다. 터미널에 일회용
                 코드와 URL이 표시되며, 사람이 브라우저에서 승인해야 완료된다.
                 이미 로그인돼 있어도 새 세션으로 교체한다.
                 용도: 세션이 없거나 만료됐을 때. 브라우저 승인이 필요하므로
                 AI agent는 코드를 사용자에게 전달하고 승인을 기다린다.

  auth status    세션 상태를 출력한다: 계정, scope, 발급/만료 시각(남은 시간),
                 GitHub API 라이브 토큰 검증.
                 exit 0 = 세션 유효, exit 1 = 미로그인/만료/무효 토큰.
                 용도: 어떤 작업이든 시작하기 전 첫 명령. exit code로 분기한다.
                 예: simsync auth status || (로그인 필요 안내)

  auth logout    저장된 세션 파일을 삭제한다.
                 용도: 토큰 폐기, 계정 전환 전.

  version        CLI 버전을 출력한다.
  help           이 도움말을 출력한다.

환경변수:
  SIMSYNC_GITHUB_CLIENT_ID   포크에서 자체 OAuth App client_id 오버라이드

세션 파일: ~/.simsync/cli/session.json (0600). 만료 정책은 데스크톱 앱과
동일한 24시간. auth 이외의 명령은 실행 시 세션 만료를 자동 점검해 stderr로
경고한다 (만료됐거나 2시간 미만 남았을 때).`

const authUsage = `사용법: simsync auth <login|logout|status>

  login    GitHub Device Flow 로그인 (브라우저 승인 필요)
  logout   세션 삭제
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
	default:
		fmt.Fprintln(os.Stderr, authUsage)
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
	case "":
		// 상시 만료 체크: 세션이 있고 만료됐거나 임박했으면 경고 후 진행.
		warnIfStale()
		err = cmdLaunch()
	case "auth":
		err = runAuth(os.Args[2:])
	case "version", "--version", "-v":
		fmt.Println("simsync version " + version)
	case "help", "--help", "-h":
		fmt.Println(usage)
	default:
		fmt.Fprintf(os.Stderr, "알 수 없는 명령: %s\n\n%s\n", cmd, usage)
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "오류:", err)
		os.Exit(1)
	}
}
