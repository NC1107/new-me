// Package push delivers notifications through the Apple Push Notification service with
// token-based authentication. Nothing here is required for the app to work: a server without
// APNs credentials simply never builds a client.
package push

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"
)

const (
	productionHost = "https://api.push.apple.com"
	sandboxHost    = "https://api.sandbox.push.apple.com"

	// jwtLifetime is how long one provider token is reused. Apple rejects tokens older than an
	// hour and throttles issuing a new one more often than every 20 minutes.
	jwtLifetime = 50 * time.Minute
	sendTimeout = 10 * time.Second
)

// ErrUnregistered means Apple will never deliver to the token again, so it should be dropped.
var ErrUnregistered = errors.New("push: device token is no longer valid")

// Config is what the client needs to talk to APNs.
type Config struct {
	// Key is the .p8 signing key.
	Key     *ecdsa.PrivateKey
	KeyID   string
	TeamID  string
	Topic   string
	Sandbox bool
	// BaseURL overrides the APNs host, for tests.
	BaseURL string
	// HTTPClient overrides the transport, for tests that trust a fake server's certificate.
	HTTPClient *http.Client
	Now        func() time.Time
}

// ParseKey reads the base64 of a .p8 file, which is a PKCS #8 PEM holding a P-256 key.
func ParseKey(b64 string) (*ecdsa.PrivateKey, error) {
	raw, err := base64.StdEncoding.DecodeString(strings.TrimSpace(b64))
	if err != nil {
		return nil, fmt.Errorf("apns key is not base64: %w", err)
	}
	block, _ := pem.Decode(raw)
	if block == nil {
		return nil, errors.New("apns key is not PEM")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("apns key: %w", err)
	}
	key, ok := parsed.(*ecdsa.PrivateKey)
	if !ok || key.Curve.Params().BitSize != 256 {
		return nil, errors.New("apns key must be an ECDSA P-256 key")
	}
	return key, nil
}

// Message is one notification for a person. Kind groups related notifications and rides along
// in the payload so the app can route a tap.
type Message struct {
	UserID int64
	Kind   string
	Title  string
	Body   string
}

// Client sends alerts to APNs over HTTP/2.
type Client struct {
	cfg  Config
	base string
	http *http.Client

	mu       sync.Mutex
	jwt      string
	jwtMaker time.Time
}

// NewClient builds a client from a validated config.
func NewClient(cfg Config) (*Client, error) {
	if cfg.Key == nil || cfg.KeyID == "" || cfg.TeamID == "" || cfg.Topic == "" {
		return nil, errors.New("push: key, key id, team id and topic are required")
	}
	if cfg.Now == nil {
		cfg.Now = time.Now
	}
	base := productionHost
	if cfg.Sandbox {
		base = sandboxHost
	}
	if cfg.BaseURL != "" {
		base = strings.TrimRight(cfg.BaseURL, "/")
	}
	client := cfg.HTTPClient
	if client == nil {
		client = &http.Client{Transport: &http.Transport{ForceAttemptHTTP2: true}, Timeout: sendTimeout}
	}
	return &Client{cfg: cfg, base: base, http: client}, nil
}

// Payload is the JSON body of an alert.
func Payload(m Message) ([]byte, error) {
	return json.Marshal(map[string]any{
		"aps": map[string]any{
			"alert":     map[string]string{"title": m.Title, "body": m.Body},
			"sound":     "default",
			"thread-id": m.Kind,
		},
		"kind": m.Kind,
	})
}

// providerToken returns the cached JWT, signing a fresh one once it is old enough.
func (c *Client) providerToken(force bool) (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	now := c.cfg.Now()
	if !force && c.jwt != "" && now.Sub(c.jwtMaker) < jwtLifetime {
		return c.jwt, nil
	}
	token, err := SignJWT(c.cfg.Key, c.cfg.KeyID, c.cfg.TeamID, now)
	if err != nil {
		return "", err
	}
	c.jwt, c.jwtMaker = token, now
	return token, nil
}

// SignJWT builds the ES256 provider token APNs expects: the key id in the header, the team id
// as issuer and the issue time as claims.
func SignJWT(key *ecdsa.PrivateKey, keyID, teamID string, issuedAt time.Time) (string, error) {
	header, err := json.Marshal(map[string]string{"alg": "ES256", "kid": keyID})
	if err != nil {
		return "", err
	}
	claims, err := json.Marshal(map[string]any{"iss": teamID, "iat": issuedAt.Unix()})
	if err != nil {
		return "", err
	}
	enc := base64.RawURLEncoding
	signingInput := enc.EncodeToString(header) + "." + enc.EncodeToString(claims)
	sum := sha256.Sum256([]byte(signingInput))
	r, s, err := ecdsa.Sign(rand.Reader, key, sum[:])
	if err != nil {
		return "", err
	}
	// JWS wants the fixed-width r||s, not the ASN.1 form.
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	s.FillBytes(sig[32:])
	return signingInput + "." + enc.EncodeToString(sig), nil
}

// Send delivers one alert to one device token. It returns ErrUnregistered when Apple says the
// token is dead.
func (c *Client) Send(ctx context.Context, deviceToken string, m Message) error {
	body, err := Payload(m)
	if err != nil {
		return err
	}
	err = c.send(ctx, deviceToken, body, false)
	var expired *apnsError
	if errors.As(err, &expired) && expired.Reason == "ExpiredProviderToken" {
		err = c.send(ctx, deviceToken, body, true)
	}
	return err
}

type apnsError struct {
	Status int
	Reason string
}

func (e *apnsError) Error() string { return fmt.Sprintf("apns %d %s", e.Status, e.Reason) }

func (c *Client) send(ctx context.Context, deviceToken string, body []byte, refresh bool) error {
	jwt, err := c.providerToken(refresh)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(ctx, sendTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.base+"/3/device/"+deviceToken, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("authorization", "bearer "+jwt)
	req.Header.Set("apns-topic", c.cfg.Topic)
	req.Header.Set("apns-push-type", "alert")
	req.Header.Set("apns-priority", "10")
	req.Header.Set("content-type", "application/json")
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusOK {
		_, _ = io.Copy(io.Discard, resp.Body)
		return nil
	}
	var reason struct {
		Reason string `json:"reason"`
	}
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	_ = json.Unmarshal(raw, &reason)
	if resp.StatusCode == http.StatusGone || reason.Reason == "BadDeviceToken" || reason.Reason == "Unregistered" {
		return fmt.Errorf("%w (%d %s)", ErrUnregistered, resp.StatusCode, reason.Reason)
	}
	return &apnsError{Status: resp.StatusCode, Reason: reason.Reason}
}
