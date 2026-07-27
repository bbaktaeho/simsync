package main

import (
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func captureStdout(t *testing.T, fn func() error) string {
	t.Helper()
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	orig := os.Stdout
	os.Stdout = w
	callErr := fn()
	w.Close()
	os.Stdout = orig
	out, _ := io.ReadAll(r)
	if callErr != nil {
		t.Fatal(callErr)
	}
	return string(out)
}

func mustGit(t *testing.T, dir string, args ...string) string {
	t.Helper()
	out, err := runGit(dir, args...)
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return out
}

// 스토어 클론 → note new → 커밋 → sync 전체 흐름을 로컬 bare repo로 검증한다.
func TestStoreCloneNoteSyncEndToEnd(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git 없음")
	}
	tempHome(t)

	// 원격 역할의 bare repo에 초기 커밋을 심는다 (실제 스토어는 auto-init).
	bare := filepath.Join(t.TempDir(), "store.git")
	if out, err := exec.Command("git", "init", "--bare", "-b", "main", bare).CombinedOutput(); err != nil {
		t.Fatalf("init bare: %v\n%s", err, out)
	}
	seed := t.TempDir()
	if out, err := exec.Command("git", "clone", bare, seed).CombinedOutput(); err != nil {
		t.Fatalf("seed clone: %v\n%s", err, out)
	}
	mustGit(t, seed, "config", "user.email", "t@t")
	mustGit(t, seed, "config", "user.name", "t")
	os.WriteFile(filepath.Join(seed, "README.md"), []byte("# store"), 0o644)
	mustGit(t, seed, "add", "-A")
	mustGit(t, seed, "commit", "-m", "init")
	mustGit(t, seed, "push", "origin", "HEAD:main")

	// github URL 대신 로컬 bare 경로로 클론하게 바꿔치기.
	orig := gitRemoteURL
	gitRemoteURL = func(string) string { return bare }
	defer func() { gitRemoteURL = orig }()

	clone := filepath.Join(t.TempDir(), "clone")
	_ = captureStdout(t, func() error {
		return cmdStoreClone([]string{"owner/repo", clone})
	})

	cfg, err := loadConfig()
	if err != nil || cfg == nil || cfg.ClonePath != clone || cfg.Repo != "owner/repo" {
		t.Fatalf("config = %+v, err = %v", cfg, err)
	}
	// credential helper가 클론 로컬 설정에 등록됐는지 확인.
	helper := mustGit(t, clone, "config", "credential.helper")
	if !strings.Contains(helper, "auth git-credential") {
		t.Errorf("credential.helper = %q", helper)
	}

	// 노트 생성 → 커밋 → sync → 원격(bare)에 반영 확인.
	out := captureStdout(t, func() error {
		return cmdNoteNew([]string{"--date", "2026-07-27", "--title", "e2e"})
	})
	lines := strings.Split(strings.TrimSpace(out), "\n")
	notePath := lines[len(lines)-1] // 마지막 줄 = 파일 경로 (agent 계약)
	if _, err := os.Stat(notePath); err != nil {
		t.Fatalf("note path %q: %v", notePath, err)
	}

	// 커밋 전 dirty 상태에서는 sync가 거부된다.
	if err := cmdStoreSync(); err == nil || !strings.Contains(err.Error(), "커밋") {
		t.Fatalf("dirty sync err = %v", err)
	}

	mustGit(t, clone, "config", "user.email", "t@t")
	mustGit(t, clone, "config", "user.name", "t")
	mustGit(t, clone, "add", "-A")
	mustGit(t, clone, "commit", "-m", "note: e2e")
	_ = captureStdout(t, cmdStoreSync)

	files := mustGit(t, bare, "ls-tree", "-r", "main", "--name-only")
	if !strings.Contains(files, "notes/2026-07/27/e2e.md") {
		t.Errorf("bare tree:\n%s", files)
	}
}

func TestStoreCloneExistingDirUpdatesConfigOnly(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git 없음")
	}
	tempHome(t)
	dir := t.TempDir()
	if out, err := exec.Command("git", "init", dir).CombinedOutput(); err != nil {
		t.Fatalf("git init: %v\n%s", err, out)
	}

	_ = captureStdout(t, func() error {
		return cmdStoreClone([]string{"owner/repo", dir})
	})
	cfg, _ := loadConfig()
	if cfg == nil || cfg.ClonePath != dir {
		t.Fatalf("config = %+v", cfg)
	}
	// 재실행 시 credential helper가 (바이너리 이동 대비) 다시 기록된다.
	helper := mustGit(t, dir, "config", "credential.helper")
	if !strings.Contains(helper, "auth git-credential") {
		t.Errorf("credential.helper = %q", helper)
	}
}

func TestGitCredentialGet(t *testing.T) {
	tempHome(t)
	saveSession(&AuthSession{
		AccessToken: "gho_secret",
		ExpiresAt:   time.Now().Add(time.Hour),
	})

	stdinR, stdinW, _ := os.Pipe()
	stdinW.WriteString("protocol=https\nhost=github.com\n\n")
	stdinW.Close()
	origIn := os.Stdin
	os.Stdin = stdinR
	defer func() { os.Stdin = origIn }()

	out := captureStdout(t, func() error { return cmdGitCredential([]string{"get"}) })
	if !strings.Contains(out, "username=x-access-token\n") ||
		!strings.Contains(out, "password=gho_secret\n") {
		t.Errorf("out = %q", out)
	}
}

func TestGitCredentialGetExpiredSession(t *testing.T) {
	tempHome(t)
	saveSession(&AuthSession{
		AccessToken: "gho_secret",
		ExpiresAt:   time.Now().Add(-time.Hour),
	})
	stdinR, stdinW, _ := os.Pipe()
	stdinW.Close()
	origIn := os.Stdin
	os.Stdin = stdinR
	defer func() { os.Stdin = origIn }()

	if err := cmdGitCredential([]string{"get"}); err == nil {
		t.Error("만료 세션은 자격 증명을 내주지 않아야 한다")
	}
}

func TestGuideEmbeddedAndCloneOverride(t *testing.T) {
	tempHome(t)

	// 클론 설정이 없으면 내장본.
	out := captureStdout(t, func() error { return cmdGuide([]string{"note-format"}) })
	if !strings.Contains(out, "# Note Format") {
		t.Errorf("embedded guide:\n%s", out)
	}

	// 클론에 .agents/가 있으면 그쪽이 우선한다.
	clone := t.TempDir()
	saveConfig(&cliConfig{Repo: "o/r", ClonePath: clone})
	os.MkdirAll(filepath.Join(clone, ".agents"), 0o755)
	os.WriteFile(filepath.Join(clone, ".agents", "note-format.md"),
		[]byte("# Custom Rules\n"), 0o644)

	out = captureStdout(t, func() error { return cmdGuide([]string{"note-format"}) })
	if !strings.Contains(out, "# Custom Rules") {
		t.Errorf("clone guide:\n%s", out)
	}

	// 없는 가이드 이름은 오류.
	if err := cmdGuide([]string{"nope"}); err == nil {
		t.Error("unknown guide must error")
	}
}
