package score

import "time"

// MinuteOfDay is the wall-clock time of t in loc as minutes after midnight, with seconds as a
// fraction, which sleep statistics average and compare round the clock.
func MinuteOfDay(t time.Time, loc *time.Location) float64 {
	local := t.In(loc)
	return float64(local.Hour()*60+local.Minute()) + float64(local.Second())/60
}
