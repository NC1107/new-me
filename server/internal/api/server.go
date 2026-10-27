// Package api wires the HTTP router and handlers.
package api

import (
	"context"
	"net/http"
	"sync"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"github.com/nc1107/new-me/server/internal/config"
	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/listening"
	"github.com/nc1107/new-me/server/internal/ratelimit"
	"github.com/nc1107/new-me/server/internal/semver"
)

// defaultMaxUsers applies to a hand-built Config, which leaves the cap at zero.
const defaultMaxUsers = 2

// limits are the per-key request budgets. Each is sized to stop automation, not people.
type limits struct {
	// join covers the unauthenticated pairing routes, per client IP.
	join *ratelimit.Limiter
	// device covers every authenticated route, per device.
	device *ratelimit.Limiter
	// healthPut is the extra budget of PUT /health/daily, per device.
	healthPut *ratelimit.Limiter
	// absLink caps sign-in attempts, per device, so the endpoint cannot be used to guess
	// Audiobookshelf passwords.
	absLink *ratelimit.Limiter
}

func newLimits() limits {
	return limits{
		join:      ratelimit.New(5, 5),
		device:    ratelimit.New(120, 60),
		healthPut: ratelimit.New(30, 10),
		absLink:   ratelimit.New(5, 5),
	}
}

// Server holds the dependencies shared by every handler.
type Server struct {
	cfg       config.Config
	db        *db.DB
	version   string
	now       func() time.Time
	limits    limits
	minClient semver.Version
	health    healthCache
	// listen is nil while NEWME_ABS_URL is unset, which is how the feature is off.
	listen *listening.Syncer
}

// New builds a Server on the wall clock.
func New(cfg config.Config, database *db.DB) *Server {
	if cfg.MaxUsers < 1 {
		cfg.MaxUsers = defaultMaxUsers
	}
	if cfg.MinClientVersion == "" {
		cfg.MinClientVersion = "0.0.0"
	}
	// Load has validated the value; a hand-built Config falls back to accepting everything.
	minClient, _ := semver.Parse(cfg.MinClientVersion)
	var syncer *listening.Syncer
	if cfg.ABSURL != "" {
		syncer = listening.New(database, cfg.ABSURL)
	}
	return &Server{
		listen:    syncer,
		cfg:       cfg,
		db:        database,
		version:   "dev",
		now:       time.Now,
		limits:    newLimits(),
		minClient: minClient,
	}
}

// WithVersion sets the build version reported by /api/health.
func (s *Server) WithVersion(version string) *Server {
	s.version = version
	return s
}

// WithClock replaces the clock handlers read, so tests can place a request at a chosen moment.
func (s *Server) WithClock(now func() time.Time) *Server {
	s.now = now
	if s.listen != nil {
		s.listen.Now = now
	}
	return s
}

// Router builds the HTTP handler tree.
func (s *Server) Router() http.Handler {
	r := chi.NewRouter()
	// A hand-built Config leaves the hops at zero, which the middleware panics on.
	trustedHops := max(s.cfg.TrustedProxyHops, 1)

	r.Use(recoverer)
	r.Use(middleware.ClientIPFromXFFTrustedProxies(trustedHops))
	r.Use(requestID)
	r.Use(middleware.Timeout(requestTimeout))
	r.Use(limitBody)
	r.Use(secureHeaders)
	if s.cfg.DevCORS {
		r.Use(devCORS)
	}
	r.Use(s.appKey)
	r.Use(s.clientVersion)

	r.NotFound(func(w http.ResponseWriter, _ *http.Request) {
		writeErr(w, http.StatusNotFound, codeNotFound, "no such endpoint")
	})
	r.MethodNotAllowed(func(w http.ResponseWriter, _ *http.Request) {
		writeErr(w, http.StatusMethodNotAllowed, codeMethodNotAllowed, "method not allowed")
	})

	r.Get("/api/health", s.handleHealth)
	r.Get("/api/server-info", s.handleServerInfo)

	r.Group(func(r chi.Router) {
		r.Use(limit(s.limits.join, byClientIP))
		r.Post("/api/join", s.handleJoin)
		r.Post("/api/invites/check", s.handleCheckInvite)
	})

	r.Group(func(r chi.Router) {
		r.Use(s.requireAuth)
		r.Use(limit(s.limits.device, byDevice))

		r.Delete("/api/devices/me", s.handleDeleteDevice)
		r.Get("/api/me", s.handleGetMe)
		r.Patch("/api/me", s.handlePatchMe)
		r.Get("/api/today", s.handleToday)
		r.Get("/api/board", s.handleBoard)
		r.Post("/api/logs", s.handleCreateLog)
		r.Get("/api/logs", s.handleListLogs)
		r.Delete("/api/logs/{id}", s.handleDeleteLog)
		r.Get("/api/meals/recent", s.handleRecentMeals)
		r.With(limit(s.limits.healthPut, byDevice)).Put("/api/health/daily", s.handlePutHealthDaily)
		r.Get("/api/health/trends", s.handleHealthTrends)
		r.With(limit(s.limits.absLink, byDevice)).Put("/api/me/audiobookshelf", s.handleLinkAudiobookshelf)
		r.Delete("/api/me/audiobookshelf", s.handleUnlinkAudiobookshelf)

		r.Group(func(r chi.Router) {
			r.Use(requireAdmin)
			r.Post("/api/invites", s.handleCreateInvite)
		})
	})
	return r
}

// healthTTL is how long a database ping is reused, so a probe loop cannot hammer the pool.
const healthTTL = 5 * time.Second

// healthCache remembers the last database ping.
type healthCache struct {
	mu      sync.Mutex
	checked time.Time
	err     error
}

func (h *healthCache) ping(r *http.Request, database *db.DB) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	if !h.checked.IsZero() && time.Since(h.checked) < healthTTL {
		return h.err
	}
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	h.err = database.Pool.Ping(ctx)
	h.checked = time.Now()
	return h.err
}
