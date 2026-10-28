package targets

// Water constants, in millilitres of drinks a day. The National Academies adequate intake of
// total water is 3.7 L for men and 2.7 L for women aged 19 and over; about 81% of it comes from
// drinking water and beverages, which is what the quest counts, and the rest comes from food.
const (
	WaterMaleML   = 3000
	WaterFemaleML = 2200
	// WaterMaleTotalL and WaterFemaleTotalL are the total-water adequate intakes the drink
	// figures come from.
	WaterMaleTotalL   = 3.7
	WaterFemaleTotalL = 2.7
)

// Water is the daily drink target and whether it rests on the person's sex.
type Water struct {
	ML int
	// Personalized is false when no sex is set and the women's figure is used as the default.
	Personalized bool
}

// ComputeWater is the National Academies adequate intake of drinks for the person's sex. Without
// a sex it is the lower figure, so nobody is asked for more than the guidance gives anyone.
// Needs rise with activity and heat, which is why the figure is a floor to adjust and not a
// formula.
func ComputeWater(sex *Sex) Water {
	if sex == nil {
		return Water{ML: WaterFemaleML}
	}
	if *sex == Male {
		return Water{ML: WaterMaleML, Personalized: true}
	}
	return Water{ML: WaterFemaleML, Personalized: true}
}
