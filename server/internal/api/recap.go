package api

import (
	"net/http"
	"time"

	"github.com/nc1107/new-me/server/internal/recap"
	"github.com/nc1107/new-me/server/internal/score"
)

// handleRecap answers the weekly recap for both people. Without ?week= it is the last completed
// week, except from Sunday 19:00 on, when it is the week that is about to end, so the Sunday
// push opens on the week it talks about.
func (s *Server) handleRecap(w http.ResponseWriter, r *http.Request) {
	c := callerFrom(r)
	now := s.now()
	today := score.LocalToday(now, c.loc)
	thisWeek := score.WeekStart(today)
	firstWeek := score.WeekStart(c.user.JoinedOn)

	monday := thisWeek.AddDays(-7)
	if local := now.In(c.loc); local.Weekday() == time.Sunday && local.Hour() >= recap.PushHour {
		monday = thisWeek
	}
	if raw := r.URL.Query().Get("week"); raw != "" {
		parsed, err := score.ParseISOWeek(raw)
		if err != nil {
			fail(w, r, invalid("week must be an ISO week like 2026-W45"))
			return
		}
		if parsed.After(thisWeek) || parsed.Before(firstWeek) {
			fail(w, r, invalid("week must be between the week you joined and this week"))
			return
		}
		monday = parsed
	} else if monday.Before(firstWeek) {
		monday = thisWeek
	}

	out, err := s.recap.Build(r.Context(), monday, today)
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}
