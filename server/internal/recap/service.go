package recap

import (
	"context"
	"errors"
	"fmt"
	"log"
	"time"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/nudge"
	"github.com/nc1107/new-me/server/internal/push"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/together"
)

// PushHour is the local hour the Sunday recap is sent.
const PushHour = 19

// PersonRecap is one person's week against the week before.
type PersonRecap struct {
	UserID     int64    `json:"userId"`
	Name       string   `json:"name"`
	Color      string   `json:"color"`
	This       Stats    `json:"this"`
	Previous   Stats    `json:"previous"`
	BestDay    *BestDay `json:"bestDay"`
	Suggestion string   `json:"suggestion"`
}

// PairRecap is the two of them together.
type PairRecap struct {
	This     Stats    `json:"this"`
	Previous Stats    `json:"previous"`
	BestDay  *BestDay `json:"bestDay"`
}

// ChallengeResult is how the week's shared challenge ended.
type ChallengeResult struct {
	Kind      string `json:"kind"`
	Title     string `json:"title"`
	Target    int    `json:"target"`
	Progress  int    `json:"progress"`
	Completed bool   `json:"completed"`
}

// Recap is the answer of GET /api/recap.
type Recap struct {
	Week string     `json:"week"`
	From score.Date `json:"from"`
	To   score.Date `json:"to"`
	// Complete is false while the week is still running.
	Complete  bool             `json:"complete"`
	People    []PersonRecap    `json:"people"`
	Pair      PairRecap        `json:"pair"`
	Challenge *ChallengeResult `json:"challenge"`
}

// Service reads the data for recaps.
type Service struct {
	DB       *db.DB
	Together *together.Service
	Now      func() time.Time
}

// Build computes the recap of the ISO week starting on the Monday. The week's completeness is
// judged by the viewer's local today.
func (s *Service) Build(ctx context.Context, monday, viewerToday score.Date) (Recap, error) {
	users, err := db.ListUsers(ctx, s.DB.Pool)
	if err != nil {
		return Recap{}, err
	}
	sunday, prevMonday := monday.AddDays(6), monday.AddDays(-7)
	out := Recap{Week: score.ISOWeekLabel(monday), From: monday, To: sunday, Complete: sunday.Before(viewerToday),
		People: make([]PersonRecap, 0, len(users))}

	var thisAll, prevAll []Stats
	var dayLists [][]DayPoints
	for _, u := range users {
		cur, err := s.week(ctx, u.ID, monday)
		if err != nil {
			return out, err
		}
		prev, err := s.week(ctx, u.ID, prevMonday)
		if err != nil {
			return out, err
		}
		curStats, prevStats := StatsOf(cur), StatsOf(prev)
		out.People = append(out.People, PersonRecap{
			UserID: u.ID, Name: u.Name, Color: u.Color, This: curStats, Previous: prevStats,
			BestDay: Best(cur.Days), Suggestion: Suggest(curStats, prevStats, out.Complete),
		})
		thisAll, prevAll = append(thisAll, curStats), append(prevAll, prevStats)
		dayLists = append(dayLists, cur.Days)
	}
	out.Pair = PairRecap{This: PairStats(thisAll...), Previous: PairStats(prevAll...), BestDay: Best(CombineDays(dayLists...))}

	ch, err := db.GetChallenge(ctx, s.DB.Pool, monday)
	switch {
	case err == nil:
		status, err := s.Together.ChallengeProgress(ctx, ch)
		if err != nil {
			return out, err
		}
		out.Challenge = &ChallengeResult{Kind: ch.Kind, Title: ch.Title, Target: status.Target, Progress: status.Progress, Completed: ch.CompletedAt != nil}
	case !errors.Is(err, db.ErrNotFound):
		return out, err
	}
	return out, nil
}

func (s *Service) week(ctx context.Context, userID int64, monday score.Date) (Week, error) {
	sunday := monday.AddDays(6)
	q := s.DB.Pool
	var w Week
	scores, err := db.ListDayScores(ctx, q, userID, monday, sunday)
	if err != nil {
		return w, err
	}
	for _, r := range scores {
		w.Days = append(w.Days, DayPoints{Date: r.LocalDate, Points: r.Points(), Counted: r.Counted})
	}
	steps, err := db.HealthSeries(ctx, q, userID, db.MetricSteps, monday, sunday)
	if err != nil {
		return w, err
	}
	for _, p := range steps {
		w.Steps += int(p.Value)
	}
	nights, err := db.ListSleepNights(ctx, q, userID, monday, sunday)
	if err != nil {
		return w, err
	}
	for _, n := range nights {
		if n.AsleepMin > 0 {
			w.AsleepNights = append(w.AsleepNights, n.AsleepMin)
		}
	}
	if w.Workouts, err = db.CountWorkouts(ctx, q, userID, monday, sunday); err != nil {
		return w, err
	}
	w.ReadingMinutes, err = db.ReadingMinutesUser(ctx, q, userID, monday, sunday)
	return w, err
}

// PushDue sends each person's recap push once, on Sunday from 19:00 in their own zone. The
// recap is of the week that ends that day, so it is complete except for the last few hours.
func (s *Service) PushDue(ctx context.Context, now time.Time) error {
	if s.Together == nil || s.Together.Notifier == nil {
		return nil
	}
	users, err := db.ListUsers(ctx, s.DB.Pool)
	if err != nil {
		return err
	}
	var errs []error
	cache := map[score.Date]Recap{}
	for _, u := range users {
		loc, err := u.Location()
		if err != nil {
			errs = append(errs, err)
			continue
		}
		local := now.In(loc)
		if local.Weekday() != time.Sunday || local.Hour() < PushHour || !u.Notify.WeeklyRecap {
			continue
		}
		today := score.LocalToday(now, loc)
		monday := score.WeekStart(today)
		rc, ok := cache[monday]
		if !ok {
			if rc, err = s.Build(ctx, monday, today); err != nil {
				errs = append(errs, fmt.Errorf("recap for user %d: %w", u.ID, err))
				continue
			}
			cache[monday] = rc
		}
		sent, err := db.CountNotices(ctx, s.DB.Pool, u.ID, today, together.AutoKinds)
		if err != nil {
			errs = append(errs, err)
			continue
		}
		// The recap shares the daily budget of automatic pushes; a spent budget skips it.
		if sent >= nudge.DailyBudget {
			continue
		}
		first, err := db.ClaimNotice(ctx, s.DB.Pool, together.EventWeeklyRecap, u.ID, today)
		if err != nil || !first {
			if err != nil {
				errs = append(errs, err)
			}
			continue
		}
		for _, p := range rc.People {
			if p.UserID == u.ID {
				s.Together.Notify(u, push.Message{Kind: together.EventWeeklyRecap, Title: "Your week",
					Body: SummaryLine(p.This, p.Previous, rc.Pair.This)})
			}
		}
	}
	if len(errs) > 0 {
		log.Printf("[NEWME] recap push: %v", errors.Join(errs...))
	}
	return errors.Join(errs...)
}
