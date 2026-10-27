package config

import (
	"fmt"
	"os"
	"strconv"
	"time"
)

// minAppKeyLen keeps the shared app key from being a guessable word.
const minAppKeyLen = 16

// Config holds all runtime configuration, sourced from environment variables so the
// server stays a single self-contained binary that is easy to run under Docker.
type Config struct {
	// HTTPAddr is the address the API server listens on, e.g. ":8080".
	HTTPAddr string
	// DatabaseURL is the PostgreSQL connection string (pgx format).
	DatabaseURL string
	// AppKey is the shared secret every /api request must carry in X-App-Key.
	AppKey string
	// ServerName is a human-friendly name surfaced to clients via /api/server-info.
	ServerName string
	// TrustedProxyHops is how many reverse proxies sit directly in front of this server.
	// The client IP is read from the X-Forwarded-For chain at that exact position, so a
	// caller cannot forge it; the default is one (Traefik).
	TrustedProxyHops int
	// SeasonStart optionally overrides when the first season begins. Zero means unset.
	SeasonStart time.Time
}

// Load reads configuration from the environment.
func Load() (Config, error) {
	cfg := Config{
		HTTPAddr: getenv("NEWME_HTTP_ADDR", ":8080"),
		// No default: a credential baked into the binary is a credential in source control.
		DatabaseURL:      os.Getenv("NEWME_DATABASE_URL"),
		AppKey:           os.Getenv("NEWME_APP_KEY"),
		ServerName:       getenv("NEWME_SERVER_NAME", "New Me"),
		TrustedProxyHops: getPositiveInt("NEWME_TRUSTED_PROXY_HOPS", 1),
	}
	if cfg.DatabaseURL == "" {
		return cfg, fmt.Errorf(
			"NEWME_DATABASE_URL is required, e.g. postgres://user:password@host:5432/newme?sslmode=disable")
	}
	if len(cfg.AppKey) < minAppKeyLen {
		return cfg, fmt.Errorf("NEWME_APP_KEY is required and must be at least %d characters", minAppKeyLen)
	}
	if v := os.Getenv("NEWME_SEASON_START"); v != "" {
		t, err := time.Parse(time.DateOnly, v)
		if err != nil {
			return cfg, fmt.Errorf("NEWME_SEASON_START must be an ISO date (YYYY-MM-DD): %w", err)
		}
		cfg.SeasonStart = t
	}
	return cfg, nil
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// getPositiveInt falls back to def unless the value is a positive integer, because
// middleware.ClientIPFromXFFTrustedProxies panics below 1.
func getPositiveInt(key string, def int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 1 {
			return n
		}
	}
	return def
}
