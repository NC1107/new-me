package targets

// Constants of the v17 quests.
const (
	// ProduceWHOGrams is the WHO and FAO minimum of fruit and vegetables a day (TRS 916, 2003).
	ProduceWHOGrams = 400
	// ProduceServingGrams is one portion in the NHS 5 A Day guide.
	ProduceServingGrams = 80
	// ProduceServings is the minimum in whole servings: 400 g at 80 g each.
	ProduceServings = ProduceWHOGrams / ProduceServingGrams
	// ProduceLowestRiskGrams is where Aune et al. 2017 found the dose-response curves for
	// cardiovascular disease and all-cause mortality still falling.
	ProduceLowestRiskGrams = 800

	// BreathingMinutes is the daily practice in Balban et al. 2023.
	BreathingMinutes = 5
	// SlowBreathsPerMin is the pace of the alternative session, about 0.1 Hz, the rate most
	// studies in Zaccaro et al. 2018 used for slow breathing.
	SlowBreathsPerMin = 6
)
