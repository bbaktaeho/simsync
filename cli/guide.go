package main

import (
	"embed"
	"fmt"
	"os"
	"path/filepath"
)

// 스토어 하네스(.agents/)의 canonical 사본. 클론이 설정돼 있으면 클론 쪽
// (사용자 커스텀 반영)을 우선하고, 없을 때 이 내장본을 출력한다.
// 원문은 데스크톱 agent_harness.dart 템플릿과 동일하게 유지한다.
//
//go:embed guides/*.md
var embeddedGuides embed.FS

var guideNames = map[string]string{
	"overview":    "README.md",
	"note-format": "note-format.md",
	"guidelines":  "guidelines.md",
}

// cmdGuide는 노트 작성/작업 규칙을 출력한다 — AI agent가 노트를 만들기 전에
// 읽는 용도. 인수 없이 실행하면 목록을 보여준다.
func cmdGuide(args []string) error {
	name := "overview"
	if len(args) > 0 {
		name = args[0]
	}
	file, ok := guideNames[name]
	if !ok {
		return fmt.Errorf("없는 가이드입니다: %s (가능: overview, note-format, guidelines)", name)
	}

	// 1순위: 클론의 .agents/ (사용자가 규칙을 고쳤다면 그것이 진실).
	if cfg, err := loadConfig(); err == nil && cfg != nil {
		path := filepath.Join(cfg.ClonePath, ".agents", file)
		if raw, err := os.ReadFile(path); err == nil {
			fmt.Fprintf(os.Stderr, "[출처] %s\n", path)
			fmt.Print(string(raw))
			return nil
		}
	}

	// 2순위: CLI 내장 canonical 사본.
	raw, err := embeddedGuides.ReadFile("guides/" + file)
	if err != nil {
		return err
	}
	fmt.Fprintln(os.Stderr, "[출처] CLI 내장본 (클론이 없거나 클론에 .agents/가 없음)")
	fmt.Print(string(raw))
	return nil
}
