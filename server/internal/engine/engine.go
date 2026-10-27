// Package engine turns a user-day's stored inputs into a stored score. It is the one place
// that knows how quests map onto logs and Health readings.
package engine

import (
	"context"
	"encoding/json"
	"math"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/score"
)

// QuestResults measures each snapshotted quest against the day's inputs. Steps stay out of the
// day until the first Health reading has arrived, so a user who has not connected Health is
// not scored against a number they cannot produce.
func QuestResults(quests []db.DayQuest, in db.DayInputs) []score.QuestResult {
	results := make([]score.QuestResult, 0, len(quests))
	for _, q := range quests {
		if q.Key == db.QuestSteps && !in.StepsConnected {
			continue
		}
		actual, target := progress(q, in)
		results = append(results, score.QuestResult{Key: q.Key, Points: q.Points, Actual: actual, Target: target})
	}
	return results
}

// progress returns the quest's actual and target in one shared unit.
func progress(q db.DayQuest, in db.DayInputs) (actual, target int) {
	switch q.Key {
	case db.QuestSteps:
		return wholeUnits(in.Steps), q.Target
	case db.QuestPushups:
		return in.Pushups, q.Target
	case db.QuestReading:
		if q.TargetAlt == nil {
			return in.ReadingMinutes, q.Target
		}
		return score.ReadingProgressBasis(in.ReadingMinutes, in.ReadingPages, q.Target, *q.TargetAlt)
	case db.QuestMealsLogged:
		return in.Meals, q.Target
	case db.QuestProtein:
		return tenthsOfGrams(in.ProteinG), q.Target * 10
	case db.QuestYoga:
		return in.YogaMinutes, q.Target
	}
	return 0, q.Target
}

// wholeUnits rounds down so a fractional reading never earns a unit it has not reached.
func wholeUnits(v float64) int { return int(math.Floor(v)) }

// tenthsOfGrams is the amount in the tenths of a gram that meals are stored in, so protein is
// scored on exactly what was logged.
func tenthsOfGrams(g float64) int { return int(math.Round(g * 10)) }

// Actuals is how far the user got on a quest in the quest's own units: for reading, minutes and
// pages separately. It is what the Today screen shows beside the target.
func Actuals(q db.DayQuest, in db.DayInputs) (actual int, actualAlt *int) {
	switch q.Key {
	case db.QuestSteps:
		return wholeUnits(in.Steps), nil
	case db.QuestPushups:
		return in.Pushups, nil
	case db.QuestReading:
		return in.ReadingMinutes, &in.ReadingPages
	case db.QuestMealsLogged:
		return in.Meals, nil
	case db.QuestProtein:
		return wholeUnits(in.ProteinG), nil
	case db.QuestYoga:
		return in.YogaMinutes, nil
	}
	return 0, nil
}

// Scored is one stored day together with the snapshot and inputs it was scored from.
type Scored struct {
	Row    db.DayScoreRow
	Quests []db.DayQuest
	Inputs db.DayInputs
	Score  score.DayScore
}

// RecomputeDay rescores one user-day inside the caller's write transaction and stores the
// result. It takes the day lock first, so concurrent writers to the same day queue behind
// each other and each scores from the other's committed inputs.
func RecomputeDay(ctx context.Context, tx pgx.Tx, userID int64, date score.Date, loc *time.Location) (db.DayScoreRow, error) {
	return RecomputeDayAt(ctx, tx, userID, date, loc, time.Now())
}

// RecomputeDayAt is RecomputeDay with an explicit clock. A day whose grace window has ended
// by now is finalized as it is stored.
func RecomputeDayAt(ctx context.Context, tx pgx.Tx, userID int64, date score.Date, loc *time.Location, now time.Time) (db.DayScoreRow, error) {
	scored, err := ScoreAt(ctx, tx, userID, date, loc, now)
	return scored.Row, err
}

// ScoreAt is RecomputeDayAt that also returns what the score was computed from.
func ScoreAt(ctx context.Context, tx pgx.Tx, userID int64, date score.Date, loc *time.Location, now time.Time) (Scored, error) {
	if err := db.LockUserDay(ctx, tx, userID, date); err != nil {
		return Scored{}, err
	}
	if err := db.EnsureSnapshot(ctx, tx, userID, date); err != nil {
		return Scored{}, err
	}
	quests, err := db.GetDayQuests(ctx, tx, userID, date)
	if err != nil {
		return Scored{}, err
	}
	inputs, err := db.LoadDayInputs(ctx, tx, userID, date)
	if err != nil {
		return Scored{}, err
	}

	day := score.ScoreDay(QuestResults(quests, inputs))
	detail, err := json.Marshal(day.Quests)
	if err != nil {
		return Scored{}, err
	}
	finalize := !now.Before(score.FinalizeAt(date, loc))
	row, err := db.UpsertDayScore(ctx, tx, db.DayScoreRow{
		UserID:      userID,
		LocalDate:   date,
		BasePoints:  day.BasePoints,
		BonusPoints: day.BonusPoints,
		MaxBase:     day.MaxBase,
		Percent:     day.Percent,
		Counted:     day.Counted,
		Detail:      detail,
	}, finalize)
	if err != nil {
		return Scored{}, err
	}
	return Scored{Row: row, Quests: quests, Inputs: inputs, Score: day}, nil
}

// StreakFor derives the user's current streak from their stored days. A day with no stored
// row, including the join day if it was never scored, counts as a miss.
func StreakFor(ctx context.Context, q db.Querier, user db.User, now time.Time, loc *time.Location) (score.StreakResult, error) {
	today := score.LocalToday(now, loc)
	rows, err := db.ListDayScores(ctx, q, user.ID, user.JoinedOn, today)
	if err != nil {
		return score.StreakResult{}, err
	}
	days := make([]score.DayFlag, 0, len(rows)+1)
	if len(rows) == 0 || rows[0].LocalDate.After(user.JoinedOn) {
		days = append(days, score.DayFlag{Date: user.JoinedOn})
	}
	for _, r := range rows {
		days = append(days, score.DayFlag{Date: r.LocalDate, Counted: r.Counted})
	}
	return score.StreakNow(days, now, loc), nil
}
