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

func TestListeningSecondsReadsTheDaysMap(t *testing.T) {
	fake := abstest.New(t, func() time.Time { return now })
	fake.AddUser("nick", "pw")
	fake.SetListening("nick", "2026-11-02", 90)
	c := abs.New(fake.URL)
	sess, _ := c.Login(context.Background(), "nick", "pw")

	days, err := c.ListeningSeconds(context.Background(), sess.AccessToken)
	if err != nil || days["2026-11-02"] != 90 {
		t.Fatalf("days = %v, %v", days, err)
	}
	if _, err := c.ListeningSeconds(context.Background(), "bad"); !errors.Is(err, abs.ErrAuth) {
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
