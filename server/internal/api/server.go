// Package api wires the HTTP router and handlers.
package api

import (
	"context"
	"net/http"
	"sync"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"github.com/nc1107/new-me/server/internal/anthropic"
	"github.com/nc1107/new-me/server/internal/coach"
	"github.com/nc1107/new-me/server/internal/config"
	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/estimate"
	"github.com/nc1107/new-me/server/internal/listening"
	"github.com/nc1107/new-me/server/internal/lookback"
	"github.com/nc1107/new-me/server/internal/milestone"
	"github.com/nc1107/new-me/server/internal/planner"
	"github.com/nc1107/new-me/server/internal/ratelimit"
	"github.com/nc1107/new-me/server/internal/recap"
	"github.com/nc1107/new-me/server/internal/semver"
	"github.com/nc1107/new-me/server/internal/together"
)

// defaultMaxUsers applies to a hand-built Config, which leaves the cap at zero.
const defaultMaxUsers = 2

// limits are the per-key request budgets. Each is sized to stop automation, not people.
type limits struct {
	// join covers the unauthenticated pairing routes, per client IP.
	join *ratelimit.Limiter
	// device covers every authenticated route, per device.
	device *ratelimit.Limiter
	// healthPut is the extra budget of the PUT /health/* routes, per device.
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
	// together is the shared challenge, reward and push logic.
	together *together.Service
	// absSync throttles the manual Audiobookshelf sync per person.
	absSync throttle
	// estimator is nil while NEWME_ANTHROPIC_API_KEY is unset, which is how meal estimates are off.
	estimator *estimate.Estimator
	// foods searches USDA and Open Food Facts; it works without a Claude key.
	foods *estimate.Foods
	// polisher is always usable; without a key it returns the deterministic summary.
	polisher *coach.Polisher
	// estimates caps meal estimates per person, since each one costs a Claude call.
	estimates *ratelimit.Window
	// planner is nil while NEWME_ANTHROPIC_API_KEY is unset, which turns plan design off.
	planner *planner.Planner
	// plans caps plan designs and changes per person.
	plans *ratelimit.Window
	recap *recap.Service
	// milestones records and announces streak milestones and firsts.
	milestones *milestone.Service
	lookback   *lookback.Service
}

// estimatesPerHour is how many meal estimates one person may request an hour.
const estimatesPerHour = 20

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
	srv := &Server{
		listen:    syncer,
		cfg:       cfg,
		db:        database,
		version:   "dev",
		now:       time.Now,
		limits:    newLimits(),
		minClient: minClient,
	}
	srv.foods = estimate.NewFoods(cfg.USDAKey, srv.version)
	var claude *anthropic.Client
	if cfg.Anthropic.Enabled() {
		claude = anthropic.New(cfg.Anthropic.Key, cfg.Anthropic.BaseURL)
		srv.estimator = &estimate.Estimator{Client: claude, Foods: srv.foods, Library: libraryStore{database}}
		srv.planner = &planner.Planner{Client: claude}
	}
	srv.polisher = &coach.Polisher{DB: database, Client: claude, Now: func() time.Time { return srv.now() }}
	srv.estimates = ratelimit.NewWindow(estimatesPerHour, time.Hour)
	srv.plans = ratelimit.NewWindow(plansPerDay, 24*time.Hour)
	srv.together = &together.Service{DB: database, Now: func() time.Time { return srv.now() }}
	srv.milestones = &milestone.Service{DB: database, Together: srv.together, Now: func() time.Time { return srv.now() }}
	srv.lookback = &lookback.Service{DB: database, Together: srv.together, Now: func() time.Time { return srv.now() }}
	srv.recap = &recap.Service{DB: database, Together: srv.together, Now: func() time.Time { return srv.now() }}
	return srv
}

// WithNotifier turns push on by giving the server somewhere to queue notifications. Without
// one, every push event is skipped and the rest of the app behaves the same.
func (s *Server) WithNotifier(n together.Notifier) *Server {
	s.together.Notifier = n
	return s
}

// WithVersion sets the build version reported by /api/health.
func (s *Server) WithVersion(version string) *Server {
	s.version = version
	s.foods.SetVersion(version)
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
		r.With(s.settleAfter).Post("/api/logs", s.handleCreateLog)
		r.Get("/api/logs", s.handleListLogs)
		r.With(s.settleAfter).Delete("/api/logs/{id}", s.handleDeleteLog)
		r.Get("/api/meals/recent", s.handleRecentMeals)
		r.With(limit(s.limits.healthPut, byDevice), s.settleAfter).Put("/api/health/daily", s.handlePutHealthDaily)
		r.Get("/api/health/trends", s.handleHealthTrends)
		r.With(limit(s.limits.healthPut, byDevice), s.settleAfter).Put("/api/health/workouts", s.handlePutWorkouts)
		r.With(limit(s.limits.healthPut, byDevice), s.settleAfter).Put("/api/health/sleep", s.handlePutSleep)
		r.With(limit(s.limits.healthPut, byDevice)).Put("/api/health/history", s.handlePutHealthHistory)
		r.Get("/api/workouts", s.handleListWorkouts)
		r.Get("/api/insights", s.handleInsights)
		r.Get("/api/targets", s.handleGetTargets)
		r.Post("/api/targets/apply", s.handleApplyTargets)
		r.Post("/api/pushups/max", s.handleRecordPushupMax)
		r.Get("/api/exercises", s.handleListExercises)
		r.Post("/api/exercises", s.handleCreateExercise)
		r.Patch("/api/exercises/{key}", s.handlePatchExercise)
		r.Delete("/api/exercises/{key}", s.handleDeleteExercise)
		r.Post("/api/exercises/{key}/max", s.handleRecordMaxTest)
		r.Get("/api/exercises/{key}/images/{n}", s.handleExerciseImage)
		r.With(s.settleAfter).Post("/api/sets", s.handleCreateSet)
		r.Get("/api/sets", s.handleListSets)
		r.With(s.settleAfter).Delete("/api/sets/{id}", s.handleDeleteSet)
		r.Get("/api/training/profile", s.handleGetTrainingProfile)
		r.Put("/api/training/profile", s.handlePutTrainingProfile)
		r.Get("/api/training/plan", s.handleGetPlan)
		r.Post("/api/training/plan", s.handleGeneratePlan)
		r.Post("/api/training/plan/change", s.handleChangePlan)
		r.Delete("/api/training/plan", s.handleDeletePlan)
		r.Get("/api/training/today", s.handleTrainingToday)
		r.Post("/api/training/today/full", s.handleTakeFullSession)
		r.With(s.settleAfter).Post("/api/training/sessions/{id}/complete", s.handleCompleteSession)
		r.Get("/api/training/progress", s.handleTrainingProgress)
		r.Get("/api/training/history", s.handleTrainingHistory)
		r.Get("/api/exercises/{key}/history", s.handleExerciseHistory)
		r.With(limit(s.limits.absLink, byDevice)).Put("/api/me/audiobookshelf", s.handleLinkAudiobookshelf)
		r.Delete("/api/me/audiobookshelf", s.handleUnlinkAudiobookshelf)
		r.Post("/api/me/audiobookshelf/sync", s.handleSyncAudiobookshelf)
		r.Post("/api/meals/estimate", s.handleEstimateMeal)
		r.Get("/api/foods", s.handleListFoods)
		r.Get("/api/foods/barcode/{code}", s.handleFoodByBarcode)
		r.Post("/api/foods", s.handleCreateFood)
		r.Patch("/api/foods/{id}", s.handlePatchFood)
		r.Delete("/api/foods/{id}", s.handleDeleteFood)
		r.Post("/api/foods/{id}/use", s.handleUseFood)
		r.Get("/api/recap", s.handleRecap)
		r.Get("/api/progress", s.handleProgress)
		r.Get("/api/lookback", s.handleLookback)
		r.Get("/api/milestones", s.handleListMilestones)
		r.Post("/api/away", s.handleCreateAway)
		r.Delete("/api/away/{id}", s.handleDeleteAway)
		r.Post("/api/streak/cover", s.handleCoverStreak)
		r.Get("/api/goals/proposals", s.handleGoalProposals)
		r.Post("/api/goals/proposals/{key}/accept", s.handleAcceptProposal)
		r.Post("/api/goals/proposals/{key}/dismiss", s.handleDismissProposal)

		r.Get("/api/habits", s.handleListHabits)
		r.Post("/api/habits", s.handleCreateHabit)
		r.Put("/api/habits/order", s.handleOrderHabits)
		r.Patch("/api/habits/{id}", s.handlePatchHabit)
		r.Delete("/api/habits/{id}", s.handleDeleteHabit)
		r.Get("/api/habits/proposals", s.handleHabitProposals)
		r.Post("/api/habits/{id}/approve", s.handleApproveHabit)
		r.Post("/api/habits/{id}/decline", s.handleDeclineHabit)
		r.With(s.settleAfter).Put("/api/habits/{id}/marks/{date}", s.handlePutHabitMark)

		r.Post("/api/cheers", s.handleCreateCheer)
		r.Get("/api/rewards", s.handleListRewards)
		r.With(s.settleAfter).Post("/api/rewards", s.handleCreateReward)
		r.Patch("/api/rewards/{id}", s.handlePatchReward)
		r.Delete("/api/rewards/{id}", s.handleWithdrawReward)
		r.Post("/api/rewards/{id}/approve", s.handleApproveReward)
		r.Post("/api/rewards/{id}/decline", s.handleDeclineReward)
		r.Post("/api/rewards/{id}/cancel", s.handleCancelReward)
		r.Post("/api/rewards/{id}/focus", s.handleFocusReward)
		r.With(s.settleAfter).Post("/api/rewards/{id}/claim", s.handleClaimReward)
		r.Put("/api/devices/me/push", s.handlePutPushToken)
		r.Delete("/api/devices/me/push", s.handleDeletePushToken)

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
