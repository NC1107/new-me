package config

import "testing"

func setRequired(t *testing.T) {
	t.Helper()
	t.Setenv("NEWME_DATABASE_URL", "postgres://x")
	t.Setenv("NEWME_APP_KEY", "0123456789abcdef")
}

func TestLoadDefaults(t *testing.T) {
	setRequired(t)
	cfg, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.MaxUsers != 2 {
		t.Fatalf("MaxUsers = %d, want 2", cfg.MaxUsers)
	}
	if cfg.DevCORS {
		t.Fatal("DevCORS must default to off")
	}
	if cfg.MinClientVersion != "0.0.0" {
		t.Fatalf("MinClientVersion = %q, want 0.0.0", cfg.MinClientVersion)
	}
}

func TestLoadMinClientVersion(t *testing.T) {
	setRequired(t)
	t.Setenv("NEWME_MIN_CLIENT_VERSION", "1.4.0")
	cfg, err := Load()
	if err != nil || cfg.MinClientVersion != "1.4.0" {
		t.Fatalf("got %q, %v", cfg.MinClientVersion, err)
	}
	t.Setenv("NEWME_MIN_CLIENT_VERSION", "soon")
	if _, err := Load(); err == nil {
		t.Fatal("expected an error for an unparseable NEWME_MIN_CLIENT_VERSION")
	}
}

func TestLoadOverrides(t *testing.T) {
	setRequired(t)
	t.Setenv("NEWME_MAX_USERS", "3")
	t.Setenv("NEWME_DEV_CORS", "true")
	cfg, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.MaxUsers != 3 || !cfg.DevCORS {
		t.Fatalf("got MaxUsers=%d DevCORS=%v", cfg.MaxUsers, cfg.DevCORS)
	}
}

func TestLoadRejectsBadDevCORS(t *testing.T) {
	setRequired(t)
	t.Setenv("NEWME_DEV_CORS", "maybe")
	if _, err := Load(); err == nil {
		t.Fatal("expected an error for an unparseable NEWME_DEV_CORS")
	}
}

func TestLoadIgnoresNonPositiveMaxUsers(t *testing.T) {
	setRequired(t)
	t.Setenv("NEWME_MAX_USERS", "0")
	cfg, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.MaxUsers != 2 {
		t.Fatalf("MaxUsers = %d, want the default 2", cfg.MaxUsers)
	}
}

func TestLoadRequiresDatabaseAndKey(t *testing.T) {
	t.Setenv("NEWME_DATABASE_URL", "")
	t.Setenv("NEWME_APP_KEY", "")
	if _, err := Load(); err == nil {
		t.Fatal("expected an error with nothing configured")
	}
}
