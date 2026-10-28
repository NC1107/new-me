package insights

import (
	"cmp"
	"fmt"
	"math"
	"slices"
	"time"

	"github.com/nc1107/new-me/server/internal/score"
)

const minutesPerDay = 24 * 60

// Night is one recorded night, keyed by the morning it ends.
type Night struct {
	Date                                          score.Date
	BedAt, WakeAt                                 time.Time
	AsleepMin, DeepMin, REMMin, CoreMin, AwakeMin int
}

// Stages is minutes per night in each sleep stage.
type Stages struct {
	DeepMin  int `json:"deepMin"`
	REMMin   int `json:"remMin"`
	CoreMin  int `json:"coreMin"`
	AwakeMin int `json:"awakeMin"`
}

// NightJSON is a night as the insights answer shows it.
type NightJSON struct {
	Date      score.Date `json:"date"`
	BedAt     string     `json:"bedAt"`
	WakeAt    string     `json:"wakeAt"`
	AsleepMin int        `json:"asleepMin"`
	DeepMin   int        `json:"deepMin"`
	REMMin    int        `json:"remMin"`
	CoreMin   int        `json:"coreMin"`
	AwakeMin  int        `json:"awakeMin"`
}

// NightBar is one bar of the 14-night chart.
type NightBar struct {
	Date      score.Date `json:"date"`
	AsleepMin int        `json:"asleepMin"`
}

// Sleep is the sleep part of the insights answer.
type Sleep struct {
	// Avg7Min is null when the last week has no nights, so nothing reads as zero sleep.
	Avg7Min          *int       `json:"avg7Min"`
	Avg30Min         int        `json:"avg30Min"`
	TargetMin        int        `json:"targetMin"`
	AvgBedtime       *string    `json:"avgBedtime"`
	AvgWake          *string    `json:"avgWake"`
	BedtimeSpreadMin int        `json:"bedtimeSpreadMin"`
	Stages7          *Stages    `json:"stages7"`
	LastNight        *NightJSON `json:"lastNight"`
	Nights           []NightBar `json:"nights"`
}

// SleepInput is everything the sleep insights read.
type SleepInput struct {
	Nights    []Night
	Today     score.Date
	TargetMin int
	// Loc is the zone bedtimes and wake times are read in.
	Loc *time.Location
}

// ComputeSleep derives the sleep insights. Only nights with sleep recorded count.
func ComputeSleep(in SleepInput) Sleep {
	var withData []Night
	for _, n := range in.Nights {
		if n.AsleepMin > 0 {
			withData = append(withData, n)
		}
	}
	slices.SortFunc(withData, func(a, b Night) int { return cmp.Compare(a.Date, b.Date) })
	inWindow := func(days int) []Night {
		from := in.Today.AddDays(-(days - 1))
		var out []Night
		for _, n := range withData {
			if !n.Date.Before(from) && !n.Date.After(in.Today) {
				out = append(out, n)
			}
		}
		return out
	}
	asleep := func(nights []Night) []float64 {
		out := make([]float64, len(nights))
		for i, n := range nights {
			out[i] = float64(n.AsleepMin)
		}
		return out
	}
	last7, last14, last30 := inWindow(7), inWindow(14), inWindow(30)

	out := Sleep{
		Avg7Min:   roundedMean(asleep(last7)),
		Avg30Min:  int(math.Round(mean(asleep(last30)))),
		TargetMin: in.TargetMin,
		Nights:    make([]NightBar, 0, len(last14)),
	}
	bedtimes := make([]float64, len(last14))
	wakes := make([]float64, len(last14))
	for i, n := range last14 {
		out.Nights = append(out.Nights, NightBar{Date: n.Date, AsleepMin: n.AsleepMin})
		bedtimes[i] = score.MinuteOfDay(n.BedAt, in.Loc)
		wakes[i] = score.MinuteOfDay(n.WakeAt, in.Loc)
	}
	if len(last14) > 0 {
		bed, wake := circularMean(bedtimes), circularMean(wakes)
		out.AvgBedtime, out.AvgWake = clock(bed), clock(wake)
		out.BedtimeSpreadMin = int(math.Round(circularDeviation(bedtimes, bed)))
		last := last14[len(last14)-1]
		out.LastNight = &NightJSON{
			Date: last.Date, BedAt: last.BedAt.UTC().Format(time.RFC3339), WakeAt: last.WakeAt.UTC().Format(time.RFC3339),
			AsleepMin: last.AsleepMin, DeepMin: last.DeepMin, REMMin: last.REMMin, CoreMin: last.CoreMin, AwakeMin: last.AwakeMin,
		}
	}
	if len(last7) > 0 {
		var deep, rem, core, awake []float64
		for _, n := range last7 {
			deep, rem = append(deep, float64(n.DeepMin)), append(rem, float64(n.REMMin))
			core, awake = append(core, float64(n.CoreMin)), append(awake, float64(n.AwakeMin))
		}
		out.Stages7 = &Stages{
			DeepMin: int(math.Round(mean(deep))), REMMin: int(math.Round(mean(rem))),
			CoreMin: int(math.Round(mean(core))), AwakeMin: int(math.Round(mean(awake))),
		}
	}
	return out
}

// circularMean averages times of day as angles on a 24 hour circle, so 23:00 and 01:00 average
// to midnight instead of noon.
func circularMean(minutes []float64) float64 {
	var sin, cos float64
	for _, m := range minutes {
		angle := m / minutesPerDay * 2 * math.Pi
		sin += math.Sin(angle)
		cos += math.Cos(angle)
	}
	mean := math.Atan2(sin, cos) / (2 * math.Pi) * minutesPerDay
	if mean < 0 {
		mean += minutesPerDay
	}
	return mean
}

// circularDeviation is the standard deviation of times of day around their circular mean,
// measuring each distance the short way round the clock.
func circularDeviation(minutes []float64, mean float64) float64 {
	if len(minutes) < 2 {
		return 0
	}
	var sum float64
	for _, m := range minutes {
		d := math.Mod(m-mean+minutesPerDay*1.5, minutesPerDay) - minutesPerDay/2
		sum += d * d
	}
	return math.Sqrt(sum / float64(len(minutes)))
}

func clock(minutes float64) *string {
	total := int(math.Round(minutes)) % minutesPerDay
	s := fmt.Sprintf("%02d:%02d", total/60, total%60)
	return &s
}
