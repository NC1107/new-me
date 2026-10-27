package api

import (
	"net/http"
	"testing"
)

func TestHealthOK(t *testing.T) {
	h := newHarness(t)
	h.get("/api/health", "", func(r *http.Request) { r.Header.Del("X-App-Key") }).
		expect(http.StatusOK)
}

func TestServerInfoRejectsMissingAppKey(t *testing.T) {
	h := newHarness(t)
	var got struct {
		Error string `json:"error"`
	}
	h.get("/api/server-info", "", func(r *http.Request) { r.Header.Del("X-App-Key") }).
		expect(http.StatusUnauthorized).decode(&got)
	if got.Error != "missing or invalid app key" {
		t.Fatalf("error = %q", got.Error)
	}
}

func TestServerInfoRejectsWrongAppKey(t *testing.T) {
	h := newHarness(t)
	h.get("/api/server-info", "", func(r *http.Request) { r.Header.Set("X-App-Key", "nope") }).
		expect(http.StatusUnauthorized)
}

func TestServerInfoUninitialized(t *testing.T) {
	h := newHarness(t)
	var got struct {
		Name        string `json:"name"`
		Initialized bool   `json:"initialized"`
		Users       []any  `json:"users"`
	}
	h.get("/api/server-info", "").expect(http.StatusOK).decode(&got)
	if got.Initialized {
		t.Fatal("a fresh server must report initialized=false")
	}
	if got.Name != testServerName {
		t.Fatalf("name = %q, want %q", got.Name, testServerName)
	}
	if got.Users == nil || len(got.Users) != 0 {
		t.Fatalf("users = %v, want empty non-null list", got.Users)
	}
}
