package insights

import "github.com/nc1107/new-me/server/internal/score"

// ProteinDay is one day's protein target and what was eaten.
type ProteinDay struct {
	Date    score.Date
	TargetG int
	Grams   float64
}

// Protein is the protein part of the insights answer.
type Protein struct {
	TargetG int     `json:"targetG"`
	PerKg   float64 `json:"perKg"`
	// WeightKg is the latest weight and SuggestedG the per-kilogram target it gives.
	WeightKg   *float64 `json:"weightKg"`
	SuggestedG *int     `json:"suggestedG"`
	// DaysHit7 of Days7 completed days reached their protein target; HitRate7 is nil without a day.
	DaysHit7 int      `json:"daysHit7"`
	Days7    int      `json:"days7"`
	HitRate7 *float64 `json:"hitRate7"`
}

// HitRate counts how many of the days reached their own target.
func HitRate(days []ProteinDay) (hit, total int) {
	for _, d := range days {
		if d.TargetG <= 0 {
			continue
		}
		total++
		if d.Grams >= float64(d.TargetG) {
			hit++
		}
	}
	return hit, total
}

// ComputeProtein builds the protein insight from the last seven completed days.
func ComputeProtein(targetG int, weightKg *float64, days []ProteinDay) Protein {
	out := Protein{TargetG: targetG, PerKg: score.ProteinPerKg, WeightKg: weightKg}
	if weightKg != nil {
		suggested := score.ProteinTarget(*weightKg)
		out.SuggestedG = &suggested
	}
	out.DaysHit7, out.Days7 = HitRate(days)
	if out.Days7 > 0 {
		rate := round2(float64(out.DaysHit7) / float64(out.Days7))
		out.HitRate7 = &rate
	}
	return out
}
