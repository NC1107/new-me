package api

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/nc1107/new-me/server/internal/lookback"
	"github.com/nc1107/new-me/server/internal/score"
)

// handleProgress compares each person's rolling window with the one before and with their first
// window, for every tracked metric, with a weekly series for sparklines.
func (s *Server) handleProgress(w http.ResponseWriter, r *http.Request) {
	window := lookback.DefaultWindow
	if raw := r.URL.Query().Get("window"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < lookback.MinWindow || n > lookback.MaxWindow {
			fail(w, r, invalid("window must be between "+strconv.Itoa(lookback.MinWindow)+" and "+strconv.Itoa(lookback.MaxWindow)+" days"))
			return
		}
		window = n
	}
	out, err := s.lookback.BuildProgress(r.Context(), window)
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}

// handleLookback answers the monthly look-back: per person and for the couple, with the three
// biggest improvements. The month defaults to the last completed one.
func (s *Server) handleLookback(w http.ResponseWriter, r *http.Request) {
	c := callerFrom(r)
	today := score.LocalToday(s.now(), c.loc)
	month := r.URL.Query().Get("month")
	if month == "" {
		month = lookback.LastCompletedMonth(today)
	}
	out, err := s.lookback.BuildMonth(r.Context(), month, today)
	if errors.Is(err, lookback.ErrBadMonth) {
		fail(w, r, invalid(err.Error()))
		return
	}
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}
