package api

import (
	"net/http"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/insights"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/targets"
)

// Statuses of the cardio fitness placement. Each says why the page can or cannot compare.
const (
	cardioReady      = "ready"
	cardioNoReading  = "no_reading"
	cardioNeedsInput = "needs_profile"
	cardioAgeRange   = "age_out_of_range"
)

type cardioJSON struct {
	Status string         `json:"status"`
	Latest *cardioReading `json:"latest"`
	// Needs lists the profile fields still missing for the comparison.
	Needs []string     `json:"needs"`
	Norm  *cardioNorms `json:"norm"`
}

type cardioReading struct {
	Date  score.Date `json:"date"`
	Value float64    `json:"value"`
}

type cardioNorms struct {
	AgeGroup string  `json:"ageGroup"`
	Sex      string  `json:"sex"`
	Low      int     `json:"percentileLow"`
	High     int     `json:"percentileHigh"`
	Median   float64 `json:"median"`
	Source   string  `json:"source"`
}

// handleHealthCardio places the caller's newest VO2 max against the FRIEND norms for their age
// and sex. The series itself comes from the trends endpoint.
func (s *Server) handleHealthCardio(w http.ResponseWriter, r *http.Request) {
	c := callerFrom(r)
	today := score.LocalToday(s.now(), c.loc)
	latest, err := db.LatestHealth(r.Context(), s.db.Pool, c.user.ID, today, []string{"vo2max"})
	if err != nil {
		fail(w, r, err)
		return
	}
	out := cardioJSON{Status: cardioNoReading, Needs: []string{}}
	reading, ok := latest["vo2max"]
	if !ok {
		writeJSON(w, http.StatusOK, out)
		return
	}
	out.Latest = &cardioReading{Date: reading.Date, Value: reading.Value}

	age := insights.AgeOn(today, c.user.BirthYear)
	if age == nil {
		out.Needs = append(out.Needs, "birthYear")
	}
	if c.user.Sex == nil {
		out.Needs = append(out.Needs, "sex")
	}
	if len(out.Needs) > 0 {
		out.Status = cardioNeedsInput
		writeJSON(w, http.StatusOK, out)
		return
	}
	sex := targets.Sex(*c.user.Sex)
	placement, ok := targets.CardioNorms(reading.Value, *age, sex)
	if !ok {
		out.Status = cardioAgeRange
		writeJSON(w, http.StatusOK, out)
		return
	}
	out.Status = cardioReady
	out.Norm = &cardioNorms{AgeGroup: placement.AgeGroup, Sex: string(sex), Low: placement.Low,
		High: placement.High, Median: placement.MedianVO2, Source: targets.CardioSource}
	writeJSON(w, http.StatusOK, out)
}
