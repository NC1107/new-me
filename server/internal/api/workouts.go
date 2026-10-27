package api

import (
	"fmt"
	"net/http"
	"slices"
	"strconv"
	"time"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/insights"
	"github.com/nc1107/new-me/server/internal/score"
)

const (
	maxWorkoutItems = 100
	maxWorkoutDays  = 365
	maxHealthIDLen  = 100
	// maxHistoryDays is how far back a workout or night may be dated. The app sends two weeks;
	// the margin only keeps a stale device clock or a bad payload from writing ancient rows.
	maxHistoryDays = 400
)

// workoutTypes are the activity types the app maps HealthKit onto.
var workoutTypes = []string{
	"walking", "running", "cycling", "strength", "hiit", "yoga", "swimming", "hiking", "dance",
	"climbing", "other",
}

type workoutItem struct {
	ID          string    `json:"id"`
	Type        string    `json:"type"`
	StartedAt   time.Time `json:"startedAt"`
	EndedAt     time.Time `json:"endedAt"`
	DurationMin float64   `json:"durationMin"`
	Kcal        *float64  `json:"kcal"`
	DistanceM   *float64  `json:"distanceM"`
	AvgHR       *float64  `json:"avgHr"`
	Source      string    `json:"source"`
}

type putWorkoutsRequest struct {
	Items []workoutItem `json:"items"`
}

type workoutJSON struct {
	ID          string     `json:"id"`
	Type        string     `json:"type"`
	Date        score.Date `json:"date"`
	StartedAt   string     `json:"startedAt"`
	EndedAt     string     `json:"endedAt"`
	DurationMin float64    `json:"durationMin"`
	Kcal        *float64   `json:"kcal"`
	DistanceM   *float64   `json:"distanceM"`
	AvgHR       *float64   `json:"avgHr"`
}

// inRange checks an optional measurement against its bounds and rounds it to the one decimal
// the table stores.
func inRange(v *float64, lo, hi float64, name string) (*float64, string) {
	if v == nil {
		return nil, ""
	}
	if *v < lo || *v > hi {
		return nil, fmt.Sprintf("%s must be between %g and %g", name, lo, hi)
	}
	r := round1(*v)
	return &r, ""
}

// checkWorkout validates one item and returns the row to store.
func checkWorkout(item workoutItem, loc *time.Location, now time.Time) (db.Workout, string) {
	if n := utf8.RuneCountInString(item.ID); n < 1 || n > maxHealthIDLen || hasControlChars(item.ID) {
		return db.Workout{}, "id must be 1 to 100 characters without control characters"
	}
	if !slices.Contains(workoutTypes, item.Type) {
		return db.Workout{}, "type is not a supported workout type"
	}
	if n := utf8.RuneCountInString(item.Source); n < 1 || n > maxSourceLen || hasControlChars(item.Source) {
		return db.Workout{}, "source must be 1 to 32 characters"
	}
	oldest := now.AddDate(0, 0, -maxHistoryDays)
	switch {
	case item.StartedAt.IsZero() || item.StartedAt.Before(oldest) || item.StartedAt.After(now.Add(clockSkew)):
		return db.Workout{}, "startedAt must be a past instant within the last 400 days"
	case !item.EndedAt.After(item.StartedAt) || item.EndedAt.After(now.Add(clockSkew)):
		return db.Workout{}, "endedAt must be after startedAt and not in the future"
	}
	if item.DurationMin <= 0 || item.DurationMin > 1440 || round1(item.DurationMin) <= 0 {
		return db.Workout{}, "durationMin must be above 0 and at most 1440"
	}
	kcal, msg := inRange(item.Kcal, 0, 20000, "kcal")
	if msg != "" {
		return db.Workout{}, msg
	}
	distance, msg := inRange(item.DistanceM, 0, 1000000, "distanceM")
	if msg != "" {
		return db.Workout{}, msg
	}
	hr, msg := inRange(item.AvgHR, 20, 250, "avgHr")
	if msg != "" {
		return db.Workout{}, msg
	}
	return db.Workout{
		HealthID: item.ID, Type: item.Type, LocalDate: score.LocalToday(item.StartedAt, loc),
		StartedAt: item.StartedAt, EndedAt: item.EndedAt, DurationMin: round1(item.DurationMin),
		Kcal: kcal, DistanceM: distance, AvgHR: hr, Source: item.Source,
	}, ""
}

// rejectedBatch is the 422 for a batch with bad items, listing every one so the app never has
// to guess which half applied.
func rejectedBatch(what string, problems []itemError) *httpError {
	return &httpError{
		status: http.StatusUnprocessableEntity, code: codeInvalidRequest,
		msg: "some " + what + " were rejected", items: problems,
	}
}

// handlePutWorkouts upserts up to 100 workouts by HealthKit id in one transaction. A strength
// or yoga workout can complete a quest, so every still-open day the batch touches is rescored,
// including the day an edited workout moved away from. History older than the day window is
// stored all the same but never rescored.
func (s *Server) handlePutWorkouts(w http.ResponseWriter, r *http.Request) {
	var req putWorkoutsRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	if len(req.Items) < 1 || len(req.Items) > maxWorkoutItems {
		fail(w, r, invalid("items must hold 1 to 100 workouts"))
		return
	}
	c := callerFrom(r)
	now := s.now()
	rows := make([]db.Workout, len(req.Items))
	var problems []itemError
	for i, item := range req.Items {
		row, msg := checkWorkout(item, c.loc, now)
		if msg != "" {
			problems = append(problems, itemError{Index: i, Code: codeInvalidRequest, Error: msg})
			continue
		}
		rows[i] = row
	}
	if problems != nil {
		fail(w, r, rejectedBatch("workouts", problems))
		return
	}
	ctx := r.Context()
	err := s.db.WithTx(ctx, func(tx pgx.Tx) error {
		ids := make([]string, len(rows))
		for i, row := range rows {
			ids[i] = row.HealthID
		}
		moved, err := db.WorkoutDates(ctx, tx, c.user.ID, ids)
		if err != nil {
			return err
		}
		touched := moved
		for _, row := range rows {
			touched = append(touched, row.LocalDate)
		}
		// Ascending order keeps two overlapping batches from locking in opposite orders.
		slices.Sort(touched)
		touched = slices.Compact(touched)
		for _, date := range touched {
			if s.writable(c.user, c.loc, date) {
				if err := db.LockUserDay(ctx, tx, c.user.ID, date); err != nil {
					return err
				}
			}
		}
		for _, row := range rows {
			if err := db.UpsertWorkout(ctx, tx, c.user.ID, row); err != nil {
				return err
			}
		}
		// Only open days are rescored: a finished day keeps the score it was finalized with.
		for _, date := range touched {
			if s.writable(c.user, c.loc, date) {
				if _, err := s.scoreDay(ctx, tx, c, date); err != nil {
					return err
				}
			}
		}
		return nil
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]int{"saved": len(rows)})
}

// handleListWorkouts lists the caller's workouts over the last N local days, newest first,
// with this week's summary.
func (s *Server) handleListWorkouts(w http.ResponseWriter, r *http.Request) {
	days, err := strconv.Atoi(r.URL.Query().Get("days"))
	if err != nil || days < 1 || days > maxWorkoutDays {
		fail(w, r, invalid("days must be between 1 and 365"))
		return
	}
	c := callerFrom(r)
	today := score.LocalToday(s.now(), c.loc)
	weekFrom := score.WeekStart(today)
	rows, err := db.ListWorkouts(r.Context(), s.db.Pool, c.user.ID, minDate(today.AddDays(-(days-1)), weekFrom), today)
	if err != nil {
		fail(w, r, err)
		return
	}
	from := today.AddDays(-(days - 1))
	list := make([]workoutJSON, 0, len(rows))
	forWeek := make([]insights.Workout, 0, len(rows))
	for _, row := range rows {
		forWeek = append(forWeek, insights.Workout{Type: row.Type, Date: row.LocalDate, DurationMin: row.DurationMin})
		if row.LocalDate.Before(from) {
			continue
		}
		list = append(list, workoutJSON{
			ID: row.HealthID, Type: row.Type, Date: row.LocalDate,
			StartedAt: wireTime(row.StartedAt), EndedAt: wireTime(row.EndedAt),
			DurationMin: row.DurationMin, Kcal: row.Kcal, DistanceM: row.DistanceM, AvgHR: row.AvgHR,
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"workouts": list,
		"week":     insights.WeekSummary(forWeek, weekFrom, today),
	})
}

func minDate(a, b score.Date) score.Date {
	if a.Before(b) {
		return a
	}
	return b
}
