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

func TestLoadAudiobookshelfURL(t *testing.T) {
	setRequired(t)
	cfg, err := Load()
	if err != nil || cfg.ABSURL != "" {
		t.Fatalf("default = %q, %v; the feature must start off", cfg.ABSURL, err)
	}
	t.Setenv("NEWME_ABS_URL", " https://books.example.com/ ")
	cfg, err = Load()
	if err != nil || cfg.ABSURL != "https://books.example.com" {
		t.Fatalf("got %q, %v", cfg.ABSURL, err)
	}
	for _, bad := range []string{"books.example.com", "ftp://books.example.com", "https://"} {
		t.Setenv("NEWME_ABS_URL", bad)
		if _, err := Load(); err == nil {
			t.Fatalf("expected an error for NEWME_ABS_URL=%q", bad)
		}
	}
}

func TestLoadAPNS(t *testing.T) {
	setRequired(t)
	cfg, err := Load()
	if err != nil || cfg.APNS.Enabled() {
		t.Fatalf("unset: %+v, %v", cfg.APNS, err)
	}

	t.Setenv("NEWME_APNS_KEY", "a2V5")
	if _, err := Load(); err == nil {
		t.Fatal("a key without the other settings was accepted")
	}

	t.Setenv("NEWME_APNS_KEY_ID", "ABC123DEFG")
	t.Setenv("NEWME_APNS_TEAM_ID", "76S78SUWVM")
	t.Setenv("NEWME_APNS_TOPIC", "top.npcserver.newme")
	cfg, err = Load()
	if err != nil || !cfg.APNS.Enabled() || !cfg.APNS.Production || cfg.APNS.Topic != "top.npcserver.newme" {
		t.Fatalf("configured: %+v, %v", cfg.APNS, err)
	}

	t.Setenv("NEWME_APNS_PRODUCTION", "false")
	if cfg, err = Load(); err != nil || cfg.APNS.Production {
		t.Fatalf("sandbox: %+v, %v", cfg.APNS, err)
	}
	t.Setenv("NEWME_APNS_PRODUCTION", "sometimes")
	if _, err = Load(); err == nil {
		t.Fatal("a bad NEWME_APNS_PRODUCTION was accepted")
	}
}

func TestLoadAnthropic(t *testing.T) {
	setRequired(t)
	cfg, err := Load()
	if err != nil || cfg.Anthropic.Enabled() || cfg.Anthropic.BaseURL != "" {
		t.Fatalf("unset must leave Claude off: %+v, %v", cfg.Anthropic, err)
	}
	t.Setenv("NEWME_ANTHROPIC_API_KEY", "  sk-ant-test  ")
	t.Setenv("NEWME_ANTHROPIC_BASE_URL", "http://127.0.0.1:9999/")
	cfg, err = Load()
	if err != nil || !cfg.Anthropic.Enabled() || cfg.Anthropic.Key != "sk-ant-test" || cfg.Anthropic.BaseURL != "http://127.0.0.1:9999" {
		t.Fatalf("got %+v, %v", cfg.Anthropic, err)
	}
	t.Setenv("NEWME_ANTHROPIC_BASE_URL", "not a url")
	if _, err := Load(); err == nil {
		t.Fatal("a malformed base URL must fail at boot")
	}
}
