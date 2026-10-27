// Package abstest is a fake Audiobookshelf server for tests. Its routes, headers and JSON
// shapes mirror Audiobookshelf v2.37.1: POST /login (tokens in the body when x-return-tokens is
// true), POST /auth/refresh (refresh token in x-refresh-token, rotated on every use) and
// GET /api/me/listening-stats (seconds per YYYY-MM-DD under "days").
package abstest

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

// Fake is a running fake server. Its zero-config behaviour is a healthy Audiobookshelf with
// one-hour access tokens.
type Fake struct {
	*httptest.Server

	mu         sync.Mutex
	now        func() time.Time
	accessLife time.Duration
	accounts   map[string]*account // by username
	byRefresh  map[string]*account
	seq        int

	// Logins, Refreshes and Stats count the calls that reached each route.
	Logins, Refreshes, Stats int
	// LoginHeaders keeps the headers of the last login, to check the client asked for tokens.
	LoginHeaders http.Header
	down         bool
}

type account struct {
	id, username, password string
	refresh                string
	access                 string
	accessExp              time.Time
	days                   map[string]float64
	revoked                bool
}

// New starts a fake. now supplies the clock that token expiry follows.
func New(t testing.TB, now func() time.Time) *Fake {
	t.Helper()
	f := &Fake{
		now: now, accessLife: time.Hour,
		accounts: map[string]*account{}, byRefresh: map[string]*account{},
	}
	mux := http.NewServeMux()
	mux.HandleFunc("POST /login", f.login)
	mux.HandleFunc("POST /auth/refresh", f.refresh)
	mux.HandleFunc("GET /api/me/listening-stats", f.stats)
	f.Server = httptest.NewServer(f.guard(mux))
	t.Cleanup(f.Close)
	return f
}

// AddUser registers an account that can sign in.
func (f *Fake) AddUser(username, password string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.seq++
	f.accounts[username] = &account{id: fmt.Sprintf("abs-user-%d", f.seq), username: username, password: password,
		days: map[string]float64{}}
}

// SetListening sets the seconds listened on a date for the account.
func (f *Fake) SetListening(username, date string, seconds float64) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.accounts[username].days[date] = seconds
}

// SetAccessLife changes how long newly issued access tokens last.
func (f *Fake) SetAccessLife(d time.Duration) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.accessLife = d
}

// Revoke ends the account's session, so its tokens stop working and refreshing it fails.
func (f *Fake) Revoke(username string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.accounts[username].revoked = true
}

// ExpireAccessToken makes the issued access token invalid while the session stays alive.
func (f *Fake) ExpireAccessToken(username string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.accounts[username].accessExp = f.now().Add(-time.Minute)
}

// SetDown makes every request fail with a 503, like a server that is restarting.
func (f *Fake) SetDown(down bool) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.down = down
}

// Counts returns the call counters under the lock.
func (f *Fake) Counts() (logins, refreshes, stats int) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.Logins, f.Refreshes, f.Stats
}

func (f *Fake) guard(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		down := f.down
		f.mu.Unlock()
		if down {
			http.Error(w, "restarting", http.StatusServiceUnavailable)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// issue rotates the account's tokens. Callers hold the lock.
func (f *Fake) issue(a *account) {
	f.seq++
	delete(f.byRefresh, a.refresh)
	a.refresh = fmt.Sprintf("refresh-%d", f.seq)
	a.accessExp = f.now().Add(f.accessLife)
	a.access = jwt(a.id, a.accessExp)
	f.byRefresh[a.refresh] = a
}

func jwt(userID string, exp time.Time) string {
	enc := base64.RawURLEncoding.EncodeToString
	payload, _ := json.Marshal(map[string]any{"userId": userID, "type": "access", "exp": exp.Unix()})
	return enc([]byte(`{"alg":"HS256","typ":"JWT"}`)) + "." + enc(payload) + ".sig"
}

func (f *Fake) respond(w http.ResponseWriter, a *account, withRefresh bool) {
	user := map[string]any{"id": a.id, "username": a.username, "type": "user", "accessToken": a.access,
		"refreshToken": nil}
	if withRefresh {
		user["refreshToken"] = a.refresh
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"user": user, "userDefaultLibraryId": "lib-1"})
}

func (f *Fake) login(w http.ResponseWriter, r *http.Request) {
	var body struct{ Username, Password string }
	_ = json.NewDecoder(r.Body).Decode(&body)
	f.mu.Lock()
	defer f.mu.Unlock()
	f.Logins++
	f.LoginHeaders = r.Header.Clone()
	a := f.accounts[body.Username]
	if a == nil || a.password != body.Password {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	a.revoked = false
	f.issue(a)
	f.respond(w, a, r.Header.Get("x-return-tokens") == "true")
}

func (f *Fake) refresh(w http.ResponseWriter, r *http.Request) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.Refreshes++
	token := r.Header.Get("x-refresh-token")
	a := f.byRefresh[token]
	if token == "" || a == nil || a.revoked {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(`{"error":"Invalid refresh token"}`))
		return
	}
	f.issue(a)
	f.respond(w, a, true)
}

func (f *Fake) stats(w http.ResponseWriter, r *http.Request) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.Stats++
	token := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
	var a *account
	for _, c := range f.accounts {
		if c.access == token && token != "" {
			a = c
		}
	}
	if a == nil || a.revoked || !a.accessExp.After(f.now()) {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	total := 0.0
	for _, s := range a.days {
		total += s
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"totalTime": total, "items": map[string]any{}, "days": a.days, "dayOfWeek": map[string]any{},
		"today": 0, "recentSessions": []any{},
	})
}
