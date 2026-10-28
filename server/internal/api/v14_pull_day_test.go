package api

import (
	"fmt"
	"net/http"
	"testing"
	"time"
)

func TestARestDayCanPullAPlanDayIntoToday(t *testing.T) {
	h, _, nick := trainingHarness(t, planReply(2))
	h.put("/api/training/profile", nick.Token, beginnerProfile).expect(http.StatusOK)
	h.post("/api/training/plan", nick.Token, obj{}).expect(http.StatusCreated)

	h.post("/api/training/today/pull", nick.Token, obj{"dayIndex": 1}).
		expect(http.StatusConflict).code("session_exists")

	h.clock.Set(ny(2026, time.November, 3, 12, 0))
	h.post("/api/training/today/pull", nick.Token, obj{}).expect(http.StatusUnprocessableEntity)
	h.post("/api/training/today/pull", nick.Token, obj{"dayIndex": 2}).expect(http.StatusUnprocessableEntity)
	pulled := h.post("/api/training/today/pull", nick.Token, obj{"dayIndex": 1}).expect(http.StatusOK)
	if !pulled.flag("restDay") || pulled.str("session.label") != "Full body B" || pulled.str("session.date") != "2026-11-03" {
		t.Fatalf("pulled = %s", pulled.Body)
	}
	h.post("/api/training/today/pull", nick.Token, obj{"dayIndex": 1}).expect(http.StatusOK)
	h.post("/api/training/today/pull", nick.Token, obj{"dayIndex": 0}).
		expect(http.StatusConflict).code("session_exists")

	again := h.get("/api/training/today", nick.Token).expect(http.StatusOK)
	if again.num("session.id") != pulled.num("session.id") {
		t.Fatalf("the rest day keeps the pulled session: %s", again.Body)
	}
	h.post(fmt.Sprintf("/api/training/sessions/%d/complete", pulled.num("session.id")), nick.Token, obj{}).
		expect(http.StatusOK)

	h.clock.Set(ny(2026, time.November, 4, 12, 0))
	if r := h.get("/api/training/today", nick.Token).expect(http.StatusOK); !r.flag("restDay") || !r.isNull("session") {
		t.Fatalf("the next rest day starts empty: %s", r.Body)
	}
	h.clock.Set(ny(2026, time.November, 5, 12, 0))
	if r := h.get("/api/training/today", nick.Token).expect(http.StatusOK); r.str("session.label") != "Full body B" {
		t.Fatalf("Thursday still has its own session: %s", r.Body)
	}
}
