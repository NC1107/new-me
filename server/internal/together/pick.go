package together

import (
	"context"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/score"
)

// AwayDaysIn is how many days of from..to lie inside the spans.
func AwayDaysIn(spans []db.AwaySpan, from, to score.Date) int {
	n := 0
	for d := from; !d.After(to); d = d.AddDays(1) {
		for _, sp := range spans {
			if sp.Contains(d) {
				n++
				break
			}
		}
	}
	return n
}

// recent measures the person's two weeks before the challenge week for a measured kind.
func (s *Service) recent(ctx context.Context, userID int64, kind string, week score.Date) (Recent, error) {
	last, err := db.ChallengeMeasure(ctx, s.DB.Pool, userID, kind, week.AddDays(-daysInWeek), week.AddDays(-1))
	if err != nil {
		return Recent{}, err
	}
	before, err := db.ChallengeMeasure(ctx, s.DB.Pool, userID, kind, week.AddDays(-2*daysInWeek), week.AddDays(-daysInWeek-1))
	if err != nil {
		return Recent{}, err
	}
	return Recent{Last: last.Total, Before: before.Total, HistoryDays: last.Days + before.Days}, nil
}

// pickKind gathers what each kind needs from the stored data and lets PickKind choose.
func (s *Service) pickKind(ctx context.Context, week score.Date, users []db.User) (Pick, error) {
	from, to := week.AddDays(-weeksOfHistory*daysInWeek), week.AddDays(-1)
	used, err := db.ChallengeKindsBetween(ctx, s.DB.Pool, from, to)
	if err != nil {
		return Pick{}, err
	}
	awayThisWeek := make([]int, len(users))
	awayBefore := make([]int, len(users))
	for i, u := range users {
		spans, err := db.AwaySpansBetween(ctx, s.DB.Pool, u.ID, from, week.AddDays(daysInWeek-1))
		if err != nil {
			return Pick{}, err
		}
		awayThisWeek[i] = AwayDaysIn(spans, week, week.AddDays(daysInWeek-1))
		awayBefore[i] = AwayDaysIn(spans, from, to)
	}
	counted, err := db.CountedDays(ctx, s.DB.Pool, from, to)
	if err != nil {
		return Pick{}, err
	}
	var cands []Candidate
	for _, kind := range AllKinds() {
		c := Candidate{Kind: kind, AwayDays: awayThisWeek, Attainment: -1}
		switch {
		case kind == KindCountedDays:
			possible := 0
			for i := range users {
				possible += weeksOfHistory*daysInWeek - awayBefore[i]
			}
			c.Attainment = percent(len(counted), possible)
		case IsMeasured(kind):
			total, asked, possible := 0, 0, 0
			for i, u := range users {
				r, err := s.recent(ctx, u.ID, kind, week)
				if err != nil {
					return Pick{}, err
				}
				c.People = append(c.People, r)
				total += r.Last + r.Before
				possible += weeksOfHistory*daysInWeek - awayBefore[i]
				if kind == KindPushupReps || kind == KindYogaMinutes {
					m, err := db.ChallengeMeasure(ctx, s.DB.Pool, u.ID, kind, from, to)
					if err != nil {
						return Pick{}, err
					}
					asked += m.Asked
				}
			}
			switch kind {
			case KindPushupReps, KindYogaMinutes:
				c.Attainment = percent(total, asked)
			case KindHabitMarks:
			default:
				c.Attainment = percent(total, possible)
			}
		}
		cands = append(cands, c)
	}
	return PickKind(week, used, cands), nil
}

// percent is part of whole as a rounded percentage, or -1 when there is no whole to measure
// against.
func percent(part, whole int) int {
	if whole <= 0 {
		return -1
	}
	return (part*100 + whole/2) / whole
}
