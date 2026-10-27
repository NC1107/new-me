package api

import (
	"math"
	"net/http"
	"time"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/score"
)

const maxSleepNights = 31

// sleepNightItem takes minutes as JSON numbers of any form, since a Dart client may send
// 420.0 for an integer.
type sleepNightItem struct {
	Date      string    `json:"date"`
	BedAt     time.Time `json:"bedAt"`
	WakeAt    time.Time `json:"wakeAt"`
	AsleepMin float64   `json:"asleepMin"`
	DeepMin   float64   `json:"deepMin"`
	REMMin    float64   `json:"remMin"`
	CoreMin   float64   `json:"coreMin"`
	AwakeMin  float64   `json:"awakeMin"`
	Source    string    `json:"source"`
}

type putSleepRequest struct {
	Nights []sleepNightItem `json:"nights"`
}

// wholeMinutes rounds a stage length to a whole minute and says whether it is a day or less.
func wholeMinutes(v float64) (int, bool) {
	if math.IsNaN(v) || v < 0 || v > 1440 {
		return 0, false
	}
	return int(math.Round(v)), true
}

// checkSleepNight validates one night and returns the row to store.
func checkSleepNight(item sleepNightItem, today score.Date, now time.Time) (db.SleepNight, string) {
	date, err := score.ParseDate(item.Date)
	if err != nil {
		return db.SleepNight{}, "date must be YYYY-MM-DD"
	}
	if date.After(today) || date.Before(today.AddDays(-maxHistoryDays)) {
		return db.SleepNight{}, "date must be today or a past day within the last 400 days"
	}
	if n := utf8.RuneCountInString(item.Source); n < 1 || n > maxSourceLen || hasControlChars(item.Source) {
		return db.SleepNight{}, "source must be 1 to 32 characters"
	}
	switch {
	case item.BedAt.IsZero() || item.BedAt.Before(now.AddDate(0, 0, -maxHistoryDays-1)):
		return db.SleepNight{}, "bedAt must be a recent past instant"
	case !item.WakeAt.After(item.BedAt) || item.WakeAt.Sub(item.BedAt) > 24*time.Hour || item.WakeAt.After(now.Add(clockSkew)):
		return db.SleepNight{}, "wakeAt must be after bedAt, within 24 hours of it, and not in the future"
	}
	night := db.SleepNight{Date: date, BedAt: item.BedAt, WakeAt: item.WakeAt, Source: item.Source}
	for _, field := range []struct {
		name string
		in   float64
		out  *int
	}{
		{"asleepMin", item.AsleepMin, &night.AsleepMin}, {"deepMin", item.DeepMin, &night.DeepMin},
		{"remMin", item.REMMin, &night.REMMin}, {"coreMin", item.CoreMin, &night.CoreMin},
		{"awakeMin", item.AwakeMin, &night.AwakeMin},
	} {
		minutes, ok := wholeMinutes(field.in)
		if !ok {
			return db.SleepNight{}, field.name + " must be between 0 and 1440"
		}
		*field.out = minutes
	}
	return night, ""
}

// handlePutSleep upserts up to 31 nights by the morning they end, in one transaction.
func (s *Server) handlePutSleep(w http.ResponseWriter, r *http.Request) {
	var req putSleepRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	if len(req.Nights) < 1 || len(req.Nights) > maxSleepNights {
		fail(w, r, invalid("nights must hold 1 to 31 nights"))
		return
	}
	c := callerFrom(r)
	now := s.now()
	today := score.LocalToday(now, c.loc)
	rows := make([]db.SleepNight, len(req.Nights))
	var problems []itemError
	for i, item := range req.Nights {
		row, msg := checkSleepNight(item, today, now)
		if msg != "" {
			problems = append(problems, itemError{Index: i, Code: codeInvalidRequest, Error: msg})
			continue
		}
		rows[i] = row
	}
	if problems != nil {
		fail(w, r, rejectedBatch("nights", problems))
		return
	}
	err := s.db.WithTx(r.Context(), func(tx pgx.Tx) error {
		for _, row := range rows {
			if err := db.UpsertSleepNight(r.Context(), tx, c.user.ID, row); err != nil {
				return err
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
