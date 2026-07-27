package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"
)

func tempHome(t *testing.T) string {
	t.Helper()
	home := t.TempDir()
	t.Setenv("HOME", home)
	return home
}

func TestSessionRoundtripAndPermissions(t *testing.T) {
	home := tempHome(t)

	in := &AuthSession{
		Provider:    "github",
		AccessToken: "tok",
		TokenType:   "bearer",
		Scope:       "read:user repo",
		IssuedAt:    time.Date(2026, 7, 27, 15, 0, 0, 0, time.Local),
		ExpiresAt:   time.Date(2026, 7, 28, 15, 0, 0, 0, time.Local),
		User:        AuthUser{ID: "1", Login: "bbaktaeho", AvatarURL: "https://a"},
	}
	if err := saveSession(in); err != nil {
		t.Fatal(err)
	}

	// 데스크톱 앱(FileSessionStore)과 같은 파일을 공유한다.
	path := filepath.Join(home, "Library", "Application Support",
		"com.simsync.simsync", "auth", "session.json")
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if runtime.GOOS != "windows" && info.Mode().Perm() != 0o600 {
		t.Errorf("perm = %o, want 600", info.Mode().Perm())
	}

	// 데스크톱 AuthSession.toJson()과 같은 필드명이어야 한다 (2차 세션 공유 대비).
	raw, _ := os.ReadFile(path)
	var fields map[string]any
	if err := json.Unmarshal(raw, &fields); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{
		"provider", "accessToken", "tokenType", "scope", "issuedAt", "expiresAt", "user",
	} {
		if _, ok := fields[key]; !ok {
			t.Errorf("missing field %q", key)
		}
	}

	out, err := loadSession()
	if err != nil {
		t.Fatal(err)
	}
	if out == nil || out.AccessToken != "tok" || out.User.Login != "bbaktaeho" {
		t.Errorf("loaded = %+v", out)
	}
	if !out.ExpiresAt.Equal(in.ExpiresAt) {
		t.Errorf("expiresAt = %v", out.ExpiresAt)
	}
}

func TestLoadSessionAbsentAndCorrupt(t *testing.T) {
	tempHome(t)

	s, err := loadSession()
	if err != nil || s != nil {
		t.Fatalf("absent: s=%v err=%v", s, err)
	}

	path, err := sessionPath()
	if err != nil {
		t.Fatal(err)
	}
	os.MkdirAll(filepath.Dir(path), 0o700)
	os.WriteFile(path, []byte("{broken"), 0o600)

	s, err = loadSession()
	if err != nil || s != nil {
		t.Fatalf("corrupt: s=%v err=%v", s, err)
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Error("손상된 세션 파일은 제거되어야 한다")
	}
}

// 데스크톱 앱(Dart)이 쓴 세션을 그대로 읽는다: 로컬 ISO8601(오프셋 없음)
// 타임스탬프 + 같은 필드명. "앱에 로그인돼 있으면 CLI 로그인 불필요"의 근거.
func TestLoadSessionWrittenByDesktopApp(t *testing.T) {
	tempHome(t)
	path, err := sessionPath()
	if err != nil {
		t.Fatal(err)
	}
	os.MkdirAll(filepath.Dir(path), 0o755)
	dartJSON := `{
	  "provider": "github",
	  "accessToken": "gho_from_app",
	  "tokenType": "bearer",
	  "scope": "read:user,repo",
	  "issuedAt": "2026-07-27T21:56:04.123456",
	  "expiresAt": "2026-07-28T21:56:04.123456",
	  "user": {"id": "1", "login": "bbaktaeho", "name": null, "avatarUrl": "https://a"}
	}`
	os.WriteFile(path, []byte(dartJSON), 0o644)

	s, err := loadSession()
	if err != nil || s == nil {
		t.Fatalf("s=%v err=%v", s, err)
	}
	if s.AccessToken != "gho_from_app" || s.User.Login != "bbaktaeho" {
		t.Errorf("session = %+v", s)
	}
	want := time.Date(2026, 7, 28, 21, 56, 4, 123456000, time.Local)
	if !s.ExpiresAt.Equal(want) {
		t.Errorf("expiresAt = %v, want %v", s.ExpiresAt, want)
	}
}

func TestClearSession(t *testing.T) {
	tempHome(t)

	existed, err := clearSession()
	if err != nil || existed {
		t.Fatalf("no file: existed=%v err=%v", existed, err)
	}

	saveSession(&AuthSession{AccessToken: "tok"})
	existed, err = clearSession()
	if err != nil || !existed {
		t.Fatalf("with file: existed=%v err=%v", existed, err)
	}
}

func TestExpiredAndFormatDuration(t *testing.T) {
	now := time.Now()
	s := &AuthSession{ExpiresAt: now.Add(time.Hour)}
	if s.expired(now) {
		t.Error("1시간 남음 = not expired")
	}
	if !s.expired(now.Add(2 * time.Hour)) {
		t.Error("지난 시각 = expired")
	}

	cases := map[time.Duration]string{
		30 * time.Second:              "1분 미만",
		41 * time.Minute:              "41분",
		23*time.Hour + 41*time.Minute: "23시간 41분",
		-(3 * time.Hour):              "3시간 0분",
	}
	for d, want := range cases {
		if got := formatDuration(d); got != want {
			t.Errorf("formatDuration(%v) = %q, want %q", d, got, want)
		}
	}
}
