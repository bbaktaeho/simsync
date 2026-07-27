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

const usage = `simsync - SimSync CLI

사용법:
  simsync            SimSync 데스크톱 앱을 실행한다
  simsync login      GitHub Device Flow로 로그인한다
  simsync logout     저장된 세션을 삭제한다
  simsync status     로그인 상태와 세션 만료를 확인한다 (만료/미로그인이면 exit 1)
  simsync version    CLI 버전을 출력한다
  simsync help       이 도움말을 출력한다

환경변수:
  SIMSYNC_GITHUB_CLIENT_ID   포크에서 자체 OAuth App을 쓸 때 client_id 오버라이드

세션 파일: ~/.simsync/cli/session.json (0600)`

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
// `simsync status || simsync login` 같은 스크립트 연동을 위해서다.
func cmdStatus() error {
	s, err := loadSession()
	if err != nil {
		return err
	}
	if s == nil {
		fmt.Println("로그인되어 있지 않습니다. 'simsync login'으로 로그인하세요.")
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
		fmt.Println("\n세션이 만료되었습니다. 'simsync login'으로 다시 로그인하세요.")
		os.Exit(1)
	}
	fmt.Printf("만료:      %s (%s 남음)\n",
		formatTime(s.ExpiresAt), formatDuration(s.ExpiresAt.Sub(now)))
	if state == tokenInvalid {
		os.Exit(1)
	}
	return nil
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
	case "login":
		err = cmdLogin()
	case "logout":
		err = cmdLogout()
	case "status":
		err = cmdStatus()
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
