package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"time"
)

// 데스크톱 SessionPolicy(maxAge: 24h)와 동일한 만료 정책.
const sessionMaxAge = 24 * time.Hour

// 만료가 이 시간 미만으로 남으면 상시 체크가 경고를 띄운다.
const sessionWarnWindow = 2 * time.Hour

// AuthUser / AuthSession은 데스크톱 auth_models.dart의 toJson()과 같은 필드를
// 쓴다 — 2차에서 앱 세션 공유로 갈 때 포맷 호환을 미리 확보한다.
// (타임스탬프만 다르다: Go는 RFC3339(타임존 포함), Dart는 로컬 ISO8601.
//
//	CLI가 앱 세션 파일을 직접 읽게 되는 시점에 커스텀 파싱을 붙인다.)
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

func sessionPath() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
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
		fmt.Fprintf(os.Stderr, "[알림] 세션이 만료되었습니다 (%s). 'simsync login'으로 다시 로그인하세요.\n",
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

// formatDuration은 "23시간 41분", "41분", "1분 미만" 형태로 표시한다.
func formatDuration(d time.Duration) string {
	if d < 0 {
		d = -d
	}
	if d < time.Minute {
		return "1분 미만"
	}
	h := int(d.Hours())
	m := int(d.Minutes()) % 60
	if h == 0 {
		return fmt.Sprintf("%d분", m)
	}
	return fmt.Sprintf("%d시간 %d분", h, m)
}
