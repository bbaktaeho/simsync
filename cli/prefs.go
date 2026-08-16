package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

// 데스크톱 앱의 설정 도메인. 앱은 shared_preferences로 값을 저장하는데, 그
// 플러그인이 macOS에서 NSUserDefaults를 쓰면서 모든 키에 "flutter." 접두사를
// 붙인다 (실제 키는 snake_case: local_note_path, weekly_instruction, …).
const appPrefsDomain = "com.simsync.simsync"

// appPref는 데스크톱 앱 설정값 하나를 읽는다. 앱을 한 번도 실행하지 않았거나
// 그 키를 바꾼 적이 없으면 빈 문자열이다 — 없는 것은 에러가 아니라 "기본값을
// 쓰라"는 뜻이므로 호출부가 fallback을 정한다.
//
// 세션·스토어와 달리 앱 설정에는 CLI가 읽을 공유 파일이 없어서 이 경로를
// 쓴다. 동기화되는 설정(settings/settings.json)으로 옮기는 방안은
// .agent/proposal/cli-review-instructions.md 참고.
func appPref(key string) string {
	if runtime.GOOS != "darwin" {
		return ""
	}
	out, err := exec.Command("defaults", "read", appPrefsDomain, "flutter."+key).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

// localStoreBase는 로컬 노트 스토어의 루트를 정한다.
//
// 앱 설정을 우선 보는 이유: 로컬 노트는 동기화되지 않으므로, 앱과 CLI가 같은
// 디렉토리를 보지 않으면 서로가 만든 노트를 아예 못 본다.
// 우선순위: SIMSYNC_LOCAL_NOTE_PATH > 앱 설정 > 앱의 기본 경로.
func localStoreBase() (string, error) {
	if p := strings.TrimSpace(os.Getenv("SIMSYNC_LOCAL_NOTE_PATH")); p != "" {
		return p, nil
	}
	if p := appPref("local_note_path"); p != "" {
		return p, nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	// 데스크톱 defaultLocalNotePath()와 같은 기본값.
	return filepath.Join(home, "Documents", "SimSync"), nil
}
