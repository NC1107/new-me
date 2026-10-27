package targets

import "math"

// Macro constants.
const (
	kcalPerGProtein = 4
	kcalPerGCarbs   = 4
	kcalPerGFat     = 9
	// FatShare is the default share of energy from fat; FatFloorShare the least (IOM 2005 range
	// 20 to 35%; Thomas 2016).
	FatShare      = 0.28
	FatFloorShare = 0.20
	// SatFatMaxShare is the most energy from saturated fat (DGA 2020 to 2025; WHO 2023).
	SatFatMaxShare = 0.10
	// CarbsFloorG is the carbohydrate RDA (IOM 2005).
	CarbsFloorG = 130
	// FiberPer1000Kcal is the fiber adequate intake per 1,000 kcal (IOM 2005; DGA).
	FiberPer1000Kcal = 14
	// ProteinCapPerKg is the cap for BMI 30 or more, per kg of the weight at BMI 25.
	ProteinCapPerKg = 2.2
	// ProteinMealPerKg is the per-meal dose (Schoenfeld and Aragon 2018).
	ProteinMealPerKg = 0.4
	proteinRound     = 5
	// ObesityBMI is where the adjusted weight starts to apply.
	ObesityBMI = 30
	// ReferenceBMI is the BMI the adjusted weight is taken at.
	ReferenceBMI = 25
)

// ProteinPerKg is the daily protein per kg for the goal: 2.0 to lose, 1.8 to gain, 1.6 to maintain.
func ProteinPerKg(kind string) float64 {
	switch kind {
	case Lose:
		return 2.0
	case Gain:
		return 1.8
	}
	return 1.6
}

// Protein is the daily protein target and how the cap applied.
type Protein struct {
	G        int
	PerKg    float64
	BMI      *float64
	Capped   bool
	CapG     float64
	PerMealG int
}

// ComputeProtein is g/kg x weight rounded to 5 g. With a BMI of 30 or more the target is capped
// at 2.2 g/kg of the weight at BMI 25 for the height (expert practice). heightCm may be nil, in
// which case no BMI is known and no cap applies.
func ComputeProtein(kind string, weightKg float64, heightCm *float64) Protein {
	out := Protein{PerKg: ProteinPerKg(kind)}
	raw := out.PerKg * weightKg
	if heightCm != nil {
		m := *heightCm / 100
		bmi := weightKg / (m * m)
		out.BMI = &bmi
		if bmi >= ObesityBMI {
			out.CapG = ProteinCapPerKg * ReferenceBMI * m * m
			if raw > out.CapG {
				raw, out.Capped = out.CapG, true
			}
		}
	}
	out.G = int(math.Round(raw/proteinRound)) * proteinRound
	out.PerMealG = int(math.Round(ProteinMealPerKg * weightKg))
	return out
}

// Macros are the fat and carbohydrate targets that fill the energy left after protein.
type Macros struct {
	FatG       int
	CarbsG     int
	SatFatMaxG int
	// FatShare is the share of energy the fat target gives.
	FatShare float64
	// FatLowered is true when fat went below 28% so carbohydrate could reach its floor.
	FatLowered bool
	// CarbsFloored is true when carbohydrate sits at 130 g with fat already at its floor, so the
	// macros add up to more than the energy target.
	CarbsFloored bool
}

// ComputeMacros gives fat 28% of energy, carbohydrate the remainder at 4 kcal/g and never under
// 130 g; when the remainder would be lower fat is lowered toward 20% first.
func ComputeMacros(kcal, proteinG int) Macros {
	energy := float64(kcal)
	fatKcal := FatShare * energy
	afterProtein := energy - kcalPerGProtein*float64(proteinG)
	var out Macros
	if (afterProtein-fatKcal)/kcalPerGCarbs < CarbsFloorG {
		lowered := afterProtein - CarbsFloorG*kcalPerGCarbs
		fatKcal = math.Max(lowered, FatFloorShare*energy)
		out.FatLowered = true
	}
	out.FatG = int(math.Round(fatKcal / kcalPerGFat))
	out.FatShare = float64(out.FatG) * kcalPerGFat / energy
	out.CarbsG = int(math.Round((afterProtein - kcalPerGFat*float64(out.FatG)) / kcalPerGCarbs))
	if out.CarbsG < CarbsFloorG {
		out.CarbsG, out.CarbsFloored = CarbsFloorG, true
	}
	out.SatFatMaxG = int(math.Round(SatFatMaxShare * energy / kcalPerGFat))
	return out
}

// FiberTarget is 14 g per 1,000 kcal.
func FiberTarget(kcal int) int {
	return int(math.Round(FiberPer1000Kcal * float64(kcal) / 1000))
}

// FiberAI is the age and sex adequate intake (IOM 2005): men 38 g and women 25 g at 19 to 50;
// 30 g and 21 g at 51 and over. Nil below 19 or without a sex.
func FiberAI(age int, sex Sex) *int {
	if age < 19 || (sex != Male && sex != Female) {
		return nil
	}
	table := map[Sex][2]int{Male: {38, 30}, Female: {25, 21}}
	v := table[sex][0]
	if age >= 51 {
		v = table[sex][1]
	}
	return &v
}
