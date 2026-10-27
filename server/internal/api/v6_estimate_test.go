package api

import (
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"

	"github.com/nc1107/new-me/server/internal/anthropic"
	"github.com/nc1107/new-me/server/internal/estimate"
)

// fakeClaude stands in for the Anthropic API: it records requests and answers with a canned
// reply.
type fakeClaude struct {
	mu       sync.Mutex
	requests []map[string]any
	headers  []http.Header
	status   int
	reply    func(req map[string]any) any
}

func newFakeClaude(t *testing.T) (*fakeClaude, *httptest.Server) {
	f := &fakeClaude{status: http.StatusOK, reply: forTool(goodEstimate())}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw, _ := io.ReadAll(r.Body)
		var req map[string]any
		_ = json.Unmarshal(raw, &req)
		f.mu.Lock()
		f.requests = append(f.requests, req)
		f.headers = append(f.headers, r.Header.Clone())
		status, reply := f.status, f.reply
		f.mu.Unlock()
		if r.URL.Path != "/v1/messages" || r.Method != http.MethodPost {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		_ = json.NewEncoder(w).Encode(reply(req))
	}))
	t.Cleanup(srv.Close)
	return f, srv
}

func (f *fakeClaude) count() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.requests)
}

func toolName(req map[string]any) string {
	return req["tool_choice"].(map[string]any)["name"].(string)
}

// splitReply is what the parse step returns for a one-food sentence.
func splitReply() obj {
	return toolReply(obj{"items": []obj{{"text": "chicken burrito bowl, no rice", "label": "Chicken burrito bowl",
		"food": "chicken burrito bowl", "brand": nil, "quantity": 1, "unit": "bowl", "grams": nil, "kind": "generic"}}})
}

// forTool answers the parse step with one item and every other call with the given estimate.
func forTool(estimateInput any) func(map[string]any) any {
	return func(req map[string]any) any {
		if toolName(req) == "split_meal" {
			return splitReply()
		}
		return toolReply(estimateInput)
	}
}

func goodEstimate() obj {
	return obj{"name": "Chicken burrito bowl", "kcal": 640.4, "protein": 42, "carbs": 58, "fat": 22, "fiber": 9,
		"confidence": "medium", "notes": "Assumes a restaurant-size bowl."}
}

func toolReply(input any) obj {
	return obj{"id": "msg_1", "type": "message", "role": "assistant", "stop_reason": "tool_use",
		"content": []obj{{"type": "tool_use", "id": "tu_1", "name": "report_meal_estimate", "input": input}}}
}

func withClaude(srv *httptest.Server) func(*Server) {
	return func(s *Server) {
		client := anthropic.New("sk-test-key", srv.URL)
		s.estimator = &estimate.Estimator{Client: client}
	}
}

func jpegB64(size int) string {
	b := make([]byte, size)
	copy(b, []byte{0xFF, 0xD8, 0xFF, 0xE0})
	return base64.StdEncoding.EncodeToString(b)
}

func TestEstimateIsOffWithoutAKey(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.post("/api/meals/estimate", nick.Token, obj{"text": "toast"}).expect(http.StatusNotFound).code("estimate_disabled")
	if h.get("/api/me", nick.Token).flag("features.mealEstimate") {
		t.Fatal("features.mealEstimate must be false without a key")
	}
}

func TestEstimateFromTextSendsTheForcedToolRequestAndClampsTheAnswer(t *testing.T) {
	fake, srv := newFakeClaude(t)
	h := newHarness(t, withClaude(srv))
	nick := h.joinAdmin("Nick", "green")
	if !h.get("/api/me", nick.Token).flag("features.mealEstimate") {
		t.Fatal("features.mealEstimate must be true with a key")
	}

	got := h.post("/api/meals/estimate", nick.Token, obj{"text": "  chicken burrito bowl, no rice "}).expect(http.StatusOK)
	if got.str("name") != "Chicken burrito bowl" || got.num("kcal") != 640 || got.at("protein") != 42.0 ||
		got.str("confidence") != "medium" || got.at("databaseShare") != 0.0 {
		t.Fatalf("estimate = %s", got.Body)
	}

	items := got.at("items").([]any)
	if len(items) != 1 || items[0].(map[string]any)["source"] != "estimated" || got.at("total").(map[string]any)["kcal"] != 640.0 {
		t.Fatalf("items = %s", got.Body)
	}
	if fake.count() != 2 {
		t.Fatalf("calls = %d, want the parse call and one item estimate", fake.count())
	}
	req, hdr := fake.requests[0], fake.headers[0]
	if hdr.Get("x-api-key") != "sk-test-key" || hdr.Get("anthropic-version") != "2023-06-01" ||
		!strings.HasPrefix(hdr.Get("content-type"), "application/json") {
		t.Fatalf("headers = %v", hdr)
	}
	if req["model"] != "claude-sonnet-4-6" || req["max_tokens"] == nil {
		t.Fatalf("request = %v", req)
	}
	choice := req["tool_choice"].(map[string]any)
	tool := req["tools"].([]any)[0].(map[string]any)
	schema := tool["input_schema"].(map[string]any)
	if choice["type"] != "tool" || choice["name"] != tool["name"] || schema["type"] != "object" ||
		choice["name"] != "split_meal" || len(schema["required"].([]any)) != 1 {
		t.Fatalf("tool use = %v / %v", choice, tool)
	}
	content := req["messages"].([]any)[0].(map[string]any)["content"].([]any)
	if len(content) != 1 || !strings.Contains(content[0].(map[string]any)["text"].(string), "chicken burrito bowl, no rice") {
		t.Fatalf("content = %v", content)
	}
}

func TestEstimateFromAPhotoSendsAnImageBlock(t *testing.T) {
	fake, srv := newFakeClaude(t)
	h := newHarness(t, withClaude(srv))
	nick := h.joinAdmin("Nick", "green")
	image := jpegB64(2048)

	h.post("/api/meals/estimate", nick.Token, obj{"image": image, "mediaType": "image/jpeg"}).expect(http.StatusOK)
	content := fake.requests[0]["messages"].([]any)[0].(map[string]any)["content"].([]any)
	first := content[0].(map[string]any)
	source := first["source"].(map[string]any)
	if first["type"] != "image" || source["type"] != "base64" || source["media_type"] != "image/jpeg" || source["data"] != image {
		t.Fatalf("first block = %v", first)
	}
	if content[1].(map[string]any)["type"] != "text" {
		t.Fatalf("content = %v", content)
	}

	// A caption rides along as a hint.
	h.post("/api/meals/estimate", nick.Token, obj{"image": image, "mediaType": "image/jpeg", "text": "half portion"}).expect(http.StatusOK)
	text := fake.requests[1]["messages"].([]any)[0].(map[string]any)["content"].([]any)[1].(map[string]any)["text"].(string)
	if !strings.Contains(text, "half portion") {
		t.Fatalf("hint missing: %q", text)
	}
}

func TestEstimateClampsWildAnswersToTheMealLogBounds(t *testing.T) {
	fake, srv := newFakeClaude(t)
	fake.reply = forTool(obj{"name": "x", "kcal": 1e9, "protein": 99999, "carbs": -5, "fat": 3.14159, "fiber": 0,
		"confidence": "certain", "notes": strings.Repeat("n", 500)})
	h := newHarness(t, withClaude(srv))
	nick := h.joinAdmin("Nick", "green")

	got := h.post("/api/meals/estimate", nick.Token, obj{"text": "mystery"}).expect(http.StatusOK)
	if got.num("kcal") != 10000 || got.at("protein") != 5000.0 || got.at("carbs") != 0.0 || got.at("fat") != 3.1 ||
		got.str("confidence") != "low" {
		t.Fatalf("estimate = %s", got.Body)
	}
	// What comes back must be loggable as it is.
	h.logMeal(nick, got.str("name"), got.num("kcal"), got.at("protein").(float64)).expect(http.StatusCreated)
}

func TestEstimateValidation(t *testing.T) {
	fake, srv := newFakeClaude(t)
	h := newHarness(t, withClaude(srv))
	nick := h.joinAdmin("Nick", "green")

	for name, tc := range map[string]struct {
		body   obj
		status int
		code   string
	}{
		"empty":             {obj{}, http.StatusUnprocessableEntity, "invalid_request"},
		"blank text":        {obj{"text": "   "}, http.StatusUnprocessableEntity, "invalid_request"},
		"long text":         {obj{"text": strings.Repeat("a", 501)}, http.StatusUnprocessableEntity, "invalid_request"},
		"control chars":     {obj{"text": "a\x00b"}, http.StatusUnprocessableEntity, "invalid_request"},
		"image no type":     {obj{"image": jpegB64(100)}, http.StatusUnprocessableEntity, "invalid_request"},
		"gif":               {obj{"image": jpegB64(100), "mediaType": "image/gif"}, http.StatusUnprocessableEntity, "invalid_request"},
		"not base64":        {obj{"image": "%%%", "mediaType": "image/jpeg"}, http.StatusUnprocessableEntity, "invalid_request"},
		"png claims jpeg":   {obj{"image": jpegB64(100), "mediaType": "image/png"}, http.StatusUnprocessableEntity, "invalid_request"},
		"over 5 MB decoded": {obj{"image": jpegB64(estimate.MaxImageBytes + 1), "mediaType": "image/jpeg"}, http.StatusRequestEntityTooLarge, "payload_too_large"},
		"unknown field":     {obj{"text": "toast", "extra": 1}, http.StatusBadRequest, "invalid_json"},
	} {
		t.Run(name, func(t *testing.T) {
			h.post("/api/meals/estimate", nick.Token, tc.body).expect(tc.status).code(tc.code)
		})
	}
	if fake.count() != 0 {
		t.Fatalf("invalid requests must never reach Claude (%d calls)", fake.count())
	}
	h.post("/api/meals/estimate", "", obj{"text": "toast"}).expect(http.StatusUnauthorized)

	just := jpegB64(estimate.MaxImageBytes)
	h.post("/api/meals/estimate", nick.Token, obj{"image": just, "mediaType": "image/jpeg"}).expect(http.StatusOK)
}

func TestEstimateUpstreamFailuresAre502(t *testing.T) {
	fake, srv := newFakeClaude(t)
	h := newHarness(t, withClaude(srv))
	nick := h.joinAdmin("Nick", "green")

	fake.status = http.StatusInternalServerError
	h.post("/api/meals/estimate", nick.Token, obj{"text": "toast"}).expect(http.StatusBadGateway).code("estimate_unavailable")

	fake.status = http.StatusOK
	fake.reply = func(map[string]any) any {
		return obj{"content": []obj{{"type": "text", "text": "I cannot help with that"}}}
	}
	h.post("/api/meals/estimate", nick.Token, obj{"text": "toast"}).expect(http.StatusBadGateway).code("estimate_unavailable")

	fake.reply = forTool(obj{"name": "no energy"})
	h.post("/api/meals/estimate", nick.Token, obj{"text": "toast"}).expect(http.StatusBadGateway).code("estimate_unavailable")

	srv.Close()
	h.post("/api/meals/estimate", nick.Token, obj{"text": "toast"}).expect(http.StatusBadGateway).code("estimate_unavailable")
}

func TestEstimateIsLimitedToTwentyAnHourPerPerson(t *testing.T) {
	fake, srv := newFakeClaude(t)
	h := newHarness(t, withClaude(srv))
	nick, nadia := h.pair()

	for i := range 20 {
		h.post("/api/meals/estimate", nick.Token, obj{"text": "toast"}).expect(http.StatusOK)
		_ = i
	}
	limited := h.post("/api/meals/estimate", nick.Token, obj{"text": "toast"}).expect(http.StatusTooManyRequests).code("rate_limited")
	if limited.Header.Get("Retry-After") == "" {
		t.Fatal("429 should say when to retry")
	}
	if fake.count() != 40 {
		t.Fatalf("calls = %d", fake.count())
	}
	h.post("/api/meals/estimate", nadia.Token, obj{"text": "toast"}).expect(http.StatusOK)
}
