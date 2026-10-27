package push

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"io"
	"math/big"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

func newKey(t *testing.T) *ecdsa.PrivateKey {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	return key
}

type seen struct {
	path    string
	header  http.Header
	body    []byte
	proto   string
	jwtSigs string
}

// fakeAPNs is an HTTP/2 TLS server that records requests and answers with the scripted status.
type fakeAPNs struct {
	mu     sync.Mutex
	reqs   []seen
	status func(n int, r *http.Request) (int, string)
	srv    *httptest.Server
}

func newFakeAPNs(t *testing.T) *fakeAPNs {
	t.Helper()
	f := &fakeAPNs{status: func(int, *http.Request) (int, string) { return 200, "" }}
	f.srv = httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		f.mu.Lock()
		f.reqs = append(f.reqs, seen{path: r.URL.Path, header: r.Header.Clone(), body: body, proto: r.Proto})
		n := len(f.reqs)
		f.mu.Unlock()
		code, reason := f.status(n, r)
		if reason != "" {
			w.WriteHeader(code)
			_ = json.NewEncoder(w).Encode(map[string]string{"reason": reason})
			return
		}
		w.WriteHeader(code)
	}))
	f.srv.EnableHTTP2 = true
	f.srv.StartTLS()
	t.Cleanup(f.srv.Close)
	return f
}

func (f *fakeAPNs) requests() []seen {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]seen(nil), f.reqs...)
}

// client trusts only the fake's certificate and speaks HTTP/2 to it.
func (f *fakeAPNs) client(t *testing.T, key *ecdsa.PrivateKey, now func() time.Time) *Client {
	t.Helper()
	pool := x509.NewCertPool()
	pool.AddCert(f.srv.Certificate())
	c, err := NewClient(Config{
		Key: key, KeyID: "KEY1234567", TeamID: "TEAM123456", Topic: "top.example.app", BaseURL: f.srv.URL, Now: now,
		HTTPClient: &http.Client{Transport: &http.Transport{
			ForceAttemptHTTP2: true, TLSClientConfig: &tls.Config{RootCAs: pool}}},
	})
	if err != nil {
		t.Fatal(err)
	}
	return c
}

func decodeJWT(t *testing.T, token string) (header, claims map[string]any, signingInput string, sig []byte) {
	t.Helper()
	parts := strings.Split(strings.TrimPrefix(token, "bearer "), ".")
	if len(parts) != 3 {
		t.Fatalf("jwt has %d parts", len(parts))
	}
	dec := func(s string, v *map[string]any) {
		raw, err := base64.RawURLEncoding.DecodeString(s)
		if err != nil {
			t.Fatal(err)
		}
		if err := json.Unmarshal(raw, v); err != nil {
			t.Fatal(err)
		}
	}
	dec(parts[0], &header)
	dec(parts[1], &claims)
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		t.Fatal(err)
	}
	return header, claims, parts[0] + "." + parts[1], sig
}

func TestSignJWTProducesAnES256TokenAppleCanVerify(t *testing.T) {
	key := newKey(t)
	issued := time.Date(2026, 11, 2, 12, 0, 0, 0, time.UTC)
	token, err := SignJWT(key, "KEY1234567", "TEAM123456", issued)
	if err != nil {
		t.Fatal(err)
	}
	header, claims, input, sig := decodeJWT(t, token)
	if header["alg"] != "ES256" || header["kid"] != "KEY1234567" {
		t.Fatalf("header = %v", header)
	}
	if claims["iss"] != "TEAM123456" || int64(claims["iat"].(float64)) != issued.Unix() {
		t.Fatalf("claims = %v", claims)
	}
	if len(sig) != 64 {
		t.Fatalf("signature is %d bytes, want the 64-byte r||s form", len(sig))
	}
	sum := sha256.Sum256([]byte(input))
	r, s := new(big.Int).SetBytes(sig[:32]), new(big.Int).SetBytes(sig[32:])
	if !ecdsa.Verify(&key.PublicKey, sum[:], r, s) {
		t.Fatal("signature does not verify against the public key")
	}
}

func TestParseKeyReadsABase64P8(t *testing.T) {
	key := newKey(t)
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	p8 := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})
	got, err := ParseKey(base64.StdEncoding.EncodeToString(p8) + "\n")
	if err != nil || !got.Equal(key) {
		t.Fatalf("ParseKey = %v, %v", got, err)
	}
	for _, bad := range []string{"", "not base64!", base64.StdEncoding.EncodeToString([]byte("plain text"))} {
		if _, err := ParseKey(bad); err == nil {
			t.Errorf("ParseKey(%q) accepted", bad)
		}
	}
}

func TestPayloadCarriesTheAlertAndKind(t *testing.T) {
	raw, err := Payload(Message{Kind: "cheer", Title: "Nadia cheered your day", Body: "Fire"})
	if err != nil {
		t.Fatal(err)
	}
	var got struct {
		Aps struct {
			Alert    struct{ Title, Body string }
			Sound    string
			ThreadID string `json:"thread-id"`
		}
		Kind string
	}
	if err := json.Unmarshal(raw, &got); err != nil {
		t.Fatal(err)
	}
	if got.Aps.Alert.Title != "Nadia cheered your day" || got.Aps.Alert.Body != "Fire" ||
		got.Aps.Sound != "default" || got.Aps.ThreadID != "cheer" || got.Kind != "cheer" {
		t.Fatalf("payload = %s", raw)
	}
}

func TestSendUsesHTTP2WithTheApnsHeadersAndASignedToken(t *testing.T) {
	fake := newFakeAPNs(t)
	key := newKey(t)
	c := fake.client(t, key, time.Now)
	if err := c.Send(context.Background(), "abc123", Message{Kind: "reward", Title: "T", Body: "B"}); err != nil {
		t.Fatal(err)
	}
	reqs := fake.requests()
	if len(reqs) != 1 {
		t.Fatalf("requests = %d", len(reqs))
	}
	r := reqs[0]
	if r.proto != "HTTP/2.0" || r.path != "/3/device/abc123" {
		t.Fatalf("proto/path = %s %s", r.proto, r.path)
	}
	if r.header.Get("apns-topic") != "top.example.app" || r.header.Get("apns-push-type") != "alert" ||
		r.header.Get("apns-priority") != "10" {
		t.Fatalf("headers = %v", r.header)
	}
	header, claims, input, sig := decodeJWT(t, r.header.Get("authorization"))
	sum := sha256.Sum256([]byte(input))
	if header["kid"] != "KEY1234567" || claims["iss"] != "TEAM123456" ||
		!ecdsa.Verify(&key.PublicKey, sum[:], new(big.Int).SetBytes(sig[:32]), new(big.Int).SetBytes(sig[32:])) {
		t.Fatalf("authorization token is wrong: %v %v", header, claims)
	}
	if !strings.HasPrefix(r.header.Get("authorization"), "bearer ") || !strings.Contains(string(r.body), `"title":"T"`) {
		t.Fatalf("authorization %q body %s", r.header.Get("authorization"), r.body)
	}
}

func TestProviderTokenIsCachedAndRefreshedBeforeAnHour(t *testing.T) {
	fake := newFakeAPNs(t)
	now := time.Date(2026, 11, 2, 12, 0, 0, 0, time.UTC)
	c := fake.client(t, newKey(t), func() time.Time { return now })
	send := func() {
		t.Helper()
		if err := c.Send(context.Background(), "tok", Message{Kind: "k"}); err != nil {
			t.Fatal(err)
		}
	}
	send()
	now = now.Add(30 * time.Minute)
	send()
	now = now.Add(21 * time.Minute)
	send()
	auth := func(i int) string { return fake.requests()[i].header.Get("authorization") }
	if auth(0) != auth(1) {
		t.Error("the token was re-signed inside its lifetime")
	}
	if auth(1) == auth(2) {
		t.Error("the token was reused past 50 minutes")
	}
}

func TestSendRetriesOnceWithAFreshTokenWhenAppleSaysItExpired(t *testing.T) {
	fake := newFakeAPNs(t)
	fake.status = func(n int, _ *http.Request) (int, string) {
		if n == 1 {
			return 403, "ExpiredProviderToken"
		}
		return 200, ""
	}
	now := time.Date(2026, 11, 2, 12, 0, 0, 0, time.UTC)
	c := fake.client(t, newKey(t), func() time.Time { now = now.Add(time.Second); return now })
	if err := c.Send(context.Background(), "tok", Message{Kind: "k"}); err != nil {
		t.Fatal(err)
	}
	reqs := fake.requests()
	if len(reqs) != 2 || reqs[0].header.Get("authorization") == reqs[1].header.Get("authorization") {
		t.Fatalf("requests = %d, tokens equal = %v", len(reqs), len(reqs) == 2 &&
			reqs[0].header.Get("authorization") == reqs[1].header.Get("authorization"))
	}
}

func TestSendReportsDeadTokensAs410AndBadDeviceToken(t *testing.T) {
	for _, tc := range []struct {
		code   int
		reason string
	}{{410, "Unregistered"}, {400, "BadDeviceToken"}} {
		fake := newFakeAPNs(t)
		fake.status = func(int, *http.Request) (int, string) { return tc.code, tc.reason }
		err := fake.client(t, newKey(t), time.Now).Send(context.Background(), "tok", Message{Kind: "k"})
		if !errors.Is(err, ErrUnregistered) {
			t.Errorf("%d %s: err = %v, want ErrUnregistered", tc.code, tc.reason, err)
		}
	}
	fake := newFakeAPNs(t)
	fake.status = func(int, *http.Request) (int, string) { return 500, "InternalServerError" }
	if err := fake.client(t, newKey(t), time.Now).Send(context.Background(), "tok", Message{}); err == nil ||
		errors.Is(err, ErrUnregistered) {
		t.Errorf("a 500 should be a plain failure, got %v", err)
	}
}

func TestSandboxAndProductionHosts(t *testing.T) {
	key := newKey(t)
	for _, tc := range []struct {
		sandbox bool
		want    string
	}{{false, "https://api.push.apple.com"}, {true, "https://api.sandbox.push.apple.com"}} {
		c, err := NewClient(Config{Key: key, KeyID: "k", TeamID: "t", Topic: "x", Sandbox: tc.sandbox})
		if err != nil || c.base != tc.want {
			t.Errorf("sandbox=%v base = %q, err %v, want %q", tc.sandbox, c.base, err, tc.want)
		}
	}
	if _, err := NewClient(Config{}); err == nil {
		t.Error("an empty config was accepted")
	}
}

type fakeStore struct {
	mu      sync.Mutex
	tokens  map[int64][]string
	removed []string
}

func (s *fakeStore) Tokens(_ context.Context, id int64) ([]string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.tokens[id], nil
}

func (s *fakeStore) Remove(_ context.Context, token string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.removed = append(s.removed, token)
	return nil
}

type fakeSender struct {
	sent chan string
	fail map[string]error
}

func (s *fakeSender) Send(_ context.Context, token string, _ Message) error {
	s.sent <- token
	return s.fail[token]
}

func TestDispatcherDeliversToEveryTokenAndPrunesTheDeadOnes(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	store := &fakeStore{tokens: map[int64][]string{7: {"live", "dead"}}}
	sender := &fakeSender{sent: make(chan string, 8), fail: map[string]error{"dead": ErrUnregistered}}
	d := NewDispatcher(ctx, sender, store)
	if !d.Enqueue(Message{UserID: 7, Kind: "cheer"}) {
		t.Fatal("enqueue refused")
	}
	for range 2 {
		select {
		case <-sender.sent:
		case <-time.After(5 * time.Second):
			t.Fatal("message was not delivered")
		}
	}
	cancel()
	d.Wait()
	store.mu.Lock()
	defer store.mu.Unlock()
	if len(store.removed) != 1 || store.removed[0] != "dead" {
		t.Fatalf("removed = %v, want [dead]", store.removed)
	}
}

func TestDispatcherNeverBlocksWhenTheQueueIsFull(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	release := make(chan struct{})
	d := NewDispatcher(ctx, blockingSender{release}, &fakeStore{tokens: map[int64][]string{1: {"t"}}})
	defer close(release)
	done := make(chan struct{})
	go func() {
		defer close(done)
		for range 10 * defaultQueue {
			d.Enqueue(Message{UserID: 1})
		}
	}()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("Enqueue blocked on a stuck sender")
	}
}

type blockingSender struct{ release chan struct{} }

func (b blockingSender) Send(ctx context.Context, _ string, _ Message) error {
	select {
	case <-b.release:
	case <-ctx.Done():
	}
	return nil
}
