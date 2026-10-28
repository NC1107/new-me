// Package lookback builds the long-run comparisons: the rolling progress windows and the
// monthly look-back, and sends the push that opens each month.
package lookback

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"time"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/insights"
	"github.com/nc1107/new-me/server/internal/nudge"
	"github.com/nc1107/new-me/server/internal/progress"
	"github.com/nc1107/new-me/server/internal/push"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/together"
)

const (
	// DefaultWindow is the rolling window of the progress screen, in days.
	DefaultWindow = 30
	// MinWindow and MaxWindow bound ?window=.
	MinWindow = 7
	MaxWindow = 365
	// firstWindow is how many days after joining make up "the first month".
	firstWindow = 30
	// TopImprovements is how many wins a look-back names.
	TopImprovements = 3
)

var monthPattern = regexp.MustCompile(`^(\d{4})-(0[1-9]|1[0-2])$`)

// Service reads the data for progress and look-backs.
type Service struct {
	DB       *db.DB
	Together *together.Service
	Now      func() time.Time
}

// SeriesFor loads every tracked metric of the person from the join date through today.
func SeriesFor(ctx context.Context, q db.Querier, u db.User, today score.Date) (map[string]progress.Series, error) {
	from := u.JoinedOn
	out := map[string]progress.Series{}
	loaders := []struct {
		key  string
		load func() (map[score.Date]float64, error)
	}{
		{progress.KeyReading, func() (map[score.Date]float64, error) { return db.ReadingByDay(ctx, q, u.ID, from, today) }},
		{progress.KeySteps, func() (map[score.Date]float64, error) { return healthByDay(ctx, q, u.ID, db.MetricSteps, from, today) }},
		{progress.KeySleep, func() (map[score.Date]float64, error) { return db.SleepByDay(ctx, q, u.ID, from, today) }},
		{progress.KeyWorkouts, func() (map[score.Date]float64, error) { return db.WorkoutsByDay(ctx, q, u.ID, from, today) }},
		{progress.KeyPushups, func() (map[score.Date]float64, error) { return db.PushupsByDay(ctx, q, u.ID, from, today) }},
		{progress.KeyProtein, func() (map[score.Date]float64, error) { return db.ProteinByDay(ctx, q, u.ID, from, today) }},
		{progress.KeyHabits, func() (map[score.Date]float64, error) { return db.HabitsKeptByDay(ctx, q, u.ID, from, today) }},
		{progress.KeyBodyFat, func() (map[score.Date]float64, error) { return healthByDay(ctx, q, u.ID, "body_fat_pct", from, today) }},
		{progress.KeyLean, func() (map[score.Date]float64, error) { return healthByDay(ctx, q, u.ID, "lean_mass_kg", from, today) }},
		{progress.KeyVO2, func() (map[score.Date]float64, error) { return healthByDay(ctx, q, u.ID, "vo2max", from, today) }},
		{progress.KeyRestHR, func() (map[score.Date]float64, error) { return healthByDay(ctx, q, u.ID, "resting_hr", from, today) }},
	}
	for _, l := range loaders {
		series, err := l.load()
		if err != nil {
			return nil, fmt.Errorf("%s: %w", l.key, err)
		}
		out[l.key] = series
	}
	// The weight trend is smoothed over every weigh-in ever made, not only the ones in range, so
	// the first window starts from a settled trend.
	readings, err := db.HealthSeries(ctx, q, u.ID, db.MetricWeight, "0001-01-01", today)
	if err != nil {
		return nil, err
	}
	raw := make([]insights.Reading, len(readings))
	for i, p := range readings {
		raw[i] = insights.Reading{Date: p.Date, Value: p.Value}
	}
	weight := progress.Series{}
	for _, p := range insights.Smooth(raw) {
		weight[p.Date] = p.Smoothed
	}
	out[progress.KeyWeight] = weight
	return out, nil
}

func healthByDay(ctx context.Context, q db.Querier, userID int64, metric string, from, to score.Date) (map[score.Date]float64, error) {
	points, err := db.HealthSeries(ctx, q, userID, metric, from, to)
	if err != nil {
		return nil, err
	}
	out := make(map[score.Date]float64, len(points))
	for _, p := range points {
		out[p.Date] = p.Value
	}
	return out, nil
}

// PersonProgress is one person's progress answer.
type PersonProgress struct {
	UserID   int64             `json:"userId"`
	Name     string            `json:"name"`
	Color    string            `json:"color"`
	JoinedOn score.Date        `json:"joinedOn"`
	Metrics  []progress.Metric `json:"metrics"`
}

// Progress is the answer of GET /api/progress.
type Progress struct {
	Window int              `json:"window"`
	Today  score.Date       `json:"today"`
	People []PersonProgress `json:"people"`
}

// BuildProgress compares everyone's rolling window with the one before and with their first
// window. Each person is measured on their own local today.
func (s *Service) BuildProgress(ctx context.Context, window int) (Progress, error) {
	users, err := db.ListUsers(ctx, s.DB.Pool)
	if err != nil {
		return Progress{}, err
	}
	now := s.Now()
	out := Progress{Window: window, People: make([]PersonProgress, 0, len(users))}
	for _, u := range users {
		loc, err := u.Location()
		if err != nil {
			return out, err
		}
		today := score.LocalToday(now, loc)
		out.Today = max(out.Today, today)
		series, err := SeriesFor(ctx, s.DB.Pool, u, today)
		if err != nil {
			return out, err
		}
		person := PersonProgress{UserID: u.ID, Name: u.Name, Color: u.Color, JoinedOn: u.JoinedOn,
			Metrics: make([]progress.Metric, 0, len(progress.Specs))}
		for _, spec := range progress.Specs {
			person.Metrics = append(person.Metrics,
				progress.Compute(spec, series[spec.Key], u.JoinedOn, today, window, progress.DefaultWeeks))
		}
		out.People = append(out.People, person)
	}
	return out, nil
}

// MonthMetric is one metric's month average with its comparisons.
type MonthMetric struct {
	Key                string             `json:"key"`
	Title              string             `json:"title"`
	Unit               string             `json:"unit"`
	GoodDirection      progress.Direction `json:"goodDirection"`
	Value              *float64           `json:"value"`
	Previous           *float64           `json:"previous"`
	First              *float64           `json:"first"`
	ChangeFromPrevious *progress.Change   `json:"changeFromPrevious"`
	ChangeFromFirst    *progress.Change   `json:"changeFromFirst"`
}

// PersonMonth is one person's month.
type PersonMonth struct {
	UserID       int64                  `json:"userId"`
	Name         string                 `json:"name"`
	Color        string                 `json:"color"`
	Points       int                    `json:"points"`
	CountedDays  int                    `json:"countedDays"`
	Metrics      []MonthMetric          `json:"metrics"`
	Improvements []progress.Improvement `json:"improvements"`
	// Lifts are the exercises logged in the month with their best set against the first month.
	Lifts []Lift `json:"lifts"`
}

// CoupleMonth is the two of them together: points, the days both counted, and the metrics
// averaged across the two of them.
type CoupleMonth struct {
	Points          int                    `json:"points"`
	BothCountedDays int                    `json:"bothCountedDays"`
	Metrics         []MonthMetric          `json:"metrics"`
	Improvements    []progress.Improvement `json:"improvements"`
}

// Month is the answer of GET /api/lookback.
type Month struct {
	Month string     `json:"month"`
	Label string     `json:"label"`
	From  score.Date `json:"from"`
	To    score.Date `json:"to"`
	// Complete is false while the month is still running.
	Complete bool          `json:"complete"`
	People   []PersonMonth `json:"people"`
	Couple   CoupleMonth   `json:"couple"`
}

// ErrBadMonth marks a month that is malformed or in the future.
var ErrBadMonth = errors.New("month must be YYYY-MM and not in the future")

// MonthBounds parses YYYY-MM into its first and last day.
func MonthBounds(month string) (from, to score.Date, err error) {
	m := monthPattern.FindStringSubmatch(month)
	if m == nil {
		return "", "", ErrBadMonth
	}
	first, err := time.Parse("2006-01", month)
	if err != nil {
		return "", "", ErrBadMonth
	}
	return score.DateOf(first), score.DateOf(first.AddDate(0, 1, -1)), nil
}

// LastCompletedMonth is the month before the one `today` is in.
func LastCompletedMonth(today score.Date) string {
	return today.Time().AddDate(0, -1, 0).Format("2006-01")
}

// BuildMonth compares the month with the month before and with each person's first month. The
// month is judged complete by the caller's local today.
func (s *Service) BuildMonth(ctx context.Context, month string, viewerToday score.Date) (Month, error) {
	from, to, err := MonthBounds(month)
	if err != nil {
		return Month{}, err
	}
	if from.After(viewerToday) {
		return Month{}, ErrBadMonth
	}
	prevFrom, prevTo, _ := MonthBounds(from.AddDays(-1).Time().Format("2006-01"))
	users, err := db.ListUsers(ctx, s.DB.Pool)
	if err != nil {
		return Month{}, err
	}
	label := from.Time().Format("January 2006")
	out := Month{Month: month, Label: label, From: from, To: to, Complete: to.Before(viewerToday),
		People: make([]PersonMonth, 0, len(users))}

	coupleCur, couplePrev := map[string][]float64{}, map[string][]float64{}
	coupleFirst := map[string][]float64{}
	for _, u := range users {
		loc, err := u.Location()
		if err != nil {
			return out, err
		}
		today := score.LocalToday(s.Now(), loc)
		series, err := SeriesFor(ctx, s.DB.Pool, u, today)
		if err != nil {
			return out, err
		}
		person := PersonMonth{UserID: u.ID, Name: u.Name, Color: u.Color}
		cur, prev := map[string]*float64{}, map[string]*float64{}
		for _, spec := range progress.Specs {
			mm := monthMetric(spec, series[spec.Key], u.JoinedOn, today, from, to, prevFrom, prevTo)
			person.Metrics = append(person.Metrics, mm)
			cur[spec.Key], prev[spec.Key] = mm.Value, mm.Previous
			collect(coupleCur, spec.Key, mm.Value)
			collect(couplePrev, spec.Key, mm.Previous)
			collect(coupleFirst, spec.Key, mm.First)
		}
		person.Improvements = progress.TopImprovements(progress.Specs, cur, prev, TopImprovements)
		liftSets, err := db.LiftSetsThrough(ctx, s.DB.Pool, u.ID, from, to)
		if err != nil {
			return out, err
		}
		person.Lifts = Lifts(liftSets, from, to)
		if person.Points, err = db.SumPoints(ctx, s.DB.Pool, u.ID, from, to); err != nil {
			return out, err
		}
		if person.CountedDays, err = db.CountedDaysIn(ctx, s.DB.Pool, u.ID, from, to); err != nil {
			return out, err
		}
		out.Couple.Points += person.Points
		out.People = append(out.People, person)
	}

	counted, err := db.CountedDays(ctx, s.DB.Pool, from, to)
	if err != nil {
		return out, err
	}
	pair := make([]together.Counted, len(counted))
	for i, c := range counted {
		pair[i] = together.Counted{UserID: c.UserID, Date: c.Date}
	}
	members := make([]int64, len(users))
	for i, u := range users {
		members[i] = u.ID
	}
	out.Couple.BothCountedDays = together.BothCountedDays(pair, members)

	cur, prev := map[string]*float64{}, map[string]*float64{}
	for _, spec := range progress.Specs {
		c, p, f := mean(coupleCur[spec.Key]), mean(couplePrev[spec.Key]), mean(coupleFirst[spec.Key])
		mm := MonthMetric{Key: spec.Key, Title: spec.Title, Unit: spec.Phrase, GoodDirection: spec.Good,
			Value: c, Previous: p, First: f}
		if c != nil && p != nil {
			mm.ChangeFromPrevious = progress.Compare(spec, *p, *c)
		}
		if c != nil && f != nil {
			mm.ChangeFromFirst = progress.Compare(spec, *f, *c)
		}
		out.Couple.Metrics = append(out.Couple.Metrics, mm)
		cur[spec.Key], prev[spec.Key] = c, p
	}
	out.Couple.Improvements = progress.TopImprovements(progress.Specs, cur, prev, TopImprovements)
	return out, nil
}

func monthMetric(spec progress.Spec, s progress.Series, join, today, from, to, prevFrom, prevTo score.Date) MonthMetric {
	v, vOK := progress.Average(spec, s, from, to, join, today)
	p, pOK := progress.Average(spec, s, prevFrom, prevTo, join, today)
	mm := MonthMetric{Key: spec.Key, Title: spec.Title, Unit: spec.Phrase, GoodDirection: spec.Good,
		Value: opt(v, vOK), Previous: opt(p, pOK)}
	if firstTo := join.AddDays(firstWindow - 1); !firstTo.After(today) {
		f, fOK := progress.Average(spec, s, join, firstTo, join, today)
		mm.First = opt(f, fOK)
	}
	if vOK && pOK {
		mm.ChangeFromPrevious = progress.Compare(spec, p, v)
	}
	if mm.Value != nil && mm.First != nil {
		mm.ChangeFromFirst = progress.Compare(spec, *mm.First, *mm.Value)
	}
	return mm
}

func opt(v float64, ok bool) *float64 {
	if !ok {
		return nil
	}
	return &v
}

func collect(into map[string][]float64, key string, v *float64) {
	if v != nil {
		into[key] = append(into[key], *v)
	}
}

func mean(vs []float64) *float64 {
	if len(vs) == 0 {
		return nil
	}
	sum := 0.0
	for _, v := range vs {
		sum += v
	}
	m := sum / float64(len(vs))
	return &m
}

// PushDue sends each person the look-back of the month that just ended, once, on the 1st at
// their first notification. It is that day's first automatic push, so it takes a slot of the
// daily budget and the morning plan steps aside.
func (s *Service) PushDue(ctx context.Context, now time.Time) error {
	if s.Together == nil || s.Together.Notifier == nil {
		return nil
	}
	users, err := db.ListUsers(ctx, s.DB.Pool)
	if err != nil {
		return err
	}
	var errs []error
	cache := map[string]Month{}
	for _, u := range users {
		loc, err := u.Location()
		if err != nil {
			errs = append(errs, err)
			continue
		}
		local := now.In(loc)
		today := score.LocalToday(now, loc)
		if local.Day() != 1 || !u.Notify.Lookback || today.Before(u.JoinedOn) {
			continue
		}
		if u.Schedule.Quiet(today, local.Hour()*60+local.Minute()) {
			continue
		}
		sent, err := db.CountNotices(ctx, s.DB.Pool, u.ID, today, together.AutoKinds)
		if err != nil {
			errs = append(errs, err)
			continue
		}
		if sent >= nudge.DailyBudget {
			continue
		}
		monthKey := LastCompletedMonth(today)
		month, ok := cache[monthKey]
		if !ok {
			if month, err = s.BuildMonth(ctx, monthKey, today); err != nil {
				errs = append(errs, fmt.Errorf("look-back for user %d: %w", u.ID, err))
				continue
			}
			cache[monthKey] = month
		}
		_, err = s.Together.SendClaimed(ctx, together.Claim{Kind: together.EventLookback, UserID: u.ID, Date: today}, u,
			push.Message{Kind: together.EventLookback, Title: "Your " + month.Label, Body: Body(month, u.ID, u.Imperial())})
		if err != nil {
			errs = append(errs, err)
		}
	}
	return errors.Join(errs...)
}

// Body is the push text of a person's look-back: their biggest improvement, or a plain invitation
// to look when the month had nothing to compare.
func Body(m Month, userID int64, imperial bool) string {
	for _, p := range m.People {
		if p.UserID != userID {
			continue
		}
		if len(p.Improvements) > 0 {
			imp := p.Improvements[0]
			if imperial && imp.Unit == "kg" {
				return poundsSummary(imp) + "."
			}
			return imp.Summary + "."
		}
		return fmt.Sprintf("%d counted days in %s. Open New Me to see how it went.", p.CountedDays, m.Label)
	}
	return "Open New Me to see how the month went."
}

// poundsSummary words a kilogram improvement in pounds, the way progress words it in kg.
func poundsSummary(imp progress.Improvement) string {
	word := "up"
	if imp.Value < imp.Previous {
		word = "down"
	}
	const lbPerKg = 1 / 0.45359237
	return fmt.Sprintf("%s: %.1f lb, %s from %.1f", imp.Title, imp.Value*lbPerKg, word, imp.Previous*lbPerKg)
}
