// Package readiness turns last night's sleep and the body's own recovery signals into one of
// three plain levels for the day. It is pure: the caller passes the numbers.
//
// Rules, each signal voting -1 (strain), 0 or +1 (good):
//
//	HRV             at least 15% below the person's 30-day baseline: -1; at least 5% above: +1
//	Resting HR      at least 5 bpm above the 30-day baseline: -1
//	Sleep           at least 60 min under the target: -1; within 15 min of it or over: +1
//
// Baselines are the mean of the readings on the 30 days before today and need at least 7 of
// them. With full data the level is Ready at a total of +2 or more, Easy at -1 or less and
// Normal between. When neither HRV nor resting HR can be compared, only sleep is used
// (basis sleep_only): Easy when 60 min or more short, Ready when the target was met.
package readiness

import (
	"fmt"
	"math"
)

// Levels.
const (
	LevelReady  = "ready"
	LevelNormal = "normal"
	LevelEasy   = "easy"
)

// Bases say how much data the level rests on.
const (
	BasisFull      = "full"
	BasisSleepOnly = "sleep_only"
)

// Reason kinds.
const (
	KindSleep     = "sleep"
	KindHRV       = "hrv"
	KindRestingHR = "resting_hr"
	KindBasis     = "basis"
	KindSteady    = "steady"
)

// Thresholds.
const (
	// MinBaselineDays is how many readings a baseline needs before it is trusted.
	MinBaselineDays = 7
	// HRVLowFraction is how far below baseline HRV signals strain.
	HRVLowFraction = 0.15
	// HRVHighFraction is how far above baseline HRV counts as good.
	HRVHighFraction = 0.05
	// RestingHRHighBPM is how far above baseline resting heart rate signals strain.
	RestingHRHighBPM = 5.0
	// SleepShortMin is how far under target sleep signals strain.
	SleepShortMin = 60
	// SleepOnTargetSlackMin is how far under target still counts as on target.
	SleepOnTargetSlackMin = 15
	readyScore            = 2
	easyScore             = -1
)

// Input is what the level is computed from.
type Input struct {
	// SleepMin is last night's minutes asleep; nil when none was recorded.
	SleepMin       *int
	SleepTargetMin int
	// HRV and RestingHR are today's readings, nil when there is none yet; the baselines are the
	// readings of the 30 days before today.
	HRV         *float64
	HRVBase     []float64
	RestingHR   *float64
	RestingBase []float64
}

// Reason is one plain-language line behind the level.
type Reason struct {
	Kind string `json:"kind"`
	Text string `json:"text"`
}

// Result is the readiness of the day.
type Result struct {
	Level   string   `json:"level"`
	Reasons []Reason `json:"reasons"`
	Basis   string   `json:"basis"`
}

// Compute returns the readiness, or false when there is nothing to base it on (no sleep and no
// comparable recovery reading).
func Compute(in Input) (Result, bool) {
	hrvBase, hrvOK := baseline(in.HRV, in.HRVBase)
	rhrBase, rhrOK := baseline(in.RestingHR, in.RestingBase)
	full := hrvOK || rhrOK
	if in.SleepMin == nil && !full {
		return Result{}, false
	}

	var reasons []Reason
	score := 0
	if hrvOK {
		change := (*in.HRV - hrvBase) / hrvBase
		switch {
		case change <= -HRVLowFraction:
			score--
			reasons = append(reasons, Reason{KindHRV, fmt.Sprintf("HRV %d%% below your usual", pct(-change))})
		case change >= HRVHighFraction:
			score++
			reasons = append(reasons, Reason{KindHRV, fmt.Sprintf("HRV %d%% above your usual", pct(change))})
		}
	}
	if rhrOK {
		if diff := *in.RestingHR - rhrBase; diff >= RestingHRHighBPM {
			score--
			reasons = append(reasons, Reason{KindRestingHR,
				fmt.Sprintf("Resting heart rate %d bpm above your usual", int(math.Round(diff)))})
		}
	}
	sleepVote := 0
	if in.SleepMin != nil {
		short := in.SleepTargetMin - *in.SleepMin
		switch {
		case short >= SleepShortMin:
			sleepVote = -1
			reasons = append(reasons, Reason{KindSleep, fmt.Sprintf("Slept %s, %s under your target", Duration(*in.SleepMin), Duration(short))})
		case short <= SleepOnTargetSlackMin:
			sleepVote = 1
			reasons = append(reasons, Reason{KindSleep, fmt.Sprintf("Slept %s, on target", Duration(*in.SleepMin))})
		}
	}

	res := Result{Level: LevelNormal, Basis: BasisFull}
	if full {
		score += sleepVote
		switch {
		case score >= readyScore:
			res.Level = LevelReady
		case score <= easyScore:
			res.Level = LevelEasy
		}
	} else {
		res.Basis = BasisSleepOnly
		switch {
		case sleepVote < 0:
			res.Level = LevelEasy
		case in.SleepMin != nil && *in.SleepMin >= in.SleepTargetMin:
			res.Level = LevelReady
		}
	}
	if len(reasons) == 0 {
		reasons = append(reasons, Reason{KindSteady, "Sleep and recovery look close to your usual"})
	}
	if res.Basis == BasisSleepOnly {
		reasons = append(reasons, Reason{KindBasis, "Based on sleep only until there are 7 days of heart data"})
	}
	res.Reasons = reasons
	return res, true
}

// baseline is the mean of the readings, usable only with today's reading and enough history.
func baseline(today *float64, history []float64) (float64, bool) {
	if today == nil || len(history) < MinBaselineDays {
		return 0, false
	}
	sum := 0.0
	for _, v := range history {
		sum += v
	}
	mean := sum / float64(len(history))
	return mean, mean > 0
}

func pct(fraction float64) int { return int(math.Round(fraction * 100)) }

// Duration writes minutes as "6 h 10", "7 h" or "45 min".
func Duration(min int) string {
	switch {
	case min < 60:
		return fmt.Sprintf("%d min", min)
	case min%60 == 0:
		return fmt.Sprintf("%d h", min/60)
	}
	return fmt.Sprintf("%d h %02d", min/60, min%60)
}
