package api

import (
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/score"
)

const (
	defaultQuestHistoryDays = 7
	maxQuestHistoryDays     = 31
)

var errNoQuest = newErr(http.StatusNotFound, codeNotFound, "no such quest")

// questDayJSON is one day of a quest's history. Tracked is false when the quest was not in that
// day's snapshot (switched off, or before the person joined), so the app can say so instead of
// showing a miss.
type questDayJSON struct {
	Date    score.Date `json:"date"`
	Tracked bool       `json:"tracked"`
	Actual  int        `json:"actual"`
	Target  int        `json:"target"`
	Unit    string     `json:"unit"`
	Done    bool       `json:"done"`
}

// handleQuestHistory answers GET /api/quests/{key}/history?days=7: the quest's value, target and
// outcome for each of the last days, oldest first, read from the stored snapshots without
// writing anything.
func (s *Server) handleQuestHistory(w http.ResponseWriter, r *http.Request) {
	c := callerFrom(r)
	key := chi.URLParam(r, "key")
	days := defaultQuestHistoryDays
	if raw := r.URL.Query().Get("days"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1 || n > maxQuestHistoryDays {
			fail(w, r, invalid("days must be between 1 and "+strconv.Itoa(maxQuestHistoryDays)))
			return
		}
		days = n
	}
	ctx := r.Context()
	templates, err := db.GetQuestTemplates(ctx, s.db.Pool, c.user.ID)
	if err != nil {
		fail(w, r, err)
		return
	}
	known := false
	for _, t := range templates {
		known = known || t.Key == key
	}
	if !known {
		fail(w, r, errNoQuest)
		return
	}

	today := score.LocalToday(s.now(), c.loc)
	out := make([]questDayJSON, 0, days)
	for i := days - 1; i >= 0; i-- {
		date := today.AddDays(-i)
		if date.Before(c.user.JoinedOn) {
			continue
		}
		item, err := s.questDay(r, c.user.ID, key, date)
		if err != nil {
			fail(w, r, err)
			return
		}
		out = append(out, item)
	}
	writeJSON(w, http.StatusOK, map[string]any{"key": key, "days": out})
}

func (s *Server) questDay(r *http.Request, userID int64, key string, date score.Date) (questDayJSON, error) {
	ctx := r.Context()
	item := questDayJSON{Date: date}
	quests, err := db.GetDayQuests(ctx, s.db.Pool, userID, date)
	if err != nil {
		return item, err
	}
	for _, q := range quests {
		if q.Key != key {
			continue
		}
		inputs, err := db.LoadDayInputs(ctx, s.db.Pool, userID, date)
		if err != nil {
			return item, err
		}
		actual, _ := engine.Actuals(q, inputs)
		item.Tracked = true
		item.Actual = actual
		item.Target = q.Target
		item.Unit = q.Unit
		// A Health quest without data yet is left out of scoring, so it is simply not done.
		scored := score.ScoreDay(engine.QuestResults([]db.DayQuest{q}, inputs))
		item.Done = len(scored.Quests) == 1 && scored.Quests[0].Complete
		break
	}
	return item, nil
}
