package api

import (
	"net/http"
	"strings"
	"testing"
)

// easyMorning seeds an HRV baseline and a low reading for Monday 2026-11-02, which makes
// readiness Easy.
func easyMorning(h *harness, nick person) {
	h.seedMetric(nick, "hrv_ms", 1, steady(60, 20)...)
	h.putHealth(nick, "2026-11-02", "hrv_ms", 49.2).expect(http.StatusOK)
}

func easedHarness(t *testing.T) (*harness, person) {
	h, _, nick := trainingHarness(t, planReply(3))
	h.put("/api/training/profile", nick.Token, beginnerProfile).expect(http.StatusOK)
	h.post("/api/training/plan", nick.Token, obj{}).expect(http.StatusCreated)
	return h, nick
}

func TestEasyMorningDropsASetFromEachExercise(t *testing.T) {
	h, nick := easedHarness(t)
	easyMorning(h, nick)

	got := h.get("/api/training/today", nick.Token).expect(http.StatusOK)
	if !got.flag("session.eased") ||
		got.str("session.easedReason") != "Your HRV is below its usual level, so today is one set lighter." {
		t.Fatalf("session = %s", got.Body)
	}
	for i := 0; i < got.length("session.exercises"); i++ {
		p := "session.exercises." + string(rune('0'+i)) + "."
		if got.num(p+"target.sets") != 2 || got.num(p+"plan.sets") != 3 {
			t.Fatalf("each exercise should drop one of three sets: %s", got.Body)
		}
	}
}

func TestSessionIsNotEasedOnANormalMorning(t *testing.T) {
	h, nick := easedHarness(t)
	got := h.get("/api/training/today", nick.Token).expect(http.StatusOK)
	if got.flag("session.eased") || got.str("session.easedReason") != "" ||
		got.num(exerciseAt(t, got, "db_row")+"target.sets") != 3 {
		t.Fatalf("session = %s", got.Body)
	}
}

func TestEasedSessionHoldsLoadInsteadOfProgressing(t *testing.T) {
	h, nick := easedHarness(t)
	// Monday's session: every set at the top of the range, which would add load on Thursday.
	for range 3 {
		h.post("/api/sets", nick.Token, obj{"clientOpId": h.nextOp(), "exercise": "db_row", "reps": 10, "loadKg": 20, "rir": 2}).
			expect(http.StatusCreated)
	}
	h.clock.Set(ny(2026, 11, 5, 12, 0))
	h.seedMetric(nick, "hrv_ms", 1, steady(60, 20)...)
	h.putHealth(nick, "2026-11-05", "hrv_ms", 49.2).expect(http.StatusOK)

	got := h.get("/api/training/today", nick.Token).expect(http.StatusOK)
	row := exerciseAt(t, got, "db_row")
	if !got.flag("session.eased") || got.at(row+"target.loadKg").(float64) != 20 || got.num(row+"target.amount") != 10 ||
		got.num(row+"target.sets") != 2 || !strings.Contains(got.str(row+"reason"), "Held") {
		t.Fatalf("load and reps should hold: %s", got.Body)
	}
}

func TestTakingTheFullSessionSticks(t *testing.T) {
	h, nick := easedHarness(t)
	easyMorning(h, nick)
	if !h.get("/api/training/today", nick.Token).expect(http.StatusOK).flag("session.eased") {
		t.Fatal("precondition: the morning should be eased")
	}

	full := h.post("/api/training/today/full", nick.Token, obj{}).expect(http.StatusOK)
	if full.flag("session.eased") || full.num(exerciseAt(t, full, "db_row")+"target.sets") != 3 {
		t.Fatalf("full session = %s", full.Body)
	}
	again := h.get("/api/training/today", nick.Token).expect(http.StatusOK)
	if again.flag("session.eased") || again.num(exerciseAt(t, again, "db_row")+"target.sets") != 3 {
		t.Fatalf("the choice should stick for the day: %s", again.Body)
	}
}

func TestAStartedSessionKeepsWhatItWasShown(t *testing.T) {
	h, nick := easedHarness(t)
	easyMorning(h, nick)
	if !h.get("/api/training/today", nick.Token).expect(http.StatusOK).flag("session.eased") {
		t.Fatal("precondition: the morning should be eased")
	}
	h.post("/api/sets", nick.Token, obj{"clientOpId": h.nextOp(), "exercise": "db_row", "reps": 6, "loadKg": 20}).
		expect(http.StatusCreated)

	// Readiness recovers after the session started, and the full session is asked for too late.
	h.putHealth(nick, "2026-11-02", "hrv_ms", 62).expect(http.StatusOK)
	for _, got := range []*response{
		h.get("/api/training/today", nick.Token).expect(http.StatusOK),
		h.post("/api/training/today/full", nick.Token, obj{}).expect(http.StatusOK),
	} {
		if !got.flag("session.eased") || got.num(exerciseAt(t, got, "db_row")+"target.sets") != 2 {
			t.Fatalf("a session with logged sets should not change: %s", got.Body)
		}
	}
}

func TestTakeFullSessionOnARestDayIsHarmless(t *testing.T) {
	h, nick := easedHarness(t)
	h.clock.Set(ny(2026, 11, 3, 12, 0))
	got := h.post("/api/training/today/full", nick.Token, obj{}).expect(http.StatusOK)
	if !got.flag("restDay") || !got.isNull("session") {
		t.Fatalf("got %s", got.Body)
	}
}
