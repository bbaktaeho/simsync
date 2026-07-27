package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
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
// 앱에 연결된 스토어(repos.json 첫 엔트리)가 그 사이 바뀌었으면 클론이 다른
// 스토어를 가리키는 셈이므로 거부한다 — 스토어는 앱과 CLI가 항상 같아야 한다.
func requireConfig() (*cliConfig, error) {
	c, err := loadConfig()
	if err != nil {
		return nil, err
	}
	if c == nil {
		return nil, errors.New("노트 스토어가 설정되지 않았습니다. 먼저 'simsync store clone'을 실행하세요.")
	}
	if shared, _ := loadSharedStore(); shared != nil && shared.fullName() != c.Repo {
		return nil, fmt.Errorf(
			"앱에 연결된 스토어(%s)와 클론(%s)이 다릅니다. 'simsync store clone'으로 다시 클론하세요.",
			shared.fullName(), c.Repo)
	}
	// 클론이 지워졌거나 옮겨졌으면 여기서 멈춘다. 통과시키면 note new가 stale
	// 경로에 디렉토리를 새로 만들고 노트를 써서, git 밖에 고아 파일이 남는다.
	// (.git은 worktree에서 파일일 수 있어 종류는 보지 않고 존재만 확인한다.)
	if _, err := os.Stat(filepath.Join(c.ClonePath, ".git")); err != nil {
		return nil, fmt.Errorf(
			"클론이 없습니다 (%s). 'simsync store clone'으로 다시 클론하세요.", c.ClonePath)
	}
	return c, nil
}

// ── 앱과 공유하는 스토어 선택 (~/.simsync/repos.json) ──
//
// 데스크톱 앱의 RepoCache와 같은 파일이다. 앱은 "첫 번째 엔트리"를 활성
// 스토어로 복원하므로, CLI도 첫 엔트리를 스토어로 삼고, CLI가 스토어를 새로
// 연결하면 첫 엔트리로 기록해 앱이 다음 시작에 그대로 가져가게 한다.

// repoEntry는 데스크톱 RepoEntry.toJson()과 같은 필드다. connectedAt이 없으면
// 앱 파싱(DateTime.parse)이 실패해 캐시 전체가 무시되므로 반드시 채운다.
type repoEntry struct {
	Owner       string `json:"owner"`
	Repo        string `json:"repo"`
	Branch      string `json:"branch"`
	ConnectedAt string `json:"connectedAt"`
}

func (r repoEntry) fullName() string { return r.Owner + "/" + r.Repo }

func sharedStorePath() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".simsync", "repos.json"), nil
}

func loadSharedRepos() ([]repoEntry, error) {
	path, err := sharedStorePath()
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
	var entries []repoEntry
	if err := json.Unmarshal(raw, &entries); err != nil {
		// 앱(RepoCache.load)과 같은 규칙: 손상은 빈 목록으로 취급.
		return nil, nil
	}
	for i := range entries {
		if entries[i].Branch == "" {
			entries[i].Branch = "main"
		}
	}
	return entries, nil
}

// loadSharedStore는 앱이 활성 스토어로 쓰는 첫 엔트리를 돌려준다. 없으면 nil.
func loadSharedStore() (*repoEntry, error) {
	entries, err := loadSharedRepos()
	if err != nil || len(entries) == 0 {
		return nil, err
	}
	return &entries[0], nil
}

// shareStoreIfUnset은 앱에 스토어가 없었을 때(클론/재설정 성공 후) [entry]를
// 공유 설정에 기록한다 — 성공 이후에만 불러, 잘못된 repo가 앱에 연결되는
// 일을 막는다. 앱은 다음 시작에 이 스토어를 그대로 활성화한다.
func shareStoreIfUnset(shared *repoEntry, entry repoEntry) error {
	if shared != nil {
		return nil
	}
	entry.ConnectedAt = time.Now().Format(time.RFC3339)
	if err := setSharedStore(entry); err != nil {
		return err
	}
	fmt.Println("앱에도 이 스토어를 연결했습니다 (다음 앱 시작에 적용).")
	return nil
}

// setSharedStore는 [entry]를 첫 엔트리로 기록한다 (앱 RepoCache.add와 같은
// 중복 제거 + 최신 우선). 앱은 다음 시작에 이 엔트리를 활성 스토어로 복원한다.
func setSharedStore(entry repoEntry) error {
	entries, err := loadSharedRepos()
	if err != nil {
		return err
	}
	filtered := []repoEntry{entry}
	for _, e := range entries {
		if e.fullName() != entry.fullName() {
			filtered = append(filtered, e)
		}
	}
	path, err := sharedStorePath()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	raw, err := json.Marshal(filtered)
	if err != nil {
		return err
	}
	return os.WriteFile(path, raw, 0o644)
}

// credentialHelperSpec은 클론에 등록할 credential helper 명령을 만든다.
//
// PATH에서 simsync를 찾을 수 있으면 이름만 쓴다 — 바이너리를 PATH 안에서
// 옮기거나 새 버전으로 교체해도 클론 설정을 고칠 필요가 없다. 못 찾으면
// (PATH에 설치하지 않고 직접 실행한 경우) 현재 실행 파일의 절대 경로로
// 폴백한다. 이때는 바이너리를 옮기면 store clone을 다시 실행해야 한다.
func credentialHelperSpec() (string, error) {
	if _, err := exec.LookPath("simsync"); err == nil {
		return "!simsync auth git-credential", nil
	}
	exe, err := os.Executable()
	if err != nil {
		return "", err
	}
	return "!" + exe + " auth git-credential", nil
}

// setCredentialHelper는 [dir] 클론의 local 설정에 helper를 등록한다.
//
// 빈 값을 먼저 넣어 상위 스코프의 helper 목록을 리셋하는 것이 핵심이다.
// macOS의 Xcode git은 시스템 설정에 `credential.helper = osxkeychain`을 박아
// 두는데, git은 system → global → local 순으로 helper를 시도하므로 keychain에
// github.com 자격 증명이 있으면 거기서 답이 나오고 우리 helper까지 오지 않는다
// (= SimSync 세션이 아닌 다른 신원으로 인증됨). 리셋은 이 클론에만 적용되므로
// 사용자의 다른 저장소에는 영향이 없다.
func setCredentialHelper(dir, spec string) error {
	if out, err := runGit(dir, "config", "--replace-all", "credential.helper", ""); err != nil {
		return fmt.Errorf("credential helper 초기화 실패: %s", out)
	}
	if out, err := runGit(dir, "config", "--add", "credential.helper", spec); err != nil {
		return fmt.Errorf("credential helper 등록 실패: %s", out)
	}
	return nil
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
// 스토어는 앱과 CLI가 항상 같아야 한다:
//   - 인자가 없으면 앱에 연결된 스토어(repos.json 첫 엔트리)를 클론한다.
//   - 인자가 있는데 앱 스토어와 다르면 거부한다.
//   - 앱에 스토어가 없으면 인자의 repo를 클론하고 repos.json에 첫 엔트리로
//     기록한다 — 앱이 다음 시작에 이 스토어를 그대로 활성화한다.
//
// 인증은 토큰을 remote URL이나 git 설정에 남기지 않도록, 클론의 로컬 git
// 설정에 `simsync auth git-credential`을 credential helper로 등록한다 (gh CLI와
// 같은 방식). 이후 클론 안에서의 맨 git pull/push도 CLI 세션으로 인증된다.
func cmdStoreClone(args []string) error {
	if _, err := exec.LookPath("git"); err != nil {
		return errors.New("git이 설치되어 있지 않습니다.")
	}

	shared, err := loadSharedStore()
	if err != nil {
		return err
	}

	var entry repoEntry
	rest := args
	switch {
	case len(args) > 0 && repoRe.MatchString(args[0]):
		rest = args[1:]
		parts := strings.SplitN(args[0], "/", 2)
		entry = repoEntry{Owner: parts[0], Repo: parts[1], Branch: "main"}
		if shared != nil {
			if shared.fullName() != entry.fullName() {
				return fmt.Errorf(
					"앱에 연결된 스토어(%s)와 다른 저장소입니다. 스토어는 앱과 같아야 합니다.\n앱 스토어를 클론하려면 인자 없이 'simsync store clone'을 실행하세요.",
					shared.fullName())
			}
			entry = *shared // 브랜치 등은 앱 설정을 따른다
		}
	case shared != nil:
		entry = *shared
	default:
		return errors.New("연결된 스토어가 없습니다. 앱에서 저장소를 연결하거나 'simsync store clone <owner/repo>'로 지정하세요.")
	}
	repo := entry.fullName()

	dir := ""
	if len(rest) > 0 {
		dir = rest[0]
	} else {
		home, err := os.UserHomeDir()
		if err != nil {
			return err
		}
		dir = filepath.Join(home, ".simsync", "store", filepath.FromSlash(repo))
	}
	dir, err = filepath.Abs(dir)
	if err != nil {
		return err
	}

	helper, err := credentialHelperSpec()
	if err != nil {
		return err
	}

	// 이미 클론된 디렉토리면 설정과 credential helper만 갱신한다 (재클론 강요
	// 없음 — helper는 바이너리 경로가 바뀌었을 수 있어 항상 다시 쓴다).
	if _, statErr := os.Stat(filepath.Join(dir, ".git")); statErr == nil {
		if err := setCredentialHelper(dir, helper); err != nil {
			return err
		}
		if err := saveConfig(&cliConfig{Repo: repo, ClonePath: dir}); err != nil {
			return err
		}
		if err := shareStoreIfUnset(shared, entry); err != nil {
			return err
		}
		fmt.Printf("이미 클론이 있습니다: %s\n설정을 갱신했습니다.\n", dir)
		return nil
	}

	// --config는 초기 fetch부터 적용되고 클론의 로컬 설정으로 저장된다.
	// 빈 값을 먼저 줘 상위 스코프 helper(osxkeychain 등)를 리셋한다 —
	// [setCredentialHelper] 주석 참고.
	cmd := exec.Command("git", "clone",
		"--branch", entry.Branch,
		"--config", "credential.helper=",
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
	if err := shareStoreIfUnset(shared, entry); err != nil {
		return err
	}
	fmt.Printf("\n클론 완료: %s\n", dir)
	fmt.Println("다음 단계: 클론의 AGENTS.md와 .agents/ 지침을 읽고, 'simsync note new'로 노트를 만드세요.")
	return nil
}

// cmdStoreStatus는 스토어 상태를 요약한다: 앱과 공유되는 활성 스토어,
// 클론 위치와 존재 여부. agent가 작업 환경을 확인하는 용도.
func cmdStoreStatus() error {
	shared, err := loadSharedStore()
	if err != nil {
		return err
	}
	if shared == nil {
		fmt.Println("스토어:    연결 안 됨 (앱에서 저장소를 연결하거나 'simsync store clone <owner/repo>')")
	} else {
		fmt.Printf("스토어:    %s (branch %s) — 앱과 공유 (~/.simsync/repos.json)\n",
			shared.fullName(), shared.Branch)
	}
	cfg, err := loadConfig()
	if err != nil {
		return err
	}
	if cfg == nil {
		fmt.Println("클론:      없음 ('simsync store clone'으로 생성)")
		return nil
	}
	if _, err := os.Stat(filepath.Join(cfg.ClonePath, ".git")); err != nil {
		fmt.Printf("클론:      %s (경로에 클론이 없음 — 'simsync store clone' 재실행 필요)\n", cfg.ClonePath)
		return nil
	}
	fmt.Printf("클론:      %s (%s)\n", cfg.ClonePath, cfg.Repo)
	if shared != nil && shared.fullName() != cfg.Repo {
		fmt.Println("경고:      클론이 앱 스토어와 다릅니다. 'simsync store clone'으로 다시 클론하세요.")
	}
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
//
// 토큰은 https + github.com 요청에만 내준다 — 클론에 다른 host의 remote나
// submodule이 (악의적으로든 실수로든) 추가돼도 GitHub 토큰이 그쪽으로 새지
// 않는다. 해당 없으면 아무것도 출력하지 않고 정상 종료해 git이 다음 helper로
// 넘어가게 한다.
func cmdGitCredential(args []string) error {
	op := ""
	if len(args) > 0 {
		op = args[0]
	}
	// git은 stdin으로 key=value 목록을 준다 — 프로토콜상 항상 읽어 소비한다.
	fields := map[string]string{}
	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			break
		}
		if k, v, ok := strings.Cut(line, "="); ok {
			fields[k] = v
		}
	}
	if op != "get" {
		return nil
	}
	if fields["protocol"] != "https" || fields["host"] != "github.com" {
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
