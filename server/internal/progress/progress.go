// Package progress compares a person's recent averages with the ones before and with their
// first weeks, so a year with the app shows how far they have come. It is pure: the caller
// passes the dated numbers and the local today.
package progress

import (
	"fmt"
	"math"
	"slices"
	"strconv"

	"github.com/nc1107/new-me/server/internal/score"
)

// Direction is which way a metric moves when the person is getting better.
type Direction string

const (
	Up   Direction = "up"
	Down Direction = "down"
	// Neutral metrics, such as body weight, have no universal good direction.
	Neutral Direction = "none"
)

// Kind says how a metric's daily numbers average out.
type Kind int

const (
	// Dense metrics are totals of what was done in a day, so a day with nothing counts as zero.
	Dense Kind = iota
	// Sparse metrics are readings, so only days that have one are averaged.
	Sparse
	// PerWeek metrics are counts of events, averaged as events per seven days.
	PerWeek
)

const (
	// flatPercent is the relative change under which a metric counts as unchanged.
	flatPercent = 1.0
	// DefaultWeeks is how many weekly points a sparkline carries.
	DefaultWeeks = 26
)

// Spec describes one metric.
type Spec struct {
	Key   string
	Title string
	// Phrase follows the number in plain text: "min a day", "kg".
	Phrase   string
	Kind     Kind
	Good     Direction
	Decimals int
}

// Series holds a metric's numbers by day; days with no data are absent.
type Series map[score.Date]float64

// Change is the difference between two averages.
type Change struct {
	Abs float64 `json:"abs"`
	// Pct is the relative change, nil when it started from zero.
	Pct *float64 `json:"pct"`
	// Better is whether the change is in the good direction; nil for a flat change and for a
	// metric with no good direction.
	Better *bool `json:"better"`
}

// Point is one week of a sparkline; Value is nil for a week without data.
type Point struct {
	WeekStart score.Date `json:"weekStart"`
	Value     *float64   `json:"value"`
}

// Metric is one metric's comparison.
type Metric struct {
	Key           string    `json:"key"`
	Title         string    `json:"title"`
	Unit          string    `json:"unit"`
	GoodDirection Direction `json:"goodDirection"`
	Current       *float64  `json:"current"`
	Previous      *float64  `json:"previous"`
	First         *float64  `json:"first"`
	// ChangeFromPrevious and ChangeFromFirst compare the current window with the previous
	// window and with the first window since joining.
	ChangeFromPrevious *Change `json:"changeFromPrevious"`
	ChangeFromFirst    *Change `json:"changeFromFirst"`
	Series             []Point `json:"series"`
	Summary            string  `json:"summary"`
}

// Average is the metric's average over from..to, clipped to the days the person has lived with
// the app. It is false when no day is left, or when a sparse metric has no reading in range.
func Average(spec Spec, s Series, from, to, join, today score.Date) (float64, bool) {
	from, to = max(from, join), min(to, today)
	if from.After(to) {
		return 0, false
	}
	days := daysBetween(from, to) + 1
	sum, n := 0.0, 0
	for d := from; !d.After(to); d = d.AddDays(1) {
		if v, ok := s[d]; ok {
			sum += v
			n++
		}
	}
	switch spec.Kind {
	case Sparse:
		if n == 0 {
			return 0, false
		}
		return sum / float64(n), true
	case PerWeek:
		return sum / float64(days) * 7, true
	}
	return sum / float64(days), true
}

func daysBetween(a, b score.Date) int { return int(b.Time().Sub(a.Time()).Hours() / 24) }

func ptr(v float64, ok bool) *float64 {
	if !ok {
		return nil
	}
	v = round(v, 2)
	return &v
}

func round(v float64, places int) float64 {
	p := math.Pow(10, float64(places))
	return math.Round(v*p) / p
}

// Compare measures the change from one average to another for a metric.
func Compare(spec Spec, from, to float64) *Change {
	c := &Change{Abs: round(to-from, 2)}
	if from != 0 {
		pct := round((to-from)/math.Abs(from)*100, 1)
		c.Pct = &pct
	}
	flat := math.Abs(to-from) < 1e-9 || (c.Pct != nil && math.Abs(*c.Pct) < flatPercent)
	if spec.Good != Neutral && !flat {
		better := (to > from) == (spec.Good == Up)
		c.Better = &better
	}
	return c
}

// Compute builds the comparison of one metric over a window of `window` days ending today:
// the current window, the one before it, and the first window from the join date, which is only
// shown once that first window is over. The sparkline has one point per Monday-start week.
func Compute(spec Spec, s Series, join, today score.Date, window, weeks int) Metric {
	m := Metric{Key: spec.Key, Title: spec.Title, Unit: spec.Phrase, GoodDirection: spec.Good, Series: []Point{}}
	curFrom := today.AddDays(1 - window)
	prevFrom, prevTo := curFrom.AddDays(-window), curFrom.AddDays(-1)

	cur, curOK := Average(spec, s, curFrom, today, join, today)
	prev, prevOK := Average(spec, s, prevFrom, prevTo, join, today)
	m.Current, m.Previous = ptr(cur, curOK), ptr(prev, prevOK)
	var first float64
	var firstOK bool
	if firstTo := join.AddDays(window - 1); !firstTo.After(today) {
		first, firstOK = Average(spec, s, join, firstTo, join, today)
		m.First = ptr(first, firstOK)
	}
	if curOK && prevOK {
		m.ChangeFromPrevious = Compare(spec, prev, cur)
	}
	if curOK && firstOK {
		m.ChangeFromFirst = Compare(spec, first, cur)
	}

	for week := score.WeekStart(today).AddDays(-7 * (weeks - 1)); !week.After(today); week = week.AddDays(7) {
		if week.AddDays(6).Before(join) {
			continue
		}
		v, ok := Average(spec, s, week, week.AddDays(6), join, today)
		m.Series = append(m.Series, Point{WeekStart: week, Value: ptr(v, ok)})
	}
	m.Summary = Summary(spec, m, window)
	return m
}

// Number writes a value with the metric's precision and no trailing zeros.
func Number(spec Spec, v float64) string {
	return strconv.FormatFloat(round(v, spec.Decimals), 'f', -1, 64)
}

// Thousands is Number with a thousands separator for whole values.
func Thousands(spec Spec, v float64) string {
	s := Number(spec, v)
	if spec.Decimals != 0 {
		return s
	}
	for i := len(s) - 3; i > 0; i -= 3 {
		s = s[:i] + "," + s[i:]
	}
	return s
}

// Summary is the plain sentence of a metric: "Reading: 24 min a day, up from 11 in your first
// month". It compares with the first window when there is one, else with the previous.
func Summary(spec Spec, m Metric, window int) string {
	if m.Current == nil {
		return fmt.Sprintf("%s: no data yet", spec.Title)
	}
	now := fmt.Sprintf("%s: %s %s", spec.Title, Thousands(spec, *m.Current), spec.Phrase)
	ref, label := m.First, firstLabel(window)
	if ref == nil {
		ref, label = m.Previous, "the previous month"
		if window != 30 {
			label = fmt.Sprintf("the previous %d days", window)
		}
	}
	if ref == nil {
		return now
	}
	word := "about the same as"
	switch {
	case round(*m.Current, spec.Decimals) > round(*ref, spec.Decimals):
		word = "up from"
	case round(*m.Current, spec.Decimals) < round(*ref, spec.Decimals):
		word = "down from"
	}
	if word == "about the same as" {
		return fmt.Sprintf("%s, about the same as in %s", now, label)
	}
	return fmt.Sprintf("%s, %s %s in %s", now, word, Thousands(spec, *ref), label)
}

func firstLabel(window int) string {
	if window == 30 {
		return "your first month"
	}
	return fmt.Sprintf("your first %d days", window)
}

// Improvement is a metric that got better, ranked by how much.
type Improvement struct {
	Key      string  `json:"key"`
	Title    string  `json:"title"`
	Unit     string  `json:"unit"`
	Value    float64 `json:"value"`
	Previous float64 `json:"previous"`
	// Pct is the relative improvement.
	Pct     float64 `json:"pct"`
	Summary string  `json:"summary"`
}

// TopImprovements returns the n metrics that improved the most against their previous value, by
// relative change. A metric that started from zero ranks as a 100% improvement, since the
// percentage is undefined.
func TopImprovements(specs []Spec, current, previous map[string]*float64, n int) []Improvement {
	out := []Improvement{}
	for _, spec := range specs {
		cur, prev := current[spec.Key], previous[spec.Key]
		if cur == nil || prev == nil || spec.Good == Neutral {
			continue
		}
		change := Compare(spec, *prev, *cur)
		if change.Better == nil || !*change.Better {
			continue
		}
		pct := 100.0
		if change.Pct != nil {
			pct = math.Abs(*change.Pct)
		}
		word := "up"
		if spec.Good == Down {
			word = "down"
		}
		out = append(out, Improvement{Key: spec.Key, Title: spec.Title, Unit: spec.Phrase, Value: *cur,
			Previous: *prev, Pct: pct,
			Summary: fmt.Sprintf("%s: %s %s, %s from %s", spec.Title, Thousands(spec, *cur), spec.Phrase, word, Thousands(spec, *prev))})
	}
	slices.SortStableFunc(out, func(a, b Improvement) int {
		switch {
		case a.Pct > b.Pct:
			return -1
		case a.Pct < b.Pct:
			return 1
		}
		return 0
	})
	if len(out) > n {
		out = out[:n]
	}
	return out
}
