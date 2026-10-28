package api

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/sched"
)

// compareWeek fails when anyone's recap points differ from the board's week for the same week,
// or when the pair is not the sum of the people.
func compareWeek(t *testing.T, h *harness, viewer person, week string) {
	t.Helper()
	board := h.get("/api/board", viewer.Token).expect(http.StatusOK)
	recap := h.get("/api/recap?week="+week, viewer.Token).expect(http.StatusOK)
	sum := 0
	for i := range board.length("users") {
		id := board.num("users." + itoa(i) + ".id")
		for j := range recap.length("people") {
			if recap.num("people."+itoa(j)+".userId") != id {
				continue
			}
			bp, rp := board.num("users."+itoa(i)+".week.points"), recap.num("people."+itoa(j)+".this.points")
			if bp != rp {
				t.Errorf("user %v: board week %v, recap %v\nboard %s\nrecap %s", id, bp, rp, board.Body, recap.Body)
			}
			sum += rp
		}
	}
	if pair := recap.num("pair.this.points"); pair != sum {
		t.Errorf("pair %v, people add up to %v", pair, sum)
	}
}

func TestRecapPointsMatchTheBoardWeek(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.November, 2, 9, 0))
	nick, nadia := h.pair()
	h.clock.Set(ny(2026, time.November, 4, 12, 0))
	h.logActivity(nadia, "pushups", "reps", 30).expect(http.StatusCreated)
	h.logActivity(nick, "pushups", "reps", 30).expect(http.StatusCreated)
	h.get("/api/today", nadia.Token).expect(http.StatusOK)

	compareWeek(t, h, nick, "2026-W45")
	compareWeek(t, h, nadia, "2026-W45")

	// A day finalized by the scheduler is not counted a second time.
	h.clock.Set(ny(2026, time.November, 8, 22, 0))
	s := &sched.Scheduler{DB: h.db, Now: h.clock.Now}
	if err := s.RunOnce(context.Background()); err != nil {
		t.Fatal(err)
	}
	compareWeek(t, h, nadia, "2026-W45")
}

// The board's week is clipped to the season and stops at the person's local today, so the
// recap of that week must leave out days before the season began and days still to come, which
// a zone change can leave behind.
func TestRecapWeekIsClippedLikeTheBoard(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.November, 2, 9, 0))
	nick, nadia := h.pair()
	if _, err := h.db.Pool.Exec(context.Background(), `UPDATE seasons SET starts_on = '2026-11-04' WHERE name = 'Season 0'`); err != nil {
		t.Fatal(err)
	}
	h.clock.Set(ny(2026, time.November, 5, 12, 0))
	h.storeScore(nadia, "2026-11-02", 110, 0, 400)
	h.storeScore(nadia, "2026-11-04", 110, 0, 400)
	h.storeScore(nadia, "2026-11-07", 110, 0, 400)
	h.storeScore(nick, "2026-11-05", 50, 0, 400)

	compareWeek(t, h, nick, "2026-W45")
	recap := h.get("/api/recap?week=2026-W45", nick.Token).expect(http.StatusOK)
	if got := recap.num("pair.this.points"); got != 160 {
		t.Fatalf("pair = %d, want 160\n%s", got, recap.Body)
	}
}
