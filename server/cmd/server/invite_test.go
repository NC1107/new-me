package main

import (
	"bytes"
	"context"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/nc1107/new-me/server/internal/auth"
	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/dbtest"
)

func TestMain(m *testing.M) {
	dbtest.Require()
	os.Exit(m.Run())
}

func TestRunInviteStoresASingleUseCodeAndPrintsOnlyTheCode(t *testing.T) {
	database := dbtest.Fresh(t)
	var stdout, stderr bytes.Buffer
	if err := runInvite(context.Background(), database, &stdout, &stderr); err != nil {
		t.Fatal(err)
	}

	code := strings.TrimSpace(stdout.String())
	if auth.NormalizeInviteCode(code) == "" || strings.Count(stdout.String(), "\n") != 1 {
		t.Fatalf("stdout = %q, want exactly one invite code", stdout.String())
	}
	if !strings.Contains(stderr.String(), "single use") {
		t.Fatalf("stderr = %q", stderr.String())
	}

	ctx := context.Background()
	if err := db.CheckInvite(ctx, database.Pool, auth.HashInviteCode(code)); err != nil {
		t.Fatalf("the printed code is not redeemable: %v", err)
	}
	if err := db.ConsumeInvite(ctx, database.Pool, auth.HashInviteCode(code)); err != nil {
		t.Fatal(err)
	}
	if err := db.CheckInvite(ctx, database.Pool, auth.HashInviteCode(code)); err == nil {
		t.Fatal("a code must be single use")
	}
	var createdBy *int64
	if err := database.Pool.QueryRow(ctx, `SELECT created_by FROM invites`).Scan(&createdBy); err != nil || createdBy != nil {
		t.Fatalf("a CLI code has no creator: %v, %v", createdBy, err)
	}
}

func TestHealthcheckProbesTheConfiguredPort(t *testing.T) {
	status := http.StatusOK
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/health" {
			status = http.StatusNotFound
		}
		w.WriteHeader(status)
	}))
	defer ts.Close()
	_, port, _ := net.SplitHostPort(strings.TrimPrefix(ts.URL, "http://"))

	t.Setenv("NEWME_HTTP_ADDR", ":"+port)
	if got := healthcheck(); got != 0 {
		t.Fatalf("healthcheck = %d against a healthy server", got)
	}
	status = http.StatusServiceUnavailable
	if got := healthcheck(); got != 1 {
		t.Fatalf("healthcheck = %d against an unhealthy server", got)
	}
	ts.Close()
	if got := healthcheck(); got != 1 {
		t.Fatalf("healthcheck = %d with nothing listening", got)
	}
}
