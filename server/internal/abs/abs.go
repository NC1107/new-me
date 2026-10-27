// Package abs is the small slice of the Audiobookshelf HTTP API New Me uses: sign in, refresh
// the session, and read per-day listening time. The request and response shapes were checked
// against Audiobookshelf v2.37.1 (see docs/design-v3.md).
package abs

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// ErrAuth means Audiobookshelf rejected the credentials or the refresh token. It is the one
// failure a retry cannot fix: the person has to sign in again.
var ErrAuth = errors.New("audiobookshelf rejected the credentials")

// ErrUnavailable covers everything else: network errors, rate limiting and server errors.
var ErrUnavailable = errors.New("audiobookshelf is unavailable")

// maxResponse bounds what is read from Audiobookshelf. The listening stats embed recent
// sessions, so a real response is far larger than a login, but still well under this.
const maxResponse = 8 << 20

// fallbackAccessLife applies when an access token carries no readable expiry. Audiobookshelf
// issues one-hour tokens by default.
const fallbackAccessLife = 50 * time.Minute

// Session is what stays signed in: the account it belongs to and both tokens.
type Session struct {
	UserID        string
	Username      string
	AccessToken   string
	RefreshToken  string
	AccessExpires time.Time
}

// Client talks to one Audiobookshelf server.
type Client struct {
	base string
	http *http.Client
	now  func() time.Time
}

// New builds a client for a base URL such as https://books.example.com.
func New(baseURL string) *Client {
	return &Client{
		base: strings.TrimRight(baseURL, "/"),
		http: &http.Client{Timeout: 15 * time.Second},
		now:  time.Now,
	}
}

type authResponse struct {
	User struct {
		ID           string `json:"id"`
		Username     string `json:"username"`
		AccessToken  string `json:"accessToken"`
		RefreshToken string `json:"refreshToken"`
	} `json:"user"`
}

// Login signs in with a password. The x-return-tokens header makes Audiobookshelf put the
// refresh token in the body instead of a cookie.
func (c *Client) Login(ctx context.Context, username, password string) (Session, error) {
	body, _ := json.Marshal(map[string]string{"username": username, "password": password})
	return c.sessionFrom(ctx, "/login", body, map[string]string{"x-return-tokens": "true"}, "")
}

// Refresh trades the refresh token for a new session. Audiobookshelf rotates the refresh
// token, so the returned one replaces the old; the old stays valid for a short grace window.
func (c *Client) Refresh(ctx context.Context, s Session) (Session, error) {
	return c.sessionFrom(ctx, "/auth/refresh", nil, map[string]string{"x-refresh-token": s.RefreshToken}, s.Username)
}

func (c *Client) sessionFrom(ctx context.Context, path string, body []byte, headers map[string]string, fallbackName string) (Session, error) {
	var out authResponse
	if err := c.do(ctx, http.MethodPost, path, body, "", headers, &out); err != nil {
		return Session{}, err
	}
	u := out.User
	if u.ID == "" || u.AccessToken == "" || u.RefreshToken == "" {
		return Session{}, fmt.Errorf("%w: sign-in response lacks tokens", ErrUnavailable)
	}
	name := u.Username
	if name == "" {
		name = fallbackName
	}
	return Session{
		UserID: u.ID, Username: name, AccessToken: u.AccessToken, RefreshToken: u.RefreshToken,
		AccessExpires: c.accessExpiry(u.AccessToken),
	}, nil
}

// accessExpiry reads the exp claim of the JWT without verifying it, which is fine because it
// only schedules a refresh. A 401 on use triggers one anyway.
func (c *Client) accessExpiry(token string) time.Time {
	parts := strings.Split(token, ".")
	if len(parts) == 3 {
		if raw, err := base64.RawURLEncoding.DecodeString(parts[1]); err == nil {
			var claims struct {
				Exp int64 `json:"exp"`
			}
			if json.Unmarshal(raw, &claims) == nil && claims.Exp > 0 {
				return time.Unix(claims.Exp, 0)
			}
		}
	}
	return c.now().Add(fallbackAccessLife)
}

// ListeningSession is one playback session from GET /api/me/listening-sessions. StartedAt and
// UpdatedAt are the session row's creation and last update (milliseconds since the epoch on the
// wire) and Seconds is the time actually listened.
type ListeningSession struct {
	StartedAt time.Time
	UpdatedAt time.Time
	Seconds   float64
}

const (
	sessionsPerPage = 50
	// maxSessionPages bounds one poll if the server keeps answering sessions newer than since.
	maxSessionPages = 40
)

// ListeningSessions returns the sessions updated at or after since, newest first. Audiobookshelf
// lists a user's sessions by last update, newest first, so paging stops at the first page that
// reaches back past since.
func (c *Client) ListeningSessions(ctx context.Context, accessToken string, since time.Time) ([]ListeningSession, error) {
	var out []ListeningSession
	for page := 0; page < maxSessionPages; page++ {
		var body struct {
			NumPages int `json:"numPages"`
			Sessions []struct {
				StartedAt     int64   `json:"startedAt"`
				UpdatedAt     int64   `json:"updatedAt"`
				TimeListening float64 `json:"timeListening"`
			} `json:"sessions"`
		}
		path := fmt.Sprintf("/api/me/listening-sessions?itemsPerPage=%d&page=%d", sessionsPerPage, page)
		if err := c.do(ctx, http.MethodGet, path, nil, accessToken, nil, &body); err != nil {
			return nil, err
		}
		reachedBack := false
		for _, s := range body.Sessions {
			updated := time.UnixMilli(s.UpdatedAt)
			if updated.Before(since) {
				reachedBack = true
				continue
			}
			started := time.UnixMilli(s.StartedAt)
			if s.StartedAt == 0 {
				started = updated
			}
			out = append(out, ListeningSession{StartedAt: started, UpdatedAt: updated, Seconds: s.TimeListening})
		}
		if reachedBack || page+1 >= body.NumPages {
			break
		}
	}
	return out, nil
}

func (c *Client) do(ctx context.Context, method, path string, body []byte, bearer string, headers map[string]string, out any) error {
	req, err := http.NewRequestWithContext(ctx, method, c.base+path, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("%w: %v", ErrUnavailable, err)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if bearer != "" {
		req.Header.Set("Authorization", "Bearer "+bearer)
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("%w: %v", ErrUnavailable, err)
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, maxResponse))
	if err != nil {
		return fmt.Errorf("%w: %v", ErrUnavailable, err)
	}
	switch {
	case resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden:
		return ErrAuth
	case resp.StatusCode != http.StatusOK:
		return fmt.Errorf("%w: %s %s answered %d", ErrUnavailable, method, path, resp.StatusCode)
	}
	if err := json.Unmarshal(raw, out); err != nil {
		return fmt.Errorf("%w: unreadable %s response", ErrUnavailable, path)
	}
	return nil
}
