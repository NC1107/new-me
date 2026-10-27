package api

import (
	"bytes"
	"encoding/json"
	"net/http"
	"strconv"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/ratelimit"
)

func TestTextPostgresCannotStoreIsRejectedNotAServerError(t *testing.T) {
	h := newHarness(t)
	h.post("/api/join", "", obj{"name": "Ni\x00ck", "color": "green", "timezone": "UTC"}).
		expect(http.StatusUnprocessableEntity).code("invalid_request")

	nick := h.joinAdmin("Nick", "green")
	h.patch("/api/me", nick.Token, obj{"name": "Ni\x00ck"}).
		expect(http.StatusUnprocessableEntity).code("invalid_request")
	h.logMeal(nick, "Oat\x00meal", 300, 10).
		expect(http.StatusUnprocessableEntity).code("invalid_request")
	h.put("/api/health/daily", nick.Token, obj{"items": []obj{{
		"date": "2026-11-02", "metric": "steps", "value": 10, "source": "fa\x00ke",
		"measuredAt": h.clock.Now().UTC().Format(time.RFC3339)}}}).
		expect(http.StatusUnprocessableEntity).code("invalid_request")
}

func TestProteinIsScoredInTenthsOfAGram(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.patch("/api/me", nick.Token, obj{"targets": obj{"protein": 30}}).expect(http.StatusOK)
	// Template targets apply from the next day, so score tomorrow.
	h.clock.Set(ny(2026, time.November, 3, 12, 0))

	got := h.logMeal(nick, "Shake", 200, 29.9).expect(http.StatusCreated)
	var protein int = -1
	for i := range got.length("day.quests") {
		if got.str("day.quests."+itoa(i)+".key") == "protein" {
			protein = got.num("day.quests." + itoa(i) + ".basePoints")
		}
	}
	// (50*299 + 150) / 300 with the progress counted in tenths.
	if protein != 50 {
		t.Fatalf("protein base points = %d, want 50; body: %s", protein, got.Body)
	}
}

func TestZoneChangeOnTheJoinDayDoesNotLockTheUserOut(t *testing.T) {
	h := newHarness(t)
	// 12:00 in New York is 02:00 on the 3rd in Tokyo.
	tokyo := h.post("/api/join", "", obj{"name": "Kai", "color": "sky", "timezone": "Asia/Tokyo"}).
		expect(http.StatusCreated)
	token := tokyo.str("token")

	h.patch("/api/me", token, obj{"timezone": "America/New_York"}).expect(http.StatusOK)
	h.get("/api/today", token).expect(http.StatusOK)
	h.logActivity(person{Token: token}, "pushups", "reps", 5).expect(http.StatusCreated)
}

func TestZoneChangeAppliesFromTheNextLocalDay(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")

	got := h.patch("/api/me", nick.Token, obj{"timezone": "Asia/Tokyo"}).expect(http.StatusOK)
	if got.str("user.timezone") != "Asia/Tokyo" || got.str("localToday") != "2026-11-02" {
		t.Fatalf("the choice must show at once while today keeps its date: %s", got.Body)
	}

	// 23:00 in New York is already the 3rd in Tokyo, but the old zone's day has not ended.
	h.clock.Set(ny(2026, time.November, 2, 23, 0))
	if h.get("/api/me", nick.Token).expect(http.StatusOK).str("localToday") != "2026-11-02" {
		t.Fatal("the switch must wait for the old zone to reach the next day")
	}

	h.clock.Set(ny(2026, time.November, 3, 1, 0))
	got = h.get("/api/me", nick.Token).expect(http.StatusOK)
	if got.str("localToday") != "2026-11-03" || got.str("user.timezone") != "Asia/Tokyo" {
		t.Fatalf("after the switch: %s", got.Body)
	}
}

func TestZoneChangeWestwardWaitsUntilNoDateRepeats(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.November, 1, 12, 0))
	kai := h.post("/api/join", "", obj{"name": "Kai", "color": "sky", "timezone": "Asia/Tokyo"}).
		expect(http.StatusCreated).str("token")
	h.patch("/api/me", kai, obj{"timezone": "America/New_York"}).expect(http.StatusOK)

	// Tokyo has reached the 3rd (02:00) while New York is still on the 2nd: switching now would
	// repeat the 2nd.
	h.clock.Set(ny(2026, time.November, 2, 12, 0))
	if got := h.get("/api/me", kai).expect(http.StatusOK).str("localToday"); got != "2026-11-03" {
		t.Fatalf("localToday = %s, want it to stay on Tokyo's date", got)
	}

	// 15:00 on the 3rd in Tokyo is 01:00 on the 3rd in New York: the dates agree.
	h.clock.Set(ny(2026, time.November, 3, 1, 0))
	if got := h.get("/api/me", kai).expect(http.StatusOK).str("localToday"); got != "2026-11-03" {
		t.Fatalf("localToday = %s after the switch", got)
	}

	// Tokyo is now on the 4th, New York is not.
	h.clock.Set(ny(2026, time.November, 3, 23, 0))
	if got := h.get("/api/me", kai).expect(http.StatusOK).str("localToday"); got != "2026-11-03" {
		t.Fatalf("localToday = %s, want the new zone's date", got)
	}
}

func TestJoinLimitKeysOnTheAddressTheProxyAppendedNotOnAForgedOne(t *testing.T) {
	h := newHarness(t, func(s *Server) { s.limits.join = ratelimit.New(5, 5) })
	forged := func(chain string) func(*http.Request) {
		return func(r *http.Request) { r.Header.Set("X-Forwarded-For", chain) }
	}
	probe := func(chain string) *response {
		raw, _ := json.Marshal(obj{"code": "AAAA-AAAA-AAAA-AAAA"})
		return h.do(http.MethodPost, "/api/invites/check", "", bytes.NewReader(raw), forged(chain))
	}
	for i := range 5 {
		// The leftmost entry is whatever the caller claims; only the last one is the proxy's.
		probe("10.0.0." + strconv.Itoa(i) + ", 203.0.113.9").expect(http.StatusOK)
	}
	probe("10.9.9.9, 203.0.113.9").expect(http.StatusTooManyRequests)
	probe("10.9.9.9, 203.0.113.10").expect(http.StatusOK)
}
