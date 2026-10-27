package lookback

import (
	"sort"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/training"
)

// MaxLifts caps the lifts a look-back lists, biggest gains first.
const MaxLifts = 5

// Lift measures say what Value and First count.
const (
	LiftReps    = "reps"
	LiftSeconds = "seconds"
	// LiftE1RM is the Epley one-rep max estimate in kg, for loaded exercises.
	LiftE1RM = "e1rm"
)

// LiftSet is a best set as a look-back shows it.
type LiftSet struct {
	Date    score.Date `json:"date"`
	Reps    int        `json:"reps"`
	Seconds int        `json:"seconds"`
	LoadKg  float64    `json:"loadKg"`
}

// Lift is one exercise's best set of the month next to its best set in the first month it was
// logged ("Pull-ups: best set 8, up from 3 in your first month").
type Lift struct {
	Key     string  `json:"key"`
	Name    string  `json:"name"`
	Measure string  `json:"measure"`
	Value   float64 `json:"value"`
	Best    LiftSet `json:"best"`
	// First and FirstMonth are nil when the exercise was first logged this month.
	First      *float64 `json:"first"`
	FirstMonth *string  `json:"firstMonth"`
}

// Lifts picks each exercise's best set between from and to and its best in the first calendar
// month it was logged, from the person's sets in date order.
func Lifts(sets []db.LiftSet, from, to score.Date) []Lift {
	type acc struct {
		name, firstMonth string
		loaded, timed    bool
		month, first     []training.Set
	}
	byKey := map[string]*acc{}
	var order []string
	for _, s := range sets {
		a, ok := byKey[s.Key]
		if !ok {
			a = &acc{name: s.Name, loaded: s.Loaded, firstMonth: s.Date[:7]}
			byKey[s.Key] = a
			order = append(order, s.Key)
		}
		a.timed = a.timed || s.Seconds > 0
		date := score.Date(s.Date)
		if !date.Before(from) && !date.After(to) {
			a.month = append(a.month, s.Set)
		}
		if s.Date[:7] == a.firstMonth {
			a.first = append(a.first, s.Set)
		}
	}
	out := []Lift{}
	for _, key := range order {
		a := byKey[key]
		best, ok := training.BestSet(a.month, a.loaded)
		if !ok {
			continue
		}
		l := Lift{Key: key, Name: a.name, Measure: LiftReps, Value: float64(best.Reps),
			Best: LiftSet{Date: score.Date(best.Date), Reps: best.Reps, Seconds: best.Seconds, LoadKg: best.LoadKg}}
		switch {
		case a.loaded && best.E1RMKg > 0:
			l.Measure, l.Value = LiftE1RM, best.E1RMKg
		case a.timed:
			l.Measure, l.Value = LiftSeconds, float64(best.Seconds)
		}
		if a.firstMonth < string(from)[:7] {
			if fb, ok := training.BestSet(a.first, a.loaded); ok {
				v := float64(fb.Reps)
				switch l.Measure {
				case LiftE1RM:
					v = fb.E1RMKg
				case LiftSeconds:
					v = float64(fb.Seconds)
				}
				month := a.firstMonth
				l.First, l.FirstMonth = &v, &month
			}
		}
		out = append(out, l)
	}
	sort.SliceStable(out, func(i, j int) bool { return gain(out[i]) > gain(out[j]) })
	if len(out) > MaxLifts {
		out = out[:MaxLifts]
	}
	return out
}

// gain is the relative change from the first month, 0 without one, so new exercises sort after
// the ones that improved.
func gain(l Lift) float64 {
	if l.First == nil || *l.First <= 0 {
		return 0
	}
	return l.Value / *l.First - 1
}
