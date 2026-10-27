package api

import (
	"fmt"
	"math"
	"net/http"
	"slices"
	"time"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/score"
)

const (
	maxHealthItems = 50
	maxSourceLen   = 32
	// clockSkew is how far ahead of the server a device clock may run before its reading is
	// refused. A far-future measuredAt would win every later conflict and freeze the day.
	clockSkew = 5 * time.Minute
)

// healthLimits bound a daily reading per metric, matching the table check.
var healthLimits = map[string]float64{
	db.MetricSteps:        200000,
	db.MetricActiveEnergy: 20000,
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

// checkHealthItem returns the item's date and why it is unacceptable, if it is.
func (s *Server) checkHealthItem(c caller, item healthItem, now time.Time) (score.Date, *itemError) {
	reject := func(code, msg string) (score.Date, *itemError) {
		return "", &itemError{Code: code, Error: msg}
	}
	date, err := score.ParseDate(item.Date)
	if err != nil {
		return reject(codeInvalidRequest, "date must be YYYY-MM-DD")
	}
	maxValue, ok := healthLimits[item.Metric]
	if !ok {
		return reject(codeInvalidRequest, "metric must be steps or active_energy")
	}
	if math.IsNaN(item.Value) || item.Value < 0 || item.Value > maxValue {
		return reject(codeInvalidRequest, fmt.Sprintf("%s must be between 0 and %g", item.Metric, maxValue))
	}
	if n := utf8.RuneCountInString(item.Source); n < 1 || n > maxSourceLen || hasControlChars(item.Source) {
		return reject(codeInvalidRequest, "source must be 1 to 32 characters")
	}
	if item.MeasuredAt.IsZero() || item.MeasuredAt.After(now.Add(clockSkew)) {
		return reject(codeInvalidRequest, "measuredAt must be a past instant")
	}
	if !s.writable(c.user, c.loc, date) {
		return reject(codeDateClosed, errDateClosed.msg)
	}
	return date, nil
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
