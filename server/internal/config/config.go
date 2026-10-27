package config

import (
	"fmt"
	"net/url"
	"os"
	"strconv"
	"strings"

	"github.com/nc1107/new-me/server/internal/semver"
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
	// MaxUsers caps how many people may join this server.
	MaxUsers int
	// MinClientVersion is the oldest app version the server serves; older ones get a 426.
	MinClientVersion string
	// DevCORS allows localhost browser origins, for reviewing the web build. Never set in
	// production.
	DevCORS bool
	// ABSURL is the base URL of the Audiobookshelf server whose listening time counts toward
	// reading. Empty turns the feature off.
	ABSURL string
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
		MaxUsers:         getPositiveInt("NEWME_MAX_USERS", 2),
		MinClientVersion: getenv("NEWME_MIN_CLIENT_VERSION", "0.0.0"),
	}
	if _, err := semver.Parse(cfg.MinClientVersion); err != nil {
		return cfg, fmt.Errorf("NEWME_MIN_CLIENT_VERSION: %w", err)
	}
	devCORS, err := getBool("NEWME_DEV_CORS")
	if err != nil {
		return cfg, err
	}
	cfg.DevCORS = devCORS
	if cfg.ABSURL, err = getBaseURL("NEWME_ABS_URL"); err != nil {
		return cfg, err
	}
	if cfg.DatabaseURL == "" {
		return cfg, fmt.Errorf(
			"NEWME_DATABASE_URL is required, e.g. postgres://user:password@host:5432/newme?sslmode=disable")
	}
	if len(cfg.AppKey) < minAppKeyLen {
		return cfg, fmt.Errorf("NEWME_APP_KEY is required and must be at least %d characters", minAppKeyLen)
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

// getBool reads a boolean flag, treating unset as false and rejecting anything unparseable so a
// typo cannot silently leave a safety switch in the wrong position.
func getBool(key string) (bool, error) {
	v := os.Getenv(key)
	if v == "" {
		return false, nil
	}
	b, err := strconv.ParseBool(v)
	if err != nil {
		return false, fmt.Errorf("%s must be a boolean: %w", key, err)
	}
	return b, nil
}

// getBaseURL reads an optional http(s) base URL without a trailing slash, so a typo cannot
// silently point the server at nothing.
func getBaseURL(key string) (string, error) {
	v := strings.TrimRight(strings.TrimSpace(os.Getenv(key)), "/")
	if v == "" {
		return "", nil
	}
	u, err := url.Parse(v)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return "", fmt.Errorf("%s must be an http or https URL, got %q", key, v)
	}
	return v, nil
}
