package targets

import (
	"time"

	"github.com/nc1107/new-me/server/internal/insights"
	"github.com/nc1107/new-me/server/internal/score"
)

// Sleep constants.
const (
	// DefaultSleepMin is 7 h 30 inside the 7 to 9 hours recommended for adults (Hirshkowitz 2015).
	DefaultSleepMin = 450
	MinSleepMin     = 420
	MaxSleepMin     = 540
	// SleepOnsetMin is the upper bound of normal sleep onset latency (Ohayon 2017).
	SleepOnsetMin = 15
	// SRIMinNights and SRIWindowDays are the data an SRI needs.
	SRIMinNights  = 5
	SRIWindowDays = 14
	minutesPerDay = 24 * 60
	// nightStartHour and nightEndHour are the span a night record describes: 18:00 the day
	// before to 12:00.
	nightStartHour = 18
	nightEndHour   = 12
	// nightSpanMin is the length of that span.
	nightSpanMin = (24 - nightStartHour + nightEndHour) * 60
)

// BedtimeMin is the wake time minus the sleep target minus sleep onset latency, as minutes after
// midnight.
func BedtimeMin(wakeMin, targetMin int) int {
	return ((wakeMin-targetMin-SleepOnsetMin)%minutesPerDay + minutesPerDay) % minutesPerDay
}

// Shortfall is how far the nights from..today fall short of the target in total.
type Shortfall struct {
	Nights    int
	AsleepMin int
	TargetMin int
	Min       int
}

// SevenNightShortfall totals the last seven nights with sleep against the target. It is
// information only; surplus on one night offsets a deficit on another.
func SevenNightShortfall(nights []insights.Night, today score.Date, targetMin int) Shortfall {
	from := today.AddDays(-6)
	var out Shortfall
	for _, n := range nights {
		if n.AsleepMin > 0 && !n.Date.Before(from) && !n.Date.After(today) {
			out.Nights++
			out.AsleepMin += n.AsleepMin
		}
	}
	out.TargetMin = out.Nights * targetMin
	out.Min = max(0, out.TargetMin-out.AsleepMin)
	return out
}

// Regularity is the Sleep Regularity Index and what it was computed from.
type Regularity struct {
	// Score runs from -100 to 100; 100 is perfectly regular. Nil without enough data.
	Score  *float64
	Nights int
	Pairs  int
	// Missing names the shortfall in data.
	Missing []string
}

// SleepRegularity is the Phillips 2017 index: the chance that two minutes 24 hours apart are in
// the same state (asleep or awake), scaled to -100..100. It reads the last 14 days of night
// records at minute resolution and needs 5 nights. A night record describes 18:00 the day before
// to 12:00, so only minutes inside the spans of two consecutive recorded nights are compared;
// the afternoon is not observed and is left out rather than assumed awake.
func SleepRegularity(nights []insights.Night, today score.Date, loc *time.Location) Regularity {
	from := today.AddDays(-(SRIWindowDays - 1))
	byDate := map[score.Date]insights.Night{}
	var out Regularity
	for _, n := range nights {
		if n.AsleepMin > 0 && n.WakeAt.After(n.BedAt) && !n.Date.Before(from) && !n.Date.After(today) {
			byDate[n.Date] = n
			out.Nights++
		}
	}
	var same, total int
	for d, night := range byDate {
		next, ok := byDate[d.AddDays(1)]
		if !ok {
			continue
		}
		out.Pairs++
		for i := range nightSpanMin {
			total++
			if asleepAt(night, wallMinute(d, i, loc)) == asleepAt(next, wallMinute(d.AddDays(1), i, loc)) {
				same++
			}
		}
	}
	if out.Nights < SRIMinNights {
		out.Missing = append(out.Missing, "nights")
	}
	if out.Pairs == 0 {
		out.Missing = append(out.Missing, "consecutiveNights")
	}
	if len(out.Missing) == 0 {
		v := -100 + 200*float64(same)/float64(total)
		out.Score = &v
	}
	return out
}

// wallMinute is the Unix minute i minutes after 18:00 the day before the night's date, counted on
// the wall clock so that a daylight saving change does not shift one night against the next.
func wallMinute(d score.Date, i int, loc *time.Location) int64 {
	before := d.Time().AddDate(0, 0, -1)
	return time.Date(before.Year(), before.Month(), before.Day(), nightStartHour, i, 0, 0, loc).Unix() / 60
}

func asleepAt(n insights.Night, minute int64) bool {
	return minute >= n.BedAt.Unix()/60 && minute < n.WakeAt.Unix()/60
}
