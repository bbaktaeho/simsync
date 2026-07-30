package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"time"
)

// 데스크톱 SessionPolicy(maxAge: 30일)와 동일한 만료 정책. 앱은 세션 복원에
// 성공할 때마다 만료를 now+30일로 연장한다(sliding window). CLI 로그인은
// 같은 창으로 발급하고, 연장은 앱 쪽에서 일어난다.
const sessionMaxAge = 30 * 24 * time.Hour

// 만료가 이 시간 미만으로 남으면 상시 체크가 경고를 띄운다.
const sessionWarnWindow = 2 * time.Hour

// AuthUser / AuthSession은 데스크톱 auth_models.dart의 toJson()과 같은 필드다.
// CLI는 앱과 "같은 세션 파일"을 읽고 쓴다 — 한쪽에서 로그인하면 양쪽에 적용된다.
// 타임스탬프는 Go가 RFC3339로 쓰고(Dart DateTime.parse가 읽음), Dart가 쓴
// 로컬 ISO8601(오프셋 없음)은 [parseFlexTime]으로 읽는다.
type AuthUser struct {
	ID        string  `json:"id"`
	Login     string  `json:"login"`
	Name      *string `json:"name"`
	AvatarURL string  `json:"avatarUrl"`
}

type AuthSession struct {
	Provider    string    `json:"provider"`
	AccessToken string    `json:"accessToken"`
	TokenType   string    `json:"tokenType"`
	Scope       string    `json:"scope"`
	IssuedAt    time.Time `json:"issuedAt"`
	ExpiresAt   time.Time `json:"expiresAt"`
	User        AuthUser  `json:"user"`
}

func (s *AuthSession) expired(now time.Time) bool {
	return !s.ExpiresAt.After(now)
}

// parseFlexTime은 Go(RFC3339)와 Dart(toIso8601String — 로컬 시각, 오프셋
// 없음) 타임스탬프를 모두 읽는다. 앱이 만든 세션 파일 호환용.
func parseFlexTime(s string) (time.Time, error) {
	if t, err := time.Parse(time.RFC3339Nano, s); err == nil {
		return t, nil
	}
	return time.ParseInLocation("2006-01-02T15:04:05.999999999", s, time.Local)
}

// UnmarshalJSON은 타임스탬프만 유연 파싱하고 나머지는 그대로 받는다.
func (s *AuthSession) UnmarshalJSON(data []byte) error {
	var raw struct {
		Provider    string   `json:"provider"`
		AccessToken string   `json:"accessToken"`
		TokenType   string   `json:"tokenType"`
		Scope       string   `json:"scope"`
		IssuedAt    string   `json:"issuedAt"`
		ExpiresAt   string   `json:"expiresAt"`
		User        AuthUser `json:"user"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	issuedAt, err := parseFlexTime(raw.IssuedAt)
	if err != nil {
		return err
	}
	expiresAt, err := parseFlexTime(raw.ExpiresAt)
	if err != nil {
		return err
	}
	*s = AuthSession{
		Provider:    raw.Provider,
		AccessToken: raw.AccessToken,
		TokenType:   raw.TokenType,
		Scope:       raw.Scope,
		IssuedAt:    issuedAt,
		ExpiresAt:   expiresAt,
		User:        raw.User,
	}
	return nil
}

// sessionPath는 데스크톱 앱(FileSessionStore)이 쓰는 세션 파일과 같은 경로다.
// 같은 파일을 공유하므로: 앱에 로그인돼 있으면 CLI는 로그인이 필요 없고,
// CLI에서 로그인하면 앱이 다음 시작에 그 세션을 복원한다. (앱은 sandbox가
// 꺼져 있어 평범한 Application Support 경로를 쓴다.)
func sessionPath() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	if runtime.GOOS == "darwin" {
		return filepath.Join(home, "Library", "Application Support",
			"com.simsync.simsync", "auth", "session.json"), nil
	}
	return filepath.Join(home, ".simsync", "cli", "session.json"), nil
}

// loadSession은 세션이 없으면 (nil, nil), 파일이 손상됐으면 지우고 (nil, nil).
func loadSession() (*AuthSession, error) {
	path, err := sessionPath()
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
	var s AuthSession
	if err := json.Unmarshal(raw, &s); err != nil || s.AccessToken == "" {
		os.Remove(path)
		return nil, nil
	}
	return &s, nil
}

func saveSession(s *AuthSession) error {
	path, err := sessionPath()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	raw, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	// 토큰이 담기므로 소유자만 읽을 수 있어야 한다.
	return os.WriteFile(path, raw, 0o600)
}

// clearSession은 파일이 실제로 있었는지를 돌려준다.
func clearSession() (bool, error) {
	path, err := sessionPath()
	if err != nil {
		return false, err
	}
	err = os.Remove(path)
	if errors.Is(err, fs.ErrNotExist) {
		return false, nil
	}
	return err == nil, err
}

// warnIfStale는 모든 명령 진입 시 호출되는 상시 만료 체크다. 세션이 있고
// 만료됐거나 임박했을 때만 stderr로 한 줄 경고한다 (로그인 자체를 강요하지
// 않는다 — 앱은 자체 세션을 쓴다).
func warnIfStale() {
	s, err := loadSession()
	if err != nil || s == nil {
		return
	}
	now := time.Now()
	if s.expired(now) {
		fmt.Fprintf(os.Stderr, "[알림] 세션이 만료되었습니다 (%s). 'simsync auth login'으로 다시 로그인하세요.\n",
			formatTime(s.ExpiresAt))
		return
	}
	if remaining := s.ExpiresAt.Sub(now); remaining < sessionWarnWindow {
		fmt.Fprintf(os.Stderr, "[알림] 세션이 %s 후 만료됩니다.\n", formatDuration(remaining))
	}
}

func formatTime(t time.Time) string {
	return t.Local().Format("2006-01-02 15:04")
}

// formatDuration은 "30일", "29일 13시간", "23시간 41분", "41분", "1분 미만"
// 형태로 표시한다.
func formatDuration(d time.Duration) string {
	if d < 0 {
		d = -d
	}
	if d < time.Minute {
		return "1분 미만"
	}
	h := int(d.Hours())
	m := int(d.Minutes()) % 60
	if days := h / 24; days > 0 {
		if h%24 == 0 {
			return fmt.Sprintf("%d일", days)
		}
		return fmt.Sprintf("%d일 %d시간", days, h%24)
	}
	if h == 0 {
		return fmt.Sprintf("%d분", m)
	}
	return fmt.Sprintf("%d시간 %d분", h, m)
}
