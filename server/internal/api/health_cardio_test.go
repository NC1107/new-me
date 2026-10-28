package api

import (
	"net/http"
	"testing"
	"time"
)

func TestHealthCardioPlacesTheLatestReadingByAgeAndSex(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.November, 2, 22, 0))
	nick, nadia := h.pair()
	h.clock.Set(ny(2026, time.November, 3, 8, 0))

	none := h.get("/api/health/cardio", nick.Token).expect(http.StatusOK)
	if none.str("status") != "no_reading" || !none.isNull("latest") || !none.isNull("norm") || none.length("needs") != 0 {
		t.Fatalf("no reading = %s", none.Body)
	}

	h.put("/api/health/daily", nick.Token, obj{"items": []obj{
		healthReading("2026-11-02", "vo2max", 44, h.clock.Now()),
		healthReading("2026-11-03", "vo2max", 45, h.clock.Now()),
	}}).expect(http.StatusOK)
	h.put("/api/health/daily", nadia.Token, obj{"items": []obj{
		healthReading("2026-11-02", "vo2max", 30, h.clock.Now())}}).expect(http.StatusOK)

	bare := h.get("/api/health/cardio", nick.Token).expect(http.StatusOK)
	if bare.str("status") != "needs_profile" || bare.num("latest.value") != 45 || bare.str("latest.date") != "2026-11-03" ||
		bare.length("needs") != 2 || bare.str("needs.0") != "birthYear" || bare.str("needs.1") != "sex" || !bare.isNull("norm") {
		t.Fatalf("no profile = %s", bare.Body)
	}

	h.patch("/api/me", nick.Token, obj{"birthYear": 1986}).expect(http.StatusOK)
	half := h.get("/api/health/cardio", nick.Token).expect(http.StatusOK)
	if half.str("status") != "needs_profile" || half.length("needs") != 1 || half.str("needs.0") != "sex" {
		t.Fatalf("birth year only = %s", half.Body)
	}

	h.patch("/api/me", nick.Token, obj{"sex": "male"}).expect(http.StatusOK)
	got := h.get("/api/health/cardio", nick.Token).expect(http.StatusOK)
	if got.str("status") != "ready" || got.num("latest.value") != 45 || got.length("needs") != 0 ||
		got.str("norm.ageGroup") != "40-49" || got.str("norm.sex") != "male" || got.num("norm.percentileLow") != 70 ||
		got.num("norm.percentileHigh") != 80 || got.at("norm.median") != 35.3 || got.str("norm.source") == "" {
		t.Fatalf("ready = %s", got.Body)
	}

	h.patch("/api/me", nadia.Token, obj{"birthYear": 2010, "sex": "female"}).expect(http.StatusOK)
	young := h.get("/api/health/cardio", nadia.Token).expect(http.StatusOK)
	if young.str("status") != "age_out_of_range" || young.num("latest.value") != 30 || !young.isNull("norm") {
		t.Fatalf("under 20 = %s", young.Body)
	}

	h.get("/api/health/cardio", "").expect(http.StatusUnauthorized)
}
