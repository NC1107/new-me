package abs_test

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/abs"
	"github.com/nc1107/new-me/server/internal/abs/abstest"
)

var now = time.Date(2026, 11, 2, 12, 0, 0, 0, time.UTC)

func TestLoginReadsTheTokensAndTheAccessExpiryFromTheJWT(t *testing.T) {
	fake := abstest.New(t, func() time.Time { return now })
	fake.AddUser("nick", "pw")
	c := abs.New(fake.URL + "/")

	sess, err := c.Login(context.Background(), "nick", "pw")
	if err != nil {
		t.Fatal(err)
	}
	if sess.Username != "nick" || sess.UserID == "" || sess.RefreshToken == "" || sess.AccessToken == "" {
		t.Fatalf("session = %+v", sess)
	}
	if !sess.AccessExpires.Equal(now.Add(time.Hour)) {
		t.Fatalf("expiry = %v, want the exp claim", sess.AccessExpires)
	}
}

func TestRefreshRotatesTheRefreshToken(t *testing.T) {
	fake := abstest.New(t, func() time.Time { return now })
	fake.AddUser("nick", "pw")
	c := abs.New(fake.URL)
	first, _ := c.Login(context.Background(), "nick", "pw")

	next, err := c.Refresh(context.Background(), first)
	if err != nil || next.RefreshToken == first.RefreshToken || next.UserID != first.UserID {
		t.Fatalf("refresh = %+v, %v", next, err)
	}
	if _, err := c.Refresh(context.Background(), first); !errors.Is(err, abs.ErrAuth) {
		t.Fatalf("the rotated-out token must be rejected, got %v", err)
	}
}

func TestListeningSessionsPagesUntilItReachesBackPastSince(t *testing.T) {
	fake := abstest.New(t, func() time.Time { return now })
	fake.AddUser("nick", "pw")
	// 120 sessions an hour apart, newest first by update: three pages of 50.
	for i := 0; i < 120; i++ {
		at := now.Add(-time.Duration(i) * time.Hour)
		fake.AddSession("nick", at, at, 60)
	}
	c := abs.New(fake.URL)
	sess, _ := c.Login(context.Background(), "nick", "pw")

	got, err := c.ListeningSessions(context.Background(), sess.AccessToken, now.Add(-60*time.Hour))
	if err != nil || len(got) != 61 {
		t.Fatalf("sessions = %d, %v; want the 61 within 60 hours", len(got), err)
	}
	if _, _, stats := fake.Counts(); stats != 2 {
		t.Fatalf("requests = %d, want 2 pages", stats)
	}
	all, err := c.ListeningSessions(context.Background(), sess.AccessToken, time.Time{})
	if err != nil || len(all) != 120 {
		t.Fatalf("all = %d, %v", len(all), err)
	}
	if _, err := c.ListeningSessions(context.Background(), "bad", time.Time{}); !errors.Is(err, abs.ErrAuth) {
		t.Fatalf("err = %v, want ErrAuth", err)
	}
}

func TestFailuresAreClassified(t *testing.T) {
	for status, want := range map[int]error{
		http.StatusUnauthorized: abs.ErrAuth, http.StatusTooManyRequests: abs.ErrUnavailable,
		http.StatusInternalServerError: abs.ErrUnavailable,
	} {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(status) }))
		_, err := abs.New(srv.URL).Login(context.Background(), "a", "b")
		srv.Close()
		if !errors.Is(err, want) {
			t.Errorf("status %d: err = %v, want %v", status, err, want)
		}
	}
	if _, err := abs.New("http://127.0.0.1:1").Login(context.Background(), "a", "b"); !errors.Is(err, abs.ErrUnavailable) {
		t.Errorf("connection refused: err = %v", err)
	}
}

func TestAnOpaqueAccessTokenFallsBackToAShortLife(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"user":{"id":"u","username":"n","accessToken":"opaque","refreshToken":"r"}}`))
	}))
	defer srv.Close()
	before := time.Now()
	sess, err := abs.New(srv.URL).Login(context.Background(), "n", "p")
	if err != nil || !sess.AccessExpires.After(before) || sess.AccessExpires.After(before.Add(time.Hour)) {
		t.Fatalf("session = %+v, %v", sess, err)
	}
}
