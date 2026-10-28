package api

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/regularity"
	"github.com/nc1107/new-me/server/internal/score"
)

// questJSON is one quest of a day. Points is what the quest is worth in full; BasePoints and
// BonusPoints are what has been earned so far.
type questJSON struct {
	Key         string  `json:"key"`
	Title       string  `json:"title"`
	Target      int     `json:"target"`
	Unit        string  `json:"unit"`
	TargetAlt   *int    `json:"targetAlt"`
	UnitAlt     *string `json:"unitAlt"`
	Actual      int     `json:"actual"`
	ActualAlt   *int    `json:"actualAlt"`
	Points      int     `json:"points"`
	BasePoints  int     `json:"basePoints"`
	BonusPoints int     `json:"bonusPoints"`
	Done        bool    `json:"done"`
	// DoneBy says which Health workout or planned session completed the quest; null when logged
	// entries did.
	DoneBy *score.DoneBy `json:"doneBy"`
	// Detail is extra, quest-specific facts: the steady bedtime sends the night against the
	// person's usual times. Absent for every other quest.
	Detail map[string]any `json:"detail,omitempty"`
}

// dayJSON is the score of a day. StreakLine is the percent a day needs to count.
type dayJSON struct {
	BasePoints  int  `json:"basePoints"`
	BonusPoints int  `json:"bonusPoints"`
	Points      int  `json:"points"`
	MaxBase     int  `json:"maxBase"`
	Percent     int  `json:"percent"`
	GoalPercent int  `json:"goalPercent"`
	Counted     bool `json:"counted"`
	StreakLine  int  `json:"streakLine"`
}

// dayDetailJSON is a day with its date and quests, what write endpoints return.
type dayDetailJSON struct {
	Date score.Date `json:"date"`
	dayJSON
	Quests []questJSON `json:"quests"`
}

func toDayJSON(s engine.Scored) dayJSON {
	return dayJSON{
		BasePoints:  s.Row.BasePoints,
		BonusPoints: s.Row.BonusPoints,
		Points:      s.Row.Points(),
		MaxBase:     s.Row.MaxBase,
		Percent:     s.Row.Percent,
		GoalPercent: score.GoalPercent(s.Row.BasePoints, s.Row.MaxBase),
		Counted:     s.Row.Counted,
		StreakLine:  score.CountedPercent,
	}
}

// toQuestsJSON lists every snapshotted quest. Steps appear before Health is connected, with
// nothing earned, even though they are not part of the day's maximum yet.
func toQuestsJSON(s engine.Scored) []questJSON {
	byKey := make(map[string]score.QuestScore, len(s.Score.Quests))
	for _, q := range s.Score.Quests {
		byKey[q.Key] = q
	}
	out := make([]questJSON, 0, len(s.Quests))
	for _, q := range s.Quests {
		earned := byKey[q.Key]
		actual, actualAlt := engine.Actuals(q, s.Inputs)
		item := questJSON{
			Key: q.Key, Title: titles[q.Key], Target: q.Target, Unit: q.Unit,
			TargetAlt: q.TargetAlt, UnitAlt: q.UnitAlt, Actual: actual, ActualAlt: actualAlt,
			Points: q.Points, BasePoints: earned.Base, BonusPoints: earned.Bonus, Done: earned.Complete,
		}
		if earned.Complete {
			item.DoneBy = engine.DoneBy(q, s.Inputs)
		}
		if q.Key == db.QuestSleepRegularity {
			item.Detail = regularityDetail(engine.RegularityCheck(q, s.Inputs))
		}
		out = append(out, item)
	}
	return out
}

func toDayDetailJSON(date score.Date, s engine.Scored) dayDetailJSON {
	return dayDetailJSON{Date: date, dayJSON: toDayJSON(s), Quests: toQuestsJSON(s)}
}

// scoreDay rescores a day in the caller's transaction on the server clock.
func (s *Server) scoreDay(ctx context.Context, tx pgx.Tx, c caller, date score.Date) (engine.Scored, error) {
	return engine.ScoreAt(ctx, tx, c.user.ID, date, c.loc, s.now())
}

// writable is the day window: today, or yesterday while the grace hour has not passed, and
// never a day before the user joined.
func (s *Server) writable(u db.User, loc *time.Location, date score.Date) bool {
	return !date.Before(u.JoinedOn) && score.DateAllowed(date, s.now(), loc).Open()
}

// openDates are the days a write may still touch, which is where snapshots must be frozen
// before a template changes.
func (s *Server) openDates(u db.User, loc *time.Location) []score.Date {
	today := score.LocalToday(s.now(), loc)
	dates := []score.Date{today.AddDays(-1), today}
	out := dates[:0]
	for _, d := range dates {
		if s.writable(u, loc, d) {
			out = append(out, d)
		}
	}
	return out
}

// backdateUntil is the instant yesterday closes, or nil when it is closed or predates the user.
func (s *Server) backdateUntil(u db.User, loc *time.Location) *string {
	until, open := score.BackdateUntil(s.now(), loc)
	yesterday := score.LocalToday(s.now(), loc).AddDays(-1)
	if !open || yesterday.Before(u.JoinedOn) {
		return nil
	}
	ts := wireTime(until)
	return &ts
}

// regularityDetail is the night against the person's usual times: the usual and the night's own
// clock times as minutes after midnight in their zone, and how far off each was.
func regularityDetail(c regularity.Check) map[string]any {
	if !c.Measurable {
		return map[string]any{"measurable": false, "baselineNights": c.BaselineNights, "minBaseline": regularity.MinBaseline}
	}
	return map[string]any{
		"measurable": true, "baselineNights": c.BaselineNights, "windowMin": c.WindowMin,
		"bedMedian": c.BedMedian, "wakeMedian": c.WakeMedian,
		"bedOffset": c.BedOffset, "wakeOffset": c.WakeOffset, "bedOk": c.BedOK, "wakeOk": c.WakeOK,
	}
}
