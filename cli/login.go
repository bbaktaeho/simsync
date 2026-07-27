package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

// 데스크톱 github_oauth_provider.dart의 Device Flow 이식. 같은 OAuth App의
// 공개 client_id를 기본값으로 쓰고 (시크릿 불요), 환경변수로 오버라이드한다.
const (
	defaultClientID = "Ov23likpPsGK5U4sCxI5"
	oauthScope      = "read:user repo"
	deviceGrantType = "urn:ietf:params:oauth:grant-type:device_code"
)

// 테스트에서 httptest 서버로 바꿔치기할 수 있도록 변수로 둔다.
var (
	deviceCodeURL = "https://github.com/login/device/code"
	tokenURL      = "https://github.com/login/oauth/access_token"
	userURL       = "https://api.github.com/user"
	pollSleep     = time.Sleep
	timeNow       = time.Now
)

var httpClient = &http.Client{Timeout: 30 * time.Second}

func clientID() string {
	if v := os.Getenv("SIMSYNC_GITHUB_CLIENT_ID"); v != "" {
		return v
	}
	return defaultClientID
}

type deviceCodeResponse struct {
	DeviceCode      string `json:"device_code"`
	UserCode        string `json:"user_code"`
	VerificationURI string `json:"verification_uri"`
	ExpiresIn       int    `json:"expires_in"`
	Interval        int    `json:"interval"`
	Error           string `json:"error"`
}

type tokenResponse struct {
	AccessToken string `json:"access_token"`
	TokenType   string `json:"token_type"`
	Scope       string `json:"scope"`
	Error       string `json:"error"`
	Interval    int    `json:"interval"`
}

// postForm은 GitHub OAuth 엔드포인트에 form을 보낸다. Accept 헤더가 없으면
// GitHub이 form-encoded로 응답하므로 반드시 붙인다.
func postForm(endpoint string, form url.Values) (*http.Response, error) {
	req, err := http.NewRequest(
		http.MethodPost, endpoint, strings.NewReader(form.Encode()))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	return httpClient.Do(req)
}

// getUser는 /user를 호출한다. status 코드 판정은 호출자 몫 (로그인은 프로필,
// status 명령은 토큰 유효성 확인에 쓴다).
func getUser(accessToken string) (*http.Response, error) {
	req, err := http.NewRequest(http.MethodGet, userURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	return httpClient.Do(req)
}

func requestDeviceCode() (deviceCodeResponse, error) {
	var dc deviceCodeResponse
	resp, err := postForm(deviceCodeURL, url.Values{
		"client_id": {clientID()},
		"scope":     {oauthScope},
	})
	if err != nil {
		return dc, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return dc, fmt.Errorf("device code 요청이 실패했습니다 (HTTP %d)", resp.StatusCode)
	}
	if err := json.NewDecoder(resp.Body).Decode(&dc); err != nil {
		return dc, err
	}
	if dc.Error != "" {
		return dc, fmt.Errorf("device code 요청이 실패했습니다: %s", dc.Error)
	}
	return dc, nil
}

func clampInterval(seconds int) time.Duration {
	// GitHub 문서상 최소 5초 — 응답이 뭐라 하든 더 빠르게 폴링하지 않는다.
	if seconds < 5 {
		seconds = 5
	}
	if seconds > 60 {
		seconds = 60
	}
	return time.Duration(seconds) * time.Second
}

// pollForToken은 사용자가 github.com/login/device에서 승인할 때까지 토큰
// 엔드포인트를 폴링한다. 일시적 오류(네트워크, 5xx, 비JSON)는 스킵하고 계속
// 돈다 — device code 만료(expires_in)가 상한이다. (데스크톱과 같은 규칙)
func pollForToken(dc deviceCodeResponse) (tokenResponse, error) {
	interval := clampInterval(dc.Interval)
	deadline := timeNow().Add(time.Duration(dc.ExpiresIn) * time.Second)

	for {
		pollSleep(interval)
		if timeNow().After(deadline) {
			return tokenResponse{}, errors.New("승인 전에 코드가 만료되었습니다. 다시 시도하세요.")
		}

		resp, err := postForm(tokenURL, url.Values{
			"client_id":   {clientID()},
			"device_code": {dc.DeviceCode},
			"grant_type":  {deviceGrantType},
		})
		if err != nil {
			continue
		}
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			continue
		}
		var t tokenResponse
		if json.Unmarshal(body, &t) != nil {
			continue
		}

		switch t.Error {
		case "":
			if t.AccessToken == "" {
				continue // JSON이지만 토큰도 에러도 없음: 일시적 이상, 계속
			}
			if t.TokenType == "" {
				t.TokenType = "bearer"
			}
			return t, nil
		case "authorization_pending":
			continue
		case "slow_down":
			// 서버 지정 백오프: 명시 interval 또는 +5초.
			if t.Interval > 0 {
				interval = clampInterval(t.Interval)
			} else {
				interval += 5 * time.Second
			}
			continue
		case "expired_token":
			return tokenResponse{}, errors.New("승인 전에 코드가 만료되었습니다. 다시 시도하세요.")
		case "access_denied":
			return tokenResponse{}, errors.New("github.com에서 로그인이 거부되었습니다.")
		default:
			return tokenResponse{}, fmt.Errorf("토큰 폴링이 실패했습니다: %s", t.Error)
		}
	}
}

func fetchUser(accessToken string) (AuthUser, error) {
	var u AuthUser
	resp, err := getUser(accessToken)
	if err != nil {
		return u, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return u, fmt.Errorf("사용자 조회가 실패했습니다 (HTTP %d)", resp.StatusCode)
	}
	// GitHub의 id는 숫자 — 데스크톱 세션 포맷(문자열)에 맞춰 변환한다.
	var raw struct {
		ID        int64   `json:"id"`
		Login     string  `json:"login"`
		Name      *string `json:"name"`
		AvatarURL string  `json:"avatar_url"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&raw); err != nil {
		return u, err
	}
	return AuthUser{
		ID:        strconv.FormatInt(raw.ID, 10),
		Login:     raw.Login,
		Name:      raw.Name,
		AvatarURL: raw.AvatarURL,
	}, nil
}

// tokenState: status 명령의 라이브 토큰 검증 결과 (데스크톱
// validateAccessToken과 같은 3분류).
type tokenState int

const (
	tokenValid tokenState = iota
	tokenInvalid
	tokenUnknown
)

func validateToken(accessToken string) tokenState {
	resp, err := getUser(accessToken)
	if err != nil {
		return tokenUnknown
	}
	defer resp.Body.Close()
	io.Copy(io.Discard, resp.Body)
	switch resp.StatusCode {
	case http.StatusOK:
		return tokenValid
	case http.StatusUnauthorized, http.StatusForbidden:
		return tokenInvalid
	default:
		return tokenUnknown
	}
}

func cmdLogin() error {
	dc, err := requestDeviceCode()
	if err != nil {
		return err
	}
	fmt.Printf("브라우저에서 %s 를 열고 아래 코드를 입력하세요.\n\n", dc.VerificationURI)
	fmt.Printf("    일회용 코드: %s\n\n", dc.UserCode)
	fmt.Println("승인을 기다리는 중... (Ctrl+C로 취소)")

	token, err := pollForToken(dc)
	if err != nil {
		return err
	}
	user, err := fetchUser(token.AccessToken)
	if err != nil {
		return err
	}

	now := time.Now()
	session := &AuthSession{
		Provider:    "github",
		AccessToken: token.AccessToken,
		TokenType:   token.TokenType,
		Scope:       token.Scope,
		IssuedAt:    now,
		ExpiresAt:   now.Add(sessionMaxAge),
		User:        user,
	}
	if err := saveSession(session); err != nil {
		return err
	}
	fmt.Printf("\n로그인 완료: %s\n", user.Login)
	fmt.Printf("세션 만료: %s (%s 남음)\n",
		formatTime(session.ExpiresAt), formatDuration(sessionMaxAge))
	return nil
}

func cmdLogout() error {
	existed, err := clearSession()
	if err != nil {
		return err
	}
	if existed {
		fmt.Println("로그아웃했습니다. (세션 파일 삭제)")
	} else {
		fmt.Println("로그인되어 있지 않습니다.")
	}
	return nil
}
