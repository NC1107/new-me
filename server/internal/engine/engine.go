// Package engine turns a user-day's stored inputs into a stored score. It is the one place
// that knows how quests map onto logs and Health readings.
package engine

import (
	"context"
	"encoding/json"
	"errors"
	"math"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/score"
)

// healthMetric maps each Health-fed quest to the metric that feeds it.
var healthMetric = map[string]string{
	db.QuestSteps:    db.MetricSteps,
	db.QuestExercise: db.MetricExercise,
	db.QuestSleep:    db.MetricSleep,
	db.QuestWater:    db.MetricWater,
}

// QuestResults measures each snapshotted quest against the day's inputs. A Health-fed quest
// stays out of the day until its metric has been synced once, so a user who has not shared it
// is not scored against a number they cannot produce.
func QuestResults(quests []db.DayQuest, in db.DayInputs) []score.QuestResult {
	results := make([]score.QuestResult, 0, len(quests))
	for _, q := range quests {
		if metric, fed := healthMetric[q.Key]; fed && !connected(q.Key, metric, in) {
			continue
		}
		actual, target := progress(q, in)
		results = append(results, score.QuestResult{Key: q.Key, Points: q.Points, Actual: actual, Target: target})
	}
	return results
}

// connected is whether a Health-fed quest has data to be measured against. Manual activity is
// data for the exercise quest, so someone who logs a run by hand is scored on it before Health
// has ever reported exercise minutes. Water logged by hand does the same for the water quest.
func connected(key, metric string, in db.DayInputs) bool {
	switch {
	case in.Connected(metric):
		return true
	case key == db.QuestExercise:
		return in.ManualExerciseMinutes() > 0
	case key == db.QuestWater:
		return in.WaterLoggedML > 0
	}
	return false
}

// healthUnits is the quest's amount from Health, and for exercise the minutes logged by hand.
func healthUnits(key string, in db.DayInputs) int {
	units := wholeUnits(in.Metric(healthMetric[key]))
	switch key {
	case db.QuestExercise:
		units += in.ManualExerciseMinutes()
	case db.QuestWater:
		// Health and the log hold the same water, so the larger of the two is the day's amount;
		// adding them would count a drink twice for someone who records it in both places.
		units = max(units, in.WaterLoggedML)
	}
	return units
}

// progress returns the quest's actual and target in one shared unit.
func progress(q db.DayQuest, in db.DayInputs) (actual, target int) {
	switch q.Key {
	case db.QuestSteps, db.QuestExercise, db.QuestSleep, db.QuestWater:
		return healthUnits(q.Key, in), q.Target
	case db.QuestPushups:
		actual, _ = score.StrengthProgress(in.Pushups, q.Target, in.TrainingSession, in.Workouts, in.HIITMinHR)
		return actual, q.Target
	case db.QuestReading:
		minutes := score.ReadingMinutes(in.ReadingMinutes, in.ListeningMinutes)
		if q.TargetAlt == nil {
			return minutes, q.Target
		}
		return score.ReadingProgressBasis(minutes, in.ReadingPages, q.Target, *q.TargetAlt)
	case db.QuestMealsLogged:
		return in.Meals, q.Target
	case db.QuestProtein:
		return tenthsOfGrams(in.ProteinG), q.Target * 10
	case db.QuestYoga:
		actual, _ = score.YogaProgress(in.YogaMinutes, in.Workouts)
		return actual, q.Target
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
	case db.QuestSteps, db.QuestExercise, db.QuestSleep, db.QuestWater:
		return healthUnits(q.Key, in), nil
	case db.QuestPushups:
		return in.Pushups, nil
	case db.QuestReading:
		return score.ReadingMinutes(in.ReadingMinutes, in.ListeningMinutes), &in.ReadingPages
	case db.QuestMealsLogged:
		return in.Meals, nil
	case db.QuestProtein:
		return wholeUnits(in.ProteinG), nil
	case db.QuestYoga:
		actual, _ = score.YogaProgress(in.YogaMinutes, in.Workouts)
		return actual, nil
	}
	return 0, nil
}

// DoneBy names the Health workout that completed the quest, or nil when the quest was done by
// logged entries or is not done. Push-ups completed by a workout and yoga that needed workout
// minutes to reach its target are the two cases.
func DoneBy(q db.DayQuest, in db.DayInputs) *score.DoneBy {
	switch q.Key {
	case db.QuestPushups:
		if _, by := score.StrengthProgress(in.Pushups, q.Target, in.TrainingSession, in.Workouts, in.HIITMinHR); by != nil {
			return by
		}
	case db.QuestYoga:
		if in.YogaMinutes >= q.Target {
			return nil
		}
		if actual, by := score.YogaProgress(in.YogaMinutes, in.Workouts); actual >= q.Target {
			return by
		}
	}
	return nil
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
	day, err = withHabitsAndBonus(ctx, tx, userID, date, day)
	if err != nil {
		return Scored{}, err
	}
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
	if date == score.LocalToday(now, loc) && row.Percent == 100 {
		if err := ApplyRepairTx(ctx, tx, userID, now, loc); err != nil {
			return Scored{}, err
		}
	}
	return Scored{Row: row, Quests: quests, Inputs: inputs, Score: day}, nil
}

// withHabitsAndBonus adds what does not come from quests: the due habits' worth (which counts
// toward the daily goal) and the weekly challenge award. A finalized day keeps everything it was
// finalized with, so editing or deleting a habit later can never change history.
func withHabitsAndBonus(ctx context.Context, tx pgx.Tx, userID int64, date score.Date, day score.DayScore) (score.DayScore, error) {
	stored, err := db.GetDayScore(ctx, tx, userID, date)
	switch {
	case err == nil && stored.FinalizedAt != nil:
		day.BasePoints, day.BonusPoints, day.MaxBase = stored.BasePoints, stored.BonusPoints, stored.MaxBase
		day.Percent, day.Counted = stored.Percent, stored.Counted
		return day, nil
	case err != nil && !errors.Is(err, db.ErrNotFound):
		return day, err
	}
	states, err := db.DueHabits(ctx, tx, userID, date)
	if err != nil {
		return day, err
	}
	award, err := db.ChallengeBonus(ctx, tx, userID, date)
	if err != nil {
		return day, err
	}
	return day.WithHabits(score.HabitScore(db.HabitDays(states))).WithBonus(award), nil
}
