package insights

import "github.com/nc1107/new-me/server/internal/score"

// WHO 2020 physical activity guideline for adults, per week.
const (
	// GuidelineAerobicMinMin and GuidelineAerobicMaxMin bound the moderate-equivalent minutes: 150
	// to 300 moderate, or 75 to 150 vigorous, where a vigorous minute counts as two.
	GuidelineAerobicMinMin = 150
	GuidelineAerobicMaxMin = 300
	// GuidelineStrengthDays is the least number of muscle-strengthening days.
	GuidelineStrengthDays = 2
	// vigorousFraction is the share of heart-rate reserve from which a session is vigorous.
	vigorousFraction = 0.6
	activityDays     = 7
)

// Session is one workout.
type Session struct {
	Date        score.Date
	Type        string
	DurationMin float64
	// AvgHR is the average heart rate; nil when Health had none.
	AvgHR *float64
}

// Activity is the week's training measured against the WHO 2020 guideline. It reports minutes
// and never prescribes: there is no load ratio and no proposal to train less.
type Activity struct {
	Guideline              string `json:"guideline"`
	ModerateMin            int    `json:"moderateMin"`
	VigorousMin            int    `json:"vigorousMin"`
	ModerateEquivalentMin  int    `json:"moderateEquivalentMin"`
	StrengthDays           int    `json:"strengthDays"`
	AerobicTargetMinMin    int    `json:"aerobicTargetMinMin"`
	AerobicTargetMaxMin    int    `json:"aerobicTargetMaxMin"`
	StrengthTargetDays     int    `json:"strengthTargetDays"`
	MeetsAerobic           bool   `json:"meetsAerobic"`
	MeetsStrength          bool   `json:"meetsStrength"`
	HeartRateIntensityUsed bool   `json:"heartRateIntensityUsed"`
}

// ActivityInput is what the week is computed from.
type ActivityInput struct {
	Sessions []Session
	Today    score.Date
	// RestingHR and MaxHR (220 minus age) classify intensity; zero means unknown.
	RestingHR float64
	MaxHR     float64
}

// vigorous classifies a session. With a heart rate and reserve, 60% of the reserve or more is
// vigorous; without them HIIT is vigorous and everything else moderate.
func vigorous(s Session, in ActivityInput) (isVigorous, usedHR bool) {
	if s.AvgHR != nil && in.RestingHR > 0 && in.MaxHR > in.RestingHR {
		return (*s.AvgHR-in.RestingHR)/(in.MaxHR-in.RestingHR) >= vigorousFraction, true
	}
	return s.Type == "hiit", false
}

// ComputeActivity totals the last seven days. Strength workouts count as strength days and also
// as moderate minutes; yoga and walking are moderate unless a heart rate says otherwise.
func ComputeActivity(in ActivityInput) Activity {
	out := Activity{Guideline: "WHO 2020", AerobicTargetMinMin: GuidelineAerobicMinMin,
		AerobicTargetMaxMin: GuidelineAerobicMaxMin, StrengthTargetDays: GuidelineStrengthDays}
	var moderate, hard float64
	strength := map[score.Date]bool{}
	for _, s := range in.Sessions {
		if age := daysBetween(s.Date, in.Today); age < 0 || age >= activityDays {
			continue
		}
		if s.Type == "strength" {
			strength[s.Date] = true
		}
		v, usedHR := vigorous(s, in)
		out.HeartRateIntensityUsed = out.HeartRateIntensityUsed || usedHR
		if v {
			hard += s.DurationMin
		} else {
			moderate += s.DurationMin
		}
	}
	out.ModerateMin, out.VigorousMin = int(moderate), int(hard)
	out.ModerateEquivalentMin = int(moderate + 2*hard)
	out.StrengthDays = len(strength)
	out.MeetsAerobic = out.ModerateEquivalentMin >= GuidelineAerobicMinMin
	out.MeetsStrength = out.StrengthDays >= GuidelineStrengthDays
	return out
}
