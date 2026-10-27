package engine

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/readiness"
	"github.com/nc1107/new-me/server/internal/score"
)

// StreakInput gathers what the person's streak is derived from: their stored days, away spans
// and covers. A finalized day that has not been settled yet is decided with its readiness
// morning, so what is shown matches what settling will record.
func StreakInput(ctx context.Context, q db.Querier, user db.User, now time.Time, loc *time.Location) (score.StreakInput, error) {
	today := score.LocalToday(now, loc)
	rows, err := db.ListDayScores(ctx, q, user.ID, user.JoinedOn, today)
	if err != nil {
		return score.StreakInput{}, err
	}
	spans, err := db.AwaySpansFrom(ctx, q, user.ID, user.JoinedOn)
	if err != nil {
		return score.StreakInput{}, err
	}
	covered, spent, err := db.CoversFor(ctx, q, user.ID)
	if err != nil {
		return score.StreakInput{}, err
	}
	byDate := make(map[score.Date]db.DayScoreRow, len(rows))
	for _, r := range rows {
		byDate[r.LocalDate] = r
	}
	coveredOn := make(map[score.Date]bool, len(covered))
	for _, c := range covered {
		coveredOn[c.Date] = true
	}

	pending := score.PendingDate(now, loc)
	in := score.StreakInput{Today: today, PendingDate: pending, Easy: map[score.Date]bool{}}
	if user.StreakRulesFrom != nil {
		in.RulesFrom = *user.StreakRulesFrom
	}
	for _, c := range spent {
		in.Spends = append(in.Spends, c.Date)
	}
	for d := user.JoinedOn; !d.After(today); d = d.AddDays(1) {
		f := score.DayFlag{Date: d, Covered: coveredOn[d]}
		row, ok := byDate[d]
		if ok {
			f.Counted, f.Settled, f.FrozenReason, f.Away = row.Counted, row.Settled, row.FrozenReason, row.Away
		}
		if !f.Settled {
			for _, s := range spans {
				f.Away = f.Away || s.Contains(d)
			}
		}
		in.Days = append(in.Days, f)
		decidable := !f.Settled && !f.Counted && !f.Away && d != today && d != pending && d >= in.RulesFrom
		if decidable {
			res, err := ReadinessOn(ctx, q, user.ID, d)
			if err != nil {
				return in, err
			}
			in.Easy[d] = res != nil && res.Level == readiness.LevelEasy
		}
	}
	return in, nil
}

// StreakFor derives the user's streak from their stored days. A day with no stored row,
// including the join day if it was never scored, counts as a miss once its grace window ends.
func StreakFor(ctx context.Context, q db.Querier, user db.User, now time.Time, loc *time.Location) (score.StreakResult, error) {
	in, err := StreakInput(ctx, q, user, now, loc)
	if err != nil {
		return score.StreakResult{}, err
	}
	return score.ComputeStreak(in), nil
}

// SharedStreakFor derives the couple's streak from each person's own result. With fewer than
// two people there is no couple, so it is zero.
func SharedStreakFor(users []db.User, results map[int64]score.StreakResult, now time.Time) score.SharedResult {
	if len(users) < 2 {
		return score.SharedResult{}
	}
	var from, today score.Date
	people := make([]map[score.Date]score.DayOutcome, 0, len(users))
	for _, u := range users {
		res, ok := results[u.ID]
		if !ok {
			return score.SharedResult{}
		}
		people = append(people, res.Days)
		from = max(from, u.JoinedOn)
		loc, err := u.Location()
		if err != nil {
			return score.SharedResult{}
		}
		today = max(today, score.LocalToday(now, loc))
	}
	return score.SharedStreak(people, from, today)
}

// SettleStreaks records the outcome of every finalized day that has none yet, oldest first. A
// settled day is final: later changes to freezes or schedule never reach it. A cover on a day
// that ended up counted or away is dropped, which gives the freeze back.
func SettleStreaks(ctx context.Context, q db.Querier, user db.User, now time.Time, loc *time.Location) error {
	today := score.LocalToday(now, loc)
	rows, err := db.ListDayScores(ctx, q, user.ID, user.JoinedOn, today)
	if err != nil {
		return err
	}
	var open []db.DayScoreRow
	for _, r := range rows {
		if r.FinalizedAt != nil && !r.Settled {
			open = append(open, r)
		}
	}
	if len(open) == 0 {
		return nil
	}
	res, err := StreakFor(ctx, q, user, now, loc)
	if err != nil {
		return err
	}
	for _, r := range open {
		o := res.Outcome(r.LocalDate)
		reason := ""
		if o.Status == score.StatusFrozen {
			reason = o.Reason
		}
		if err := db.SettleDay(ctx, q, user.ID, r.LocalDate, reason, o.Status == score.StatusAway); err != nil {
			return err
		}
		if o.Status == score.StatusCounted || o.Status == score.StatusAway {
			if err := db.DeleteCover(ctx, q, user.ID, r.LocalDate); err != nil {
				return err
			}
		}
	}
	return nil
}

// Repair is the open window to repair yesterday.
type Repair struct {
	Date  score.Date
	Until time.Time
}

// RepairFor returns the repair window of the person's yesterday, or nil when yesterday was
// counted, frozen, away, still open, or the window has closed.
func RepairFor(res score.StreakResult, user db.User, now time.Time, loc *time.Location) *Repair {
	yesterday := score.LocalToday(now, loc).AddDays(-1)
	if yesterday.Before(user.JoinedOn) || res.Outcome(yesterday).Status != score.StatusMissed {
		return nil
	}
	if !score.RepairOpen(yesterday, now, loc) {
		return nil
	}
	return &Repair{Date: yesterday, Until: score.RepairUntil(yesterday, loc)}
}

// ApplyRepair repairs yesterday when today has reached 100% of its base points inside the
// repair window. The missed day becomes a frozen day and no freeze is spent.
func ApplyRepair(ctx context.Context, q db.Querier, user db.User, now time.Time, loc *time.Location) (bool, error) {
	today := score.LocalToday(now, loc)
	todayRow, err := db.GetDayScore(ctx, q, user.ID, today)
	if errors.Is(err, db.ErrNotFound) || (err == nil && todayRow.Percent < 100) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	// Most of the day's rescores happen with yesterday long settled, so look at its row before
	// deriving the whole streak.
	yesterday := today.AddDays(-1)
	yRow, err := db.GetDayScore(ctx, q, user.ID, yesterday)
	switch {
	case errors.Is(err, db.ErrNotFound):
		return false, nil
	case err != nil:
		return false, err
	case yRow.Counted || yRow.Away || yRow.FrozenReason != "" || !score.RepairOpen(yesterday, now, loc):
		return false, nil
	}
	res, err := StreakFor(ctx, q, user, now, loc)
	if err != nil {
		return false, err
	}
	repair := RepairFor(res, user, now, loc)
	if repair == nil {
		return false, nil
	}
	// A day that finalized but was not settled yet gets its plain outcome first, so the repair
	// is recorded on top of a real miss.
	if err := db.SettleDay(ctx, q, user.ID, repair.Date, "", false); err != nil {
		return false, err
	}
	return db.RepairDay(ctx, q, user.ID, repair.Date)
}

// ApplyRepairTx is ApplyRepair for the caller's transaction, loading the user itself.
func ApplyRepairTx(ctx context.Context, tx pgx.Tx, userID int64, now time.Time, loc *time.Location) error {
	user, err := db.GetUser(ctx, tx, userID)
	if err != nil {
		return err
	}
	_, err = ApplyRepair(ctx, tx, user, now, loc)
	return err
}
