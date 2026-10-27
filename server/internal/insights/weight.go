package insights

import (
	"math"

	"github.com/nc1107/new-me/server/internal/score"
)

const (
	// WeightAlpha is the smoothing factor of the weight trend: each reading moves the trend a
	// tenth of the way toward itself, so a single heavy morning barely shows.
	WeightAlpha = 0.1
	// rateWindowDays is how far back the weekly rate looks.
	rateWindowDays = 28
	// minRateSpanDays is the least history a weekly rate is reported from.
	minRateSpanDays = 7
	// weightPointsShown bounds the trend line sent to the app.
	weightPointsShown = 90
)

// WeightPoint is one weigh-in and the smoothed trend after it.
type WeightPoint struct {
	Date     score.Date `json:"date"`
	Kg       float64    `json:"kg"`
	Smoothed float64    `json:"smoothed"`
}

// Weight is the weight part of the insights answer.
type Weight struct {
	// LatestKg is the newest raw reading and SmoothedKg the trend after it.
	LatestKg   float64 `json:"latestKg"`
	SmoothedKg float64 `json:"smoothedKg"`
	// WeeklyRateKg is the change of the trend per week over the last 28 days, nil until there
	// is at least a week of weigh-ins to compare. Negative means the trend is falling.
	WeeklyRateKg *float64      `json:"weeklyRateKg"`
	Points       []WeightPoint `json:"points"`
}

// Reading is one dated measurement.
type Reading struct {
	Date  score.Date
	Value float64
}

// Smooth runs the exponential moving average over readings in date order. The trend starts at
// the first reading and moves WeightAlpha of the way toward each next one.
func Smooth(readings []Reading) []WeightPoint {
	out := make([]WeightPoint, 0, len(readings))
	trend := 0.0
	for i, r := range readings {
		if i == 0 {
			trend = r.Value
		} else {
			trend += WeightAlpha * (r.Value - trend)
		}
		out = append(out, WeightPoint{Date: r.Date, Kg: r.Value, Smoothed: trend})
	}
	return out
}

// ComputeWeight smooths the weigh-ins (oldest first) and measures how fast the trend moves. The
// rate compares the latest trend with the one at the newest weigh-in at least 28 days earlier,
// or at the first weigh-in when the history is shorter than that but at least a week long.
func ComputeWeight(readings []Reading) *Weight {
	if len(readings) == 0 {
		return nil
	}
	points := Smooth(readings)
	last := points[len(points)-1]
	w := &Weight{LatestKg: round2(last.Kg), SmoothedKg: round2(last.Smoothed)}

	ref := points[0]
	for _, p := range points {
		if daysBetween(p.Date, last.Date) >= rateWindowDays {
			ref = p
		}
	}
	if span := daysBetween(ref.Date, last.Date); span >= minRateSpanDays {
		rate := round2((last.Smoothed - ref.Smoothed) / float64(span) * 7)
		w.WeeklyRateKg = &rate
	}
	shown := points[max(len(points)-weightPointsShown, 0):]
	w.Points = make([]WeightPoint, len(shown))
	for i, p := range shown {
		w.Points[i] = WeightPoint{Date: p.Date, Kg: round2(p.Kg), Smoothed: round2(p.Smoothed)}
	}
	return w
}

func daysBetween(a, b score.Date) int { return int(b.Time().Sub(a.Time()).Hours() / 24) }

func round2(v float64) float64 { return math.Round(v*100) / 100 }
