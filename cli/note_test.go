package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// 클론 설정을 temp로 만들어 note new를 실행할 준비를 한다.
// requireConfig가 클론 존재를 .git으로 확인하므로 마커를 함께 만든다.
func setupClone(t *testing.T) string {
	t.Helper()
	tempHome(t)
	clone := t.TempDir()
	if err := os.MkdirAll(filepath.Join(clone, ".git"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := saveConfig(&cliConfig{Repo: "o/r", ClonePath: clone}); err != nil {
		t.Fatal(err)
	}
	return clone
}

func TestNoteNewScaffold(t *testing.T) {
	clone := setupClone(t)

	if err := cmdNoteNew([]string{
		"--date", "2026-07-27", "--title", "회의록", "--tags", "work, idea",
	}); err != nil {
		t.Fatal(err)
	}

	path := filepath.Join(clone, "notes", "2026-07", "27", "회의록.md")
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	content := string(raw)
	for _, want := range []string{
		"---\n",
		"title: \"회의록\"\n",
		"note_date: 2026-07-27\n",
		"is_default: true\n", // 그 날짜의 첫 일일 노트
		"is_memo: false\n",
		"tags: [\"work\", \"idea\"]\n",
		"created_at: ",
	} {
		if !strings.Contains(content, want) {
			t.Errorf("missing %q in:\n%s", want, content)
		}
	}
	// 타임스탬프는 데스크톱 포맷(콜론 없는 오프셋)이어야 한다.
	if !strings.Contains(content, time.Now().Format("-0700")) {
		t.Errorf("offset format mismatch:\n%s", content)
	}

	// 같은 제목 재생성은 거부된다.
	err = cmdNoteNew([]string{"--date", "2026-07-27", "--title", "회의록"})
	if err == nil || !strings.Contains(err.Error(), "이미 있습니다") {
		t.Errorf("dup err = %v", err)
	}

	// 두 번째 일일 노트는 default가 아니다.
	if err := cmdNoteNew([]string{"--date", "2026-07-27", "--title", "둘째"}); err != nil {
		t.Fatal(err)
	}
	raw2, _ := os.ReadFile(filepath.Join(clone, "notes", "2026-07", "27", "둘째.md"))
	if !strings.Contains(string(raw2), "is_default: false\n") {
		t.Errorf("second note must not be default:\n%s", raw2)
	}
}

func TestNoteNewMemoDoesNotTakeDefault(t *testing.T) {
	clone := setupClone(t)

	// 메모 먼저: default 아님, 제목 없으면 id가 파일명.
	if err := cmdNoteNew([]string{"--date", "2026-08-01", "--memo"}); err != nil {
		t.Fatal(err)
	}
	files, _ := filepath.Glob(filepath.Join(clone, "notes", "2026-08", "01", "*.md"))
	if len(files) != 1 {
		t.Fatalf("files = %v", files)
	}
	memoRaw, _ := os.ReadFile(files[0])
	if !strings.Contains(string(memoRaw), "is_memo: true\n") ||
		!strings.Contains(string(memoRaw), "is_default: false\n") {
		t.Errorf("memo frontmatter:\n%s", memoRaw)
	}

	// 메모만 있는 날짜의 첫 일일 노트는 여전히 default다 (앱 규칙과 동일).
	if err := cmdNoteNew([]string{"--date", "2026-08-01", "--title", "daily"}); err != nil {
		t.Fatal(err)
	}
	dailyRaw, _ := os.ReadFile(filepath.Join(clone, "notes", "2026-08", "01", "daily.md"))
	if !strings.Contains(string(dailyRaw), "is_default: true\n") {
		t.Errorf("daily after memo must be default:\n%s", dailyRaw)
	}
}

// 로컬 노트는 클론이 아니라 앱의 로컬 스토어에 만들어지고, 동기화 노트와 같은
// 레이아웃을 쓰되 기본 노트가 되지 않는다 (앱 규칙).
func TestNoteNewLocal(t *testing.T) {
	tempHome(t)
	base := t.TempDir()
	t.Setenv("SIMSYNC_LOCAL_NOTE_PATH", base)

	// 클론 설정이 없어도 로컬 노트는 만들 수 있어야 한다.
	if err := cmdNoteNew([]string{
		"--local", "--date", "2026-08-05", "--title", "로컬메모장",
	}); err != nil {
		t.Fatal(err)
	}

	path := filepath.Join(base, "notes", "2026-08", "05", "로컬메모장.md")
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	content := string(raw)
	if !strings.Contains(content, "is_memo: false\n") {
		t.Errorf("frontmatter:\n%s", content)
	}
	// 로컬 노트는 그 날짜의 첫 노트여도 기본 노트가 아니다.
	if !strings.Contains(content, "is_default: false\n") {
		t.Errorf("로컬 노트는 기본 노트가 되면 안 된다:\n%s", content)
	}

	// 로컬 메모도 만들 수 있다.
	if err := cmdNoteNew([]string{"--local", "--date", "2026-08-05", "--memo"}); err != nil {
		t.Fatal(err)
	}
	files, _ := filepath.Glob(filepath.Join(base, "notes", "2026-08", "05", "*.md"))
	if len(files) != 2 {
		t.Fatalf("files = %v", files)
	}
}

// --path는 앱 설정보다 우선한다 (스토어를 옮겨 쓰는 경우).
func TestNoteNewLocalExplicitPath(t *testing.T) {
	tempHome(t)
	t.Setenv("SIMSYNC_LOCAL_NOTE_PATH", t.TempDir()) // 무시되어야 한다
	explicit := t.TempDir()

	if err := cmdNoteNew([]string{
		"--local", "--path", explicit, "--date", "2026-08-05", "--title", "지정",
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(
		filepath.Join(explicit, "notes", "2026-08", "05", "지정.md")); err != nil {
		t.Fatal(err)
	}
}

// --path만 주면 어디에 쓰라는 것인지 모호하다 — 동기화 노트 경로는 클론이 정한다.
func TestNoteNewPathRequiresLocal(t *testing.T) {
	tempHome(t)
	err := cmdNoteNew([]string{"--path", t.TempDir(), "--title", "x"})
	if err == nil || !strings.Contains(err.Error(), "--local") {
		t.Errorf("err = %v", err)
	}
}

// 로컬 스토어 루트는 앱 설정을 따라가야 한다 (같은 디렉토리를 봐야 서로의
// 노트가 보인다). 환경변수는 그 위의 오버라이드다.
func TestLocalStoreBaseEnvOverride(t *testing.T) {
	tempHome(t)
	t.Setenv("SIMSYNC_LOCAL_NOTE_PATH", "/tmp/custom-store")
	got, err := localStoreBase()
	if err != nil {
		t.Fatal(err)
	}
	if got != "/tmp/custom-store" {
		t.Errorf("base = %q", got)
	}
}

func TestSanitizeTitle(t *testing.T) {
	if got := sanitizeTitle(`a/b\c:d*e?f"g<h>i|j`); got != "abcdefghij" {
		t.Errorf("sanitized = %q", got)
	}
}

func TestNoteNewWithoutConfig(t *testing.T) {
	tempHome(t)
	err := cmdNoteNew([]string{"--title", "x"})
	if err == nil || !strings.Contains(err.Error(), "store clone") {
		t.Errorf("err = %v", err)
	}
}

// 클론이 지워졌는데 설정만 남은 경우: 노트를 쓰지 않고 멈춰야 한다.
// (통과시키면 stale 경로에 디렉토리를 만들어 git 밖에 고아 파일이 생긴다.)
func TestNoteNewRefusesMissingClone(t *testing.T) {
	clone := setupClone(t)
	if err := os.RemoveAll(clone); err != nil {
		t.Fatal(err)
	}

	err := cmdNoteNew([]string{"--date", "2026-07-28", "--title", "회의록"})
	if err == nil || !strings.Contains(err.Error(), "클론이 없습니다") {
		t.Fatalf("err = %v", err)
	}
	if _, statErr := os.Stat(clone); !os.IsNotExist(statErr) {
		t.Error("실패한 note new가 클론 경로를 되살리면 안 된다")
	}
}
