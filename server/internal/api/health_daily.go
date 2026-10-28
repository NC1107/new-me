package api

import (
	"fmt"
	"math"
	"net/http"
	"slices"
	"strconv"
	"time"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/score"
)

const (
	maxHealthItems = 50
	// maxHistoryItems and maxHealthHistoryDays bound a Health history import batch.
	maxHistoryItems      = 200
	maxHealthHistoryDays = 400
	maxTrendDays         = 365
	maxSourceLen         = 32
	// clockSkew is how far ahead of the server a device clock may run before its reading is
	// refused. A far-future measuredAt would win every later conflict and freeze the day.
	clockSkew = 5 * time.Minute
)

type healthBounds struct{ min, max float64 }

// healthLimits bound a daily reading per metric, matching the table check.
var healthLimits = map[string]healthBounds{
	db.MetricSteps:        {0, 200000},
	db.MetricActiveEnergy: {0, 20000},
	"basal_energy":        {0, 20000},
	db.MetricExercise:     {0, 1440},
	"distance_m":          {0, 200000},
	"flights":             {0, 1000},
	"workouts":            {0, 50},
	"workout_minutes":     {0, 1440},
	db.MetricSleep:        {0, 1440},
	"mindful_minutes":     {0, 1440},
	"water_ml":            {0, 20000},
	"resting_hr":          {20, 250},
	"hrv_ms":              {0, 500},
	"vo2max":              {0, 100},
	"weight_kg":           {20, 400},
	"body_fat_pct":        {1, 80},
	"lean_mass_kg":        {10, 300},
	"height_cm":           {100, 250},
}

type healthItem struct {
	Date       string    `json:"date"`
	Metric     string    `json:"metric"`
	Value      float64   `json:"value"`
	Source     string    `json:"source"`
	MeasuredAt time.Time `json:"measuredAt"`
}

type putHealthRequest struct {
	Items []healthItem `json:"items"`
}

// checkHealthItem returns the item's date and why it is unacceptable, if it is. The date must
// be an open day.
func (s *Server) checkHealthItem(c caller, item healthItem, now time.Time) (score.Date, *itemError) {
	date, problem := checkHealthReading(item, now)
	if problem != nil {
		return date, problem
	}
	if !s.writable(c.user, c.loc, date) {
		return "", &itemError{Code: codeDateClosed, Error: errDateClosed.msg}
	}
	return date, nil
}

// checkHistoryItem is checkHealthItem for history: the date must be closed (before the open
// days) and at most maxHealthHistoryDays back.
func (s *Server) checkHistoryItem(c caller, item healthItem, now time.Time) (score.Date, *itemError) {
	date, problem := checkHealthReading(item, now)
	if problem != nil {
		return date, problem
	}
	today := score.LocalToday(now, c.loc)
	if s.writable(c.user, c.loc, date) || !date.Before(today) || date.Before(today.AddDays(-maxHealthHistoryDays)) {
		return "", &itemError{Code: codeInvalidRequest,
			Error: fmt.Sprintf("history is for closed days up to %d days back; open days go to /api/health/daily", maxHealthHistoryDays)}
	}
	return date, nil
}

// checkHealthReading checks everything about a reading except which days may take it.
func checkHealthReading(item healthItem, now time.Time) (score.Date, *itemError) {
	reject := func(code, msg string) (score.Date, *itemError) {
		return "", &itemError{Code: code, Error: msg}
	}
	date, err := score.ParseDate(item.Date)
	if err != nil {
		return reject(codeInvalidRequest, "date must be YYYY-MM-DD")
	}
	bounds, ok := healthLimits[item.Metric]
	if !ok {
		return reject(codeInvalidRequest, "metric is not a supported Health metric")
	}
	if math.IsNaN(item.Value) || item.Value < bounds.min || item.Value > bounds.max {
		return reject(codeInvalidRequest, fmt.Sprintf("%s must be between %g and %g", item.Metric, bounds.min, bounds.max))
	}
	if n := utf8.RuneCountInString(item.Source); n < 1 || n > maxSourceLen || hasControlChars(item.Source) {
		return reject(codeInvalidRequest, "source must be 1 to 32 characters")
	}
	if item.MeasuredAt.IsZero() || item.MeasuredAt.After(now.Add(clockSkew)) {
		return reject(codeInvalidRequest, "measuredAt must be a past instant")
	}
	return date, nil
}

// handlePutHealthHistory stores Health readings for closed days, only where the day has no
// reading of that metric yet, and never rescores a day: history fills insights and look-backs
// without moving a score that is already settled.
func (s *Server) handlePutHealthHistory(w http.ResponseWriter, r *http.Request) {
	var req putHealthRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	if len(req.Items) < 1 || len(req.Items) > maxHistoryItems {
		fail(w, r, invalid(fmt.Sprintf("items must hold 1 to %d readings", maxHistoryItems)))
		return
	}
	c := callerFrom(r)
	now := s.now()
	dates := make([]score.Date, len(req.Items))
	var problems []itemError
	for i, item := range req.Items {
		date, problem := s.checkHistoryItem(c, item, now)
		if problem != nil {
			problem.Index = i
			problems = append(problems, *problem)
			continue
		}
		dates[i] = date
	}
	if problems != nil {
		fail(w, r, batchError(problems))
		return
	}
	stored := 0
	ctx := r.Context()
	err := s.db.WithTx(ctx, func(tx pgx.Tx) error {
		for i, item := range req.Items {
			added, err := db.InsertHealthHistory(ctx, tx, c.user.ID, dates[i], item.Metric, item.Value,
				item.Source, item.MeasuredAt)
			if err != nil {
				return err
			}
			if added {
				stored++
			}
		}
		return nil
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"stored": stored, "received": len(req.Items)})
}

// handlePutHealthDaily stores up to 50 daily readings in one transaction and returns the
// rescored days. One bad item rejects the batch with a per-item list, so the app never has to
// guess which half applied.
func (s *Server) handlePutHealthDaily(w http.ResponseWriter, r *http.Request) {
	var req putHealthRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	if len(req.Items) < 1 || len(req.Items) > maxHealthItems {
		fail(w, r, invalid("items must hold 1 to 50 readings"))
		return
	}

	c := callerFrom(r)
	now := s.now()
	dates := make([]score.Date, len(req.Items))
	var problems []itemError
	for i, item := range req.Items {
		date, problem := s.checkHealthItem(c, item, now)
		if problem != nil {
			problem.Index = i
			problems = append(problems, *problem)
			continue
		}
		dates[i] = date
	}
	if problems != nil {
		fail(w, r, batchError(problems))
		return
	}

	affected := slices.Clone(dates)
	slices.Sort(affected)
	affected = slices.Compact(affected)

	ctx := r.Context()
	days := make([]dayDetailJSON, 0, len(affected))
	err := s.db.WithTx(ctx, func(tx pgx.Tx) error {
		// Ascending order keeps two overlapping batches from locking in opposite orders.
		for _, date := range affected {
			if err := db.LockUserDay(ctx, tx, c.user.ID, date); err != nil {
				return err
			}
		}
		for i, item := range req.Items {
			if _, err := db.UpsertHealthDaily(ctx, tx, c.user.ID, dates[i], item.Metric, item.Value,
				item.Source, item.MeasuredAt); err != nil {
				return err
			}
		}
		for _, date := range affected {
			scored, err := s.scoreDay(ctx, tx, c, date)
			if err != nil {
				return err
			}
			days = append(days, toDayDetailJSON(date, scored))
		}
		return nil
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"days": days})
}

// batchError reports every bad item. When all of them only missed the day window it carries
// date_closed, which the app already knows how to explain.
func batchError(problems []itemError) *httpError {
	code, msg := codeInvalidRequest, "some readings were rejected"
	if slices.IndexFunc(problems, func(p itemError) bool { return p.Code != codeDateClosed }) < 0 {
		code, msg = codeDateClosed, errDateClosed.msg
	}
	return &httpError{status: http.StatusUnprocessableEntity, code: code, msg: msg, items: problems}
}

// handleHealthTrends returns one metric's daily values for the caller over the last N local
// days ending today. Days without a reading are left out.
func (s *Server) handleHealthTrends(w http.ResponseWriter, r *http.Request) {
	metric := r.URL.Query().Get("metric")
	if _, ok := healthLimits[metric]; !ok {
		fail(w, r, invalid("metric is not a supported Health metric"))
		return
	}
	days, err := strconv.Atoi(r.URL.Query().Get("days"))
	if err != nil || days < 1 || days > maxTrendDays {
		fail(w, r, invalid("days must be between 1 and 365"))
		return
	}
	c := callerFrom(r)
	today := score.LocalToday(s.now(), c.loc)
	points, err := db.HealthSeries(r.Context(), s.db.Pool, c.user.ID, metric, today.AddDays(-(days - 1)), today)
	if err != nil {
		fail(w, r, err)
		return
	}
	out := make([]trendPointJSON, len(points))
	for i, p := range points {
		out[i] = trendPointJSON{Date: p.Date, Value: p.Value}
	}
	writeJSON(w, http.StatusOK, map[string]any{"metric": metric, "points": out})
}

type trendPointJSON struct {
	Date  score.Date `json:"date"`
	Value float64    `json:"value"`
}
