package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// pollForToken: pending → slow_down(6초) → 성공. 백오프 반영과 토큰 반환 확인.
func TestPollForTokenPendingSlowDownThenSuccess(t *testing.T) {
	responses := []map[string]any{
		{"error": "authorization_pending"},
		{"error": "slow_down", "interval": 6},
		{"access_token": "tok-123", "token_type": "bearer", "scope": "read:user repo"},
	}
	call := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Errorf("method = %s, want POST", r.Method)
		}
		if got := r.Header.Get("Accept"); got != "application/json" {
			t.Errorf("Accept = %q", got)
		}
		if err := r.ParseForm(); err != nil {
			t.Fatal(err)
		}
		if got := r.PostForm.Get("grant_type"); got != deviceGrantType {
			t.Errorf("grant_type = %q", got)
		}
		json.NewEncoder(w).Encode(responses[call])
		call++
	}))
	defer srv.Close()

	var sleeps []time.Duration
	origURL, origSleep := tokenURL, pollSleep
	tokenURL = srv.URL
	pollSleep = func(d time.Duration) { sleeps = append(sleeps, d) }
	defer func() { tokenURL, pollSleep = origURL, origSleep }()

	tok, err := pollForToken(deviceCodeResponse{
		DeviceCode: "dev", ExpiresIn: 900, Interval: 5,
	})
	if err != nil {
		t.Fatal(err)
	}
	if tok.AccessToken != "tok-123" {
		t.Errorf("access_token = %q", tok.AccessToken)
	}
	// 폴링 3회 = sleep 3회. slow_down의 interval(6초)이 마지막 대기에 반영된다.
	want := []time.Duration{5 * time.Second, 5 * time.Second, 6 * time.Second}
	if len(sleeps) != len(want) {
		t.Fatalf("sleeps = %v", sleeps)
	}
	for i := range want {
		if sleeps[i] != want[i] {
			t.Errorf("sleeps[%d] = %v, want %v", i, sleeps[i], want[i])
		}
	}
}

func TestPollForTokenAccessDenied(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{"error": "access_denied"})
	}))
	defer srv.Close()

	origURL, origSleep := tokenURL, pollSleep
	tokenURL = srv.URL
	pollSleep = func(time.Duration) {}
	defer func() { tokenURL, pollSleep = origURL, origSleep }()

	_, err := pollForToken(deviceCodeResponse{DeviceCode: "dev", ExpiresIn: 900, Interval: 5})
	if err == nil || !strings.Contains(err.Error(), "거부") {
		t.Fatalf("err = %v", err)
	}
}

// 5xx나 비JSON 응답은 폴링을 죽이지 않고 스킵된다 (데스크톱과 같은 규칙).
func TestPollForTokenSkipsTransientErrors(t *testing.T) {
	call := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch call {
		case 0:
			w.WriteHeader(http.StatusBadGateway)
		case 1:
			w.Write([]byte("<html>not json</html>"))
		default:
			json.NewEncoder(w).Encode(map[string]any{"access_token": "tok"})
		}
		call++
	}))
	defer srv.Close()

	origURL, origSleep := tokenURL, pollSleep
	tokenURL = srv.URL
	pollSleep = func(time.Duration) {}
	defer func() { tokenURL, pollSleep = origURL, origSleep }()

	tok, err := pollForToken(deviceCodeResponse{DeviceCode: "dev", ExpiresIn: 900, Interval: 5})
	if err != nil {
		t.Fatal(err)
	}
	if tok.AccessToken != "tok" {
		t.Errorf("access_token = %q", tok.AccessToken)
	}
	if tok.TokenType != "bearer" {
		t.Errorf("token_type 기본값이 적용되어야 한다: %q", tok.TokenType)
	}
}

func TestPollForTokenDeadline(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{"error": "authorization_pending"})
	}))
	defer srv.Close()

	base := time.Now()
	elapsed := time.Duration(0)
	origURL, origSleep, origNow := tokenURL, pollSleep, timeNow
	tokenURL = srv.URL
	pollSleep = func(d time.Duration) { elapsed += d }
	timeNow = func() time.Time { return base.Add(elapsed) }
	defer func() { tokenURL, pollSleep, timeNow = origURL, origSleep, origNow }()

	_, err := pollForToken(deviceCodeResponse{DeviceCode: "dev", ExpiresIn: 12, Interval: 5})
	if err == nil || !strings.Contains(err.Error(), "만료") {
		t.Fatalf("err = %v", err)
	}
}

func TestRequestDeviceCode(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := r.ParseForm(); err != nil {
			t.Fatal(err)
		}
		if got := r.PostForm.Get("scope"); got != oauthScope {
			t.Errorf("scope = %q", got)
		}
		json.NewEncoder(w).Encode(map[string]any{
			"device_code":      "dev-1",
			"user_code":        "ABCD-1234",
			"verification_uri": "https://github.com/login/device",
			"expires_in":       899,
			"interval":         5,
		})
	}))
	defer srv.Close()

	orig := deviceCodeURL
	deviceCodeURL = srv.URL
	defer func() { deviceCodeURL = orig }()

	dc, err := requestDeviceCode()
	if err != nil {
		t.Fatal(err)
	}
	if dc.UserCode != "ABCD-1234" || dc.DeviceCode != "dev-1" {
		t.Errorf("dc = %+v", dc)
	}
}

// GitHub의 숫자 id가 데스크톱 세션 포맷(문자열)으로 변환되는지 확인.
func TestFetchUserNumericID(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got := r.Header.Get("Authorization"); got != "Bearer tok" {
			t.Errorf("Authorization = %q", got)
		}
		json.NewEncoder(w).Encode(map[string]any{
			"id": 12345678, "login": "bbaktaeho", "name": nil,
			"avatar_url": "https://example.com/a.png",
		})
	}))
	defer srv.Close()

	orig := userURL
	userURL = srv.URL
	defer func() { userURL = orig }()

	u, err := fetchUser("tok")
	if err != nil {
		t.Fatal(err)
	}
	if u.ID != "12345678" || u.Login != "bbaktaeho" || u.Name != nil {
		t.Errorf("user = %+v", u)
	}
}

func TestValidateToken(t *testing.T) {
	status := http.StatusOK
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(status)
	}))
	defer srv.Close()

	orig := userURL
	userURL = srv.URL
	defer func() { userURL = orig }()

	if got := validateToken("t"); got != tokenValid {
		t.Errorf("200 -> %v, want tokenValid", got)
	}
	status = http.StatusUnauthorized
	if got := validateToken("t"); got != tokenInvalid {
		t.Errorf("401 -> %v, want tokenInvalid", got)
	}
	status = http.StatusInternalServerError
	if got := validateToken("t"); got != tokenUnknown {
		t.Errorf("500 -> %v, want tokenUnknown", got)
	}
}
