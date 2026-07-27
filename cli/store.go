package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
)

// 노트 스토어 클론 설정: ~/.simsync/cli/config.json
type cliConfig struct {
	Repo      string `json:"repo"`      // owner/name
	ClonePath string `json:"clonePath"` // 로컬 클론 절대 경로
}

func configPath() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".simsync", "cli", "config.json"), nil
}

// loadConfig는 설정이 없으면 (nil, nil).
func loadConfig() (*cliConfig, error) {
	path, err := configPath()
	if err != nil {
		return nil, err
	}
	raw, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var c cliConfig
	if err := json.Unmarshal(raw, &c); err != nil {
		return nil, fmt.Errorf("설정 파일이 손상되었습니다 (%s): %w", path, err)
	}
	return &c, nil
}

func saveConfig(c *cliConfig) error {
	path, err := configPath()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	raw, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, raw, 0o600)
}

// requireConfig는 store clone이 선행되지 않았으면 안내와 함께 실패한다.
func requireConfig() (*cliConfig, error) {
	c, err := loadConfig()
	if err != nil {
		return nil, err
	}
	if c == nil {
		return nil, errors.New("노트 스토어가 설정되지 않았습니다. 먼저 'simsync store clone <owner/repo>'를 실행하세요.")
	}
	return c, nil
}

var repoRe = regexp.MustCompile(`^[\w.-]+/[\w.-]+$`)

// 테스트에서 로컬 bare repo(file://)로 바꿔치기한다.
var gitRemoteURL = func(repo string) string {
	return "https://github.com/" + repo + ".git"
}

func runGit(dir string, args ...string) (string, error) {
	cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
	out, err := cmd.CombinedOutput()
	return strings.TrimSpace(string(out)), err
}

// cmdStoreClone은 스토어 repo를 클론하고 설정을 저장한다.
//
// 인증은 토큰을 remote URL이나 git 설정에 남기지 않도록, 클론의 로컬 git
// 설정에 `simsync auth git-credential`을 credential helper로 등록한다 (gh CLI와
// 같은 방식). 이후 클론 안에서의 맨 git pull/push도 CLI 세션으로 인증된다.
func cmdStoreClone(args []string) error {
	if len(args) < 1 || !repoRe.MatchString(args[0]) {
		return errors.New("사용법: simsync store clone <owner/repo> [디렉토리]")
	}
	repo := args[0]
	if _, err := exec.LookPath("git"); err != nil {
		return errors.New("git이 설치되어 있지 않습니다.")
	}

	dir := ""
	if len(args) > 1 {
		dir = args[1]
	} else {
		home, err := os.UserHomeDir()
		if err != nil {
			return err
		}
		dir = filepath.Join(home, ".simsync", "store", filepath.FromSlash(repo))
	}
	dir, err := filepath.Abs(dir)
	if err != nil {
		return err
	}

	exe, err := os.Executable()
	if err != nil {
		return err
	}
	helper := "!" + exe + " auth git-credential"

	// 이미 클론된 디렉토리면 설정과 credential helper만 갱신한다 (재클론 강요
	// 없음 — helper는 바이너리 경로가 바뀌었을 수 있어 항상 다시 쓴다).
	if _, statErr := os.Stat(filepath.Join(dir, ".git")); statErr == nil {
		if out, err := runGit(dir, "config", "credential.helper", helper); err != nil {
			return fmt.Errorf("credential helper 갱신 실패: %s", out)
		}
		if err := saveConfig(&cliConfig{Repo: repo, ClonePath: dir}); err != nil {
			return err
		}
		fmt.Printf("이미 클론이 있습니다: %s\n설정을 갱신했습니다.\n", dir)
		return nil
	}

	// --config는 초기 fetch부터 적용되고 클론의 로컬 설정으로 저장된다.
	cmd := exec.Command("git", "clone",
		"--config", "credential.helper="+helper,
		gitRemoteURL(repo), dir)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("클론에 실패했습니다: %w", err)
	}
	if err := saveConfig(&cliConfig{Repo: repo, ClonePath: dir}); err != nil {
		return err
	}
	fmt.Printf("\n클론 완료: %s\n", dir)
	fmt.Println("다음 단계: 클론의 AGENTS.md와 .agents/ 지침을 읽고, 'simsync note new'로 노트를 만드세요.")
	return nil
}

// cmdStoreSync는 클론을 원격과 정합시킨다: pull --rebase 후 push.
// 커밋되지 않은 변경이 있으면 rebase가 실패하므로 먼저 커밋을 요구한다.
func cmdStoreSync() error {
	cfg, err := requireConfig()
	if err != nil {
		return err
	}
	dirty, err := runGit(cfg.ClonePath, "status", "--porcelain")
	if err != nil {
		return fmt.Errorf("git status 실패: %s", dirty)
	}
	if dirty != "" {
		return errors.New("커밋되지 않은 변경이 있습니다. 클론에서 먼저 git add/commit 하세요.")
	}
	if out, err := runGit(cfg.ClonePath, "pull", "--rebase"); err != nil {
		return fmt.Errorf("pull --rebase 실패:\n%s", out)
	} else if out != "" {
		fmt.Println(out)
	}
	if out, err := runGit(cfg.ClonePath, "push"); err != nil {
		return fmt.Errorf("push 실패:\n%s", out)
	} else if out != "" {
		fmt.Println(out)
	}
	fmt.Println("동기화 완료. 앱은 다음 폴링에서 변경을 감지합니다.")
	return nil
}

// cmdGitCredential은 git credential helper 프로토콜을 구현한다 (내부용).
// get 요청에 CLI 세션의 토큰을 돌려줘, 클론 안의 모든 git 네트워크 작업이
// 별도 설정 없이 인증되게 한다. store/erase는 no-op (캐시하지 않는다).
func cmdGitCredential(args []string) error {
	op := ""
	if len(args) > 0 {
		op = args[0]
	}
	// git은 stdin으로 key=value 목록을 준다 — 프로토콜상 항상 읽어 소비한다.
	io.Copy(io.Discard, os.Stdin)
	if op != "get" {
		return nil
	}
	s, err := loadSession()
	if err != nil {
		return err
	}
	if s == nil || s.expired(timeNow()) {
		return errors.New("유효한 세션이 없습니다. 'simsync auth login'으로 로그인하세요.")
	}
	fmt.Printf("username=x-access-token\npassword=%s\n", s.AccessToken)
	return nil
}
