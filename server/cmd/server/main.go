// Command server runs the New Me API server.
//
// Subcommands and flags:
//
//	server               run the API server and the day scheduler
//	server invite        print a fresh single-use invite code and exit
//	server -healthcheck  probe the local health endpoint and exit 0 or 1
package main

import (
	"context"
	"errors"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/nc1107/new-me/server/internal/anthropic"
	"github.com/nc1107/new-me/server/internal/api"
	"github.com/nc1107/new-me/server/internal/coach"
	"github.com/nc1107/new-me/server/internal/config"
	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/listening"
	"github.com/nc1107/new-me/server/internal/lookback"
	"github.com/nc1107/new-me/server/internal/milestone"
	"github.com/nc1107/new-me/server/internal/nudge"
	"github.com/nc1107/new-me/server/internal/push"
	"github.com/nc1107/new-me/server/internal/recap"
	"github.com/nc1107/new-me/server/internal/sched"
	"github.com/nc1107/new-me/server/internal/together"
)

// version is stamped at build time with -ldflags "-X main.version=1.2.3".
var version = "dev"

func main() {
	// The distroless image has no shell or curl, so the container probes itself.
	if len(os.Args) > 1 && os.Args[1] == "-healthcheck" {
		os.Exit(healthcheck())
	}

	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	database, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("database: %v", err)
	}
	defer database.Close()

	if len(os.Args) > 1 && os.Args[1] == "invite" {
		if err := runInvite(ctx, database, os.Stdout, os.Stderr); err != nil {
			log.Fatalf("invite: %v", err)
		}
		return
	}

	if err := database.Migrate(ctx); err != nil {
		log.Fatalf("migrate: %v", err)
	}
	if err := database.SeedServerName(ctx, cfg.ServerName); err != nil {
		log.Printf("seed server name: %v", err)
	}

	notifier := startPush(ctx, cfg, database)

	scheduler := sched.New(database)
	if cfg.ABSURL != "" {
		scheduler.Listening = listening.New(database, cfg.ABSURL)
	}
	scheduler.Together = &together.Service{DB: database, Now: time.Now, Notifier: notifier}
	var claude *anthropic.Client
	if cfg.Anthropic.Enabled() {
		claude = anthropic.New(cfg.Anthropic.Key, cfg.Anthropic.BaseURL)
	} else {
		log.Println("[NEWME] meal estimates and plan wording are off: NEWME_ANTHROPIC_API_KEY is not set")
	}
	scheduler.Nudges = &nudge.Service{DB: database, Together: scheduler.Together, Now: time.Now,
		Polisher: &coach.Polisher{DB: database, Client: claude}}
	scheduler.Recap = &recap.Service{DB: database, Together: scheduler.Together, Now: time.Now}
	scheduler.Lookback = &lookback.Service{DB: database, Together: scheduler.Together, Now: time.Now}
	scheduler.Milestones = &milestone.Service{DB: database, Together: scheduler.Together, Now: time.Now}
	go scheduler.Run(ctx)

	httpServer := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           api.New(cfg, database).WithVersion(version).WithNotifier(notifier).Router(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	go func() {
		log.Printf("[NEWME] server %s listening on %s", version, cfg.HTTPAddr)
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("listen: %v", err)
		}
	}()

	<-ctx.Done()
	log.Println("[NEWME] shutting down...")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = httpServer.Shutdown(shutdownCtx)
}

// startPush builds the APNs dispatcher, or returns nil when push is not configured. A bad key
// is logged and leaves push off, since the rest of the app does not depend on it.
func startPush(ctx context.Context, cfg config.Config, database *db.DB) together.Notifier {
	if !cfg.APNS.Enabled() {
		log.Println("[NEWME] push is off: NEWME_APNS_* is not set")
		return nil
	}
	key, err := push.ParseKey(cfg.APNS.Key)
	if err != nil {
		log.Printf("[NEWME] push is off: %v", err)
		return nil
	}
	client, err := push.NewClient(push.Config{Key: key, KeyID: cfg.APNS.KeyID, TeamID: cfg.APNS.TeamID,
		Topic: cfg.APNS.Topic, Sandbox: !cfg.APNS.Production})
	if err != nil {
		log.Printf("[NEWME] push is off: %v", err)
		return nil
	}
	log.Printf("[NEWME] push is on (production=%v)", cfg.APNS.Production)
	return push.NewDispatcher(ctx, client, push.DBStore{DB: database})
}

// healthcheck does one GET against the local health endpoint and returns the exit code.
func healthcheck() int {
	addr := os.Getenv("NEWME_HTTP_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	_, port, err := net.SplitHostPort(addr)
	if err != nil {
		return 1
	}
	client := http.Client{Timeout: 3 * time.Second}
	resp, err := client.Get("http://" + net.JoinHostPort("127.0.0.1", port) + "/api/health")
	if err != nil {
		return 1
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return 1
	}
	return 0
}
