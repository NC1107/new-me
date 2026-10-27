package progress

// Metric keys.
const (
	KeyReading  = "reading_minutes"
	KeySteps    = "steps"
	KeySleep    = "sleep_minutes"
	KeyWorkouts = "workouts"
	KeyPushups  = "pushups"
	KeyProtein  = "protein_g"
	KeyHabits   = "habits_kept"
	KeyWeight   = "weight_kg"
	KeyBodyFat  = "body_fat_pct"
	KeyLean     = "lean_mass_kg"
	KeyVO2      = "vo2max"
	KeyRestHR   = "resting_hr"
)

// Specs are the tracked metrics, in the order they are shown.
var Specs = []Spec{
	{Key: KeyReading, Title: "Reading", Phrase: "min a day", Kind: Dense, Good: Up},
	{Key: KeySteps, Title: "Steps", Phrase: "steps a day", Kind: Sparse, Good: Up},
	{Key: KeySleep, Title: "Sleep", Phrase: "min a night", Kind: Sparse, Good: Up},
	{Key: KeyWorkouts, Title: "Workouts", Phrase: "a week", Kind: PerWeek, Good: Up, Decimals: 1},
	{Key: KeyPushups, Title: "Push-ups", Phrase: "a day", Kind: Dense, Good: Up},
	{Key: KeyProtein, Title: "Protein", Phrase: "g a day", Kind: Sparse, Good: Up},
	{Key: KeyHabits, Title: "Habits kept", Phrase: "a day", Kind: Dense, Good: Up, Decimals: 1},
	{Key: KeyWeight, Title: "Weight", Phrase: "kg", Kind: Sparse, Good: Neutral, Decimals: 1},
	{Key: KeyBodyFat, Title: "Body fat", Phrase: "%", Kind: Sparse, Good: Down, Decimals: 1},
	{Key: KeyLean, Title: "Lean mass", Phrase: "kg", Kind: Sparse, Good: Up, Decimals: 1},
	{Key: KeyVO2, Title: "VO2 max", Phrase: "ml/kg/min", Kind: Sparse, Good: Up, Decimals: 1},
	{Key: KeyRestHR, Title: "Resting heart rate", Phrase: "bpm", Kind: Sparse, Good: Down},
}
