package api

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/sched"
)

// todayAfterPass reads Today the way the app does once the scheduler's milestone pass has run:
// GET /api/today itself no longer records milestones.
func (h *harness) todayAfterPass(path, token string) *response {
	h.t.Helper()
	h.srv.milestones.RunQuietly(context.Background())
	return h.get(path, token)
}

func TestTodayReadDoesNotRecordMilestonesButTheSchedulerDoes(t *testing.T) {
	h := newHarness(t)
	nick, _ := h.pair()
	for i := range 7 {
		h.storeScore(nick, ny(2026, time.November, 2+i, 12, 0).Format(time.DateOnly), 300, 0, 400)
	}
	h.clock.Set(ny(2026, time.November, 9, 12, 0))

	count := func() (n int) {
		if err := h.db.Pool.QueryRow(context.Background(), `SELECT count(*) FROM milestones`).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return n
	}
	if got := h.get("/api/today", nick.Token).expect(http.StatusOK); got.length("newMilestones") != 0 || count() != 0 {
		t.Fatalf("a read must not record milestones: %s", got.Body)
	}
	s := &sched.Scheduler{DB: h.db, Now: h.clock.Now, Milestones: h.srv.milestones}
	if err := s.RunOnce(context.Background()); err != nil {
		t.Fatal(err)
	}
	if got := h.get("/api/today", nick.Token).expect(http.StatusOK); got.length("newMilestones") == 0 {
		t.Fatalf("the scheduler pass should have recorded them: %s", got.Body)
	}
}
