package training

import "sort"

// Metric names what an exercise's strength chart plots.
type Metric string

// The chart metrics, one per kind of work.
const (
	// MetricE1RM is the Epley estimated one-rep max in kg, from loaded sets of 1 to 10 reps.
	MetricE1RM Metric = "e1rm_kg"
	// MetricVolume is load x reps in kg, from loaded sets above 10 reps, where Epley is unreliable.
	MetricVolume Metric = "volume_kg"
	// MetricReps is the best reps of a bodyweight set.
	MetricReps Metric = "reps"
	// MetricSeconds is the longest hold.
	MetricSeconds Metric = "seconds"
)

// maxEpleyReps is the highest rep count whose set still feeds the one-rep-max estimate.
const maxEpleyReps = 10

// Point is one day on a strength chart.
type Point struct {
	Date  string
	Value float64
}

// Series is a strength chart: the metric and the best value of each day with data, oldest first.
type Series struct {
	Metric Metric
	Points []Point
}

// Estimated reports whether the metric is a calculated estimate rather than a lifted value.
func (m Metric) Estimated() bool { return m == MetricE1RM }

// ChartSeries turns an exercise's sets into its strength chart. Holds chart seconds and
// bodyweight work charts reps. Loaded work charts the estimated one-rep max when any set has 1 to
// 10 reps and otherwise the volume load of sets above 10 reps, so one chart never mixes the two.
// Sets that do not fit the metric (a loaded set with no load, say) are skipped. With no usable
// sets Points is empty.
func ChartSeries(holds, loaded bool, sets []Set) Series {
	metric := MetricReps
	switch {
	case holds:
		metric = MetricSeconds
	case loaded:
		metric = MetricVolume
		for _, s := range sets {
			if s.LoadKg > 0 && s.Reps >= 1 && s.Reps <= maxEpleyReps {
				metric = MetricE1RM
				break
			}
		}
	}
	best := map[string]float64{}
	for _, s := range sets {
		v, ok := chartValue(metric, s)
		if ok && v > best[s.Date] {
			best[s.Date] = v
		}
	}
	points := make([]Point, 0, len(best))
	for d, v := range best {
		points = append(points, Point{Date: d, Value: v})
	}
	sort.Slice(points, func(i, j int) bool { return points[i].Date < points[j].Date })
	return Series{Metric: metric, Points: points}
}

func chartValue(m Metric, s Set) (float64, bool) {
	switch m {
	case MetricSeconds:
		return float64(s.Seconds), s.Seconds > 0
	case MetricReps:
		return float64(s.Reps), s.Reps > 0
	case MetricE1RM:
		if s.LoadKg > 0 && s.Reps >= 1 && s.Reps <= maxEpleyReps {
			return Epley(s.LoadKg, s.Reps), true
		}
	case MetricVolume:
		if s.LoadKg > 0 && s.Reps > maxEpleyReps {
			return float64(int(s.LoadKg*float64(s.Reps)*10+0.5)) / 10, true
		}
	}
	return 0, false
}
