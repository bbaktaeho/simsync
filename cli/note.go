package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// 데스크톱 GitHubNoteStorage와 같은 규칙:
// 경로   notes/YYYY-MM/DD/{sanitized-title|id}.md
// 제목   / \ : * ? " < > | 제거가 파일명
// id     생성 시각 밀리초 타임스탬프 문자열
var invalidTitleChars = regexp.MustCompile(`[/\\:*?"<>|]`)

func sanitizeTitle(title string) string {
	return invalidTitleChars.ReplaceAllString(title, "")
}

// 데스크톱 _formatDateTime과 같은 포맷: 2026-07-27T09:00:00+0900 (콜론 없는 오프셋)
const noteTimeLayout = "2006-01-02T15:04:05-0700"

// buildNoteFile은 노트 스캐폴드 마크다운(frontmatter + 빈 본문)을 만든다.
func buildNoteFile(id, title string, date time.Time, isDefault, isMemo bool, tags []string, now time.Time) string {
	quoted := make([]string, len(tags))
	for i, t := range tags {
		quoted[i] = `"` + t + `"`
	}
	var b strings.Builder
	b.WriteString("---\n")
	fmt.Fprintf(&b, "id: %q\n", id)
	fmt.Fprintf(&b, "title: %q\n", title)
	fmt.Fprintf(&b, "note_date: %s\n", date.Format("2006-01-02"))
	fmt.Fprintf(&b, "is_default: %t\n", isDefault)
	fmt.Fprintf(&b, "is_memo: %t\n", isMemo)
	fmt.Fprintf(&b, "tags: [%s]\n", strings.Join(quoted, ", "))
	fmt.Fprintf(&b, "created_at: %s\n", now.Format(noteTimeLayout))
	fmt.Fprintf(&b, "updated_at: %s\n", now.Format(noteTimeLayout))
	b.WriteString("---\n")
	return b.String()
}

// hasDailyNote는 날짜 디렉토리에 (메모가 아닌) 일일 노트가 이미 있는지 본다.
// 앱 규칙: 날짜의 첫 일일 노트만 is_default=true — 메모는 세지 않는다.
func hasDailyNote(dayDir string) bool {
	entries, err := filepath.Glob(filepath.Join(dayDir, "*.md"))
	if err != nil {
		return false
	}
	for _, path := range entries {
		raw, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		if !strings.Contains(string(raw), "\nis_memo: true") {
			return true
		}
	}
	return false
}

// cmdNoteNew는 클론 안에 규칙대로 노트 파일을 스캐폴드한다. 본문 작성은
// agent 몫 — 생성된 파일의 절대 경로를 stdout 마지막 줄에 출력한다.
func cmdNoteNew(args []string) error {
	fs := flag.NewFlagSet("note new", flag.ContinueOnError)
	dateStr := fs.String("date", time.Now().Format("2006-01-02"), "노트 날짜 (YYYY-MM-DD, 기본 오늘)")
	title := fs.String("title", "", "노트 제목 (파일명으로도 쓰임)")
	memo := fs.Bool("memo", false, "메모로 생성 (날짜 무관 빠른 기록)")
	tagsStr := fs.String("tags", "", "쉼표로 구분한 태그 (예: work,idea)")
	if err := fs.Parse(args); err != nil {
		return err
	}

	cfg, err := requireConfig()
	if err != nil {
		return err
	}
	date, err := time.ParseInLocation("2006-01-02", *dateStr, time.Local)
	if err != nil {
		return fmt.Errorf("날짜 형식이 잘못되었습니다 (YYYY-MM-DD): %s", *dateStr)
	}

	var tags []string
	for _, t := range strings.Split(*tagsStr, ",") {
		if t = strings.TrimSpace(t); t != "" {
			tags = append(tags, t)
		}
	}

	now := time.Now()
	id := strconv.FormatInt(now.UnixMilli(), 10)
	name := sanitizeTitle(*title)
	if name == "" {
		name = id
	}
	dayDir := filepath.Join(cfg.ClonePath, "notes",
		date.Format("2006-01"), date.Format("02"))
	path := filepath.Join(dayDir, name+".md")
	if _, err := os.Stat(path); err == nil {
		return fmt.Errorf("같은 제목의 노트가 이미 있습니다: %s", path)
	}

	isDefault := !*memo && !hasDailyNote(dayDir)
	if err := os.MkdirAll(dayDir, 0o755); err != nil {
		return err
	}
	content := buildNoteFile(id, *title, date, isDefault, *memo, tags, now)
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		return err
	}

	fmt.Println("노트 스캐폴드를 만들었습니다. frontmatter는 수정하지 말고 본문만 작성하세요.")
	fmt.Println()
	fmt.Println("본문 작성 규칙 (템플릿 예시: simsync guide note-format):")
	fmt.Println("  - 본문은 ## 헤더로 시작하고, 주제가 바뀌면 헤더로 섹션을 나눈다")
	fmt.Println("  - 나열은 \"- \" 리스트로 쓴다")
	fmt.Println("  - 키워드나 핵심 값은 `백틱`으로 강조한다")
	fmt.Println("  - 명령어, 코드, 로그는 코드블록(```)에 넣는다")
	fmt.Println("  - 같은 꼴의 항목이 반복되는 정돈된 내용은 표로 정리한다")
	fmt.Println()
	fmt.Println("작성 후: 클론에서 git add/commit → 'simsync store sync'")
	fmt.Println(path)
	return nil
}

func runNote(args []string) error {
	sub := ""
	if len(args) > 0 {
		sub = args[0]
	}
	switch sub {
	case "new":
		return cmdNoteNew(args[1:])
	default:
		return errors.New("사용법: simsync note new [--date YYYY-MM-DD] [--title 제목] [--memo] [--tags a,b]")
	}
}
