// Package api wires the HTTP router and handlers.
package api

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"github.com/nc1107/new-me/server/internal/config"
	"github.com/nc1107/new-me/server/internal/db"
)

// Server holds the dependencies shared by every handler.
type Server struct {
	cfg config.Config
	db  *db.DB
}

// New builds a Server.
func New(cfg config.Config, database *db.DB) *Server {
	return &Server{cfg: cfg, db: database}
}

// Router builds the HTTP handler tree.
func (s *Server) Router() http.Handler {
	r := chi.NewRouter()
	// A hand-built Config leaves the hops at zero, which the middleware panics on.
	trustedHops := s.cfg.TrustedProxyHops
	if trustedHops < 1 {
		trustedHops = 1
	}
	r.Use(middleware.ClientIPFromXFFTrustedProxies(trustedHops))
	r.Use(middleware.Recoverer)
	r.Use(middleware.Timeout(30 * time.Second))
	r.Use(secureHeaders)
	r.Use(s.appKey)

	r.Get("/api/health", s.handleHealth)
	r.Get("/api/server-info", s.handleServerInfo)
	return r
}

func secureHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Referrer-Policy", "no-referrer")
		h.Set("Content-Security-Policy", "default-src 'none'")
		next.ServeHTTP(w, r)
	})
}

// appKey rejects any /api request lacking the shared key. Health is exempt so the
// container healthcheck, which has no key, keeps working.
func (s *Server) appKey(next http.Handler) http.Handler {
	// Hashing first makes the compare constant-time regardless of the supplied length.
	want := sha256.Sum256([]byte(s.cfg.AppKey))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodGet && r.URL.Path == "/api/health" {
			next.ServeHTTP(w, r)
			return
		}
		got := sha256.Sum256([]byte(r.Header.Get("X-App-Key")))
		if subtle.ConstantTimeCompare(got[:], want[:]) != 1 {
			writeErr(w, http.StatusUnauthorized, "missing or invalid app key")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := s.db.Pool.Ping(ctx); err != nil {
		writeErr(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

type serverInfoUser struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
}

func (s *Server) handleServerInfo(w http.ResponseWriter, r *http.Request) {
	info, err := s.db.GetServerInfo(r.Context())
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "could not read server info")
		return
	}
	writeJSON(w, http.StatusOK, struct {
		Name        string           `json:"name"`
		Initialized bool             `json:"initialized"`
		Users       []serverInfoUser `json:"users"`
	}{info.Name, info.Initialized, []serverInfoUser{}})
}
