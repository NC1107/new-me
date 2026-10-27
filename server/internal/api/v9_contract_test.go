package api

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// TestWriteV9Contract records real v9 responses as the app's contract fixtures. It runs only
// with NEWME_CONTRACT_DIR set (app/test/contract_v9), so fixtures change only on purpose.
func TestWriteV9Contract(t *testing.T) {
	dir := os.Getenv("NEWME_CONTRACT_DIR")
	if dir == "" {
		t.Skip("NEWME_CONTRACT_DIR is unset")
	}
	write := func(name string, r *response) {
		t.Helper()
		var out bytes.Buffer
		if err := json.Indent(&out, r.Body, "", "  "); err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		out.WriteByte('\n')
		if err := os.WriteFile(filepath.Join(dir, name+".json"), out.Bytes(), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}

	h, _, nick := trainingHarness(t, planReply(1), planReply(1), planReply(2))
	write("training_today_none", h.get("/api/training/today", nick.Token).expect(http.StatusOK))
	write("training_profile_empty", h.get("/api/training/profile", nick.Token).expect(http.StatusOK))
	write("training_profile", h.put("/api/training/profile", nick.Token, beginnerProfile).expect(http.StatusOK))
	write("plan_invalid", h.post("/api/training/plan", nick.Token, obj{}).expect(http.StatusUnprocessableEntity))
	write("plan", h.post("/api/training/plan", nick.Token, obj{}).expect(http.StatusCreated))

	today := h.get("/api/training/today", nick.Token).expect(http.StatusOK)
	id := today.num("session.id")
	write("set_created", h.post("/api/sets", nick.Token, obj{"clientOpId": h.nextOp(), "exercise": "db_row",
		"reps": 10, "loadKg": 20, "rir": 2, "sessionId": id}).expect(http.StatusCreated))
	h.post("/api/sets", nick.Token, obj{"clientOpId": h.nextOp(), "exercise": "plank", "seconds": 45}).
		expect(http.StatusCreated)
	write("training_today", h.get("/api/training/today", nick.Token).expect(http.StatusOK))
	write("max_test", h.post("/api/exercises/pull_up/max", nick.Token, obj{"reps": 6}).expect(http.StatusCreated))
	write("exercises", h.get("/api/exercises", nick.Token).expect(http.StatusOK))
	write("sets", h.get("/api/sets?days=7", nick.Token).expect(http.StatusOK))
	write("session_complete", h.post(fmt.Sprintf("/api/training/sessions/%d/complete", id), nick.Token, obj{}).
		expect(http.StatusOK))
	write("training_progress", h.get("/api/training/progress", nick.Token).expect(http.StatusOK))
	write("lookback_lifts", h.get("/api/lookback?month=2026-11", nick.Token).expect(http.StatusOK))

	h.clock.Set(ny(2026, time.November, 3, 12, 0))
	write("training_today_rest", h.get("/api/training/today", nick.Token).expect(http.StatusOK))
}
