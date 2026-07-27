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
