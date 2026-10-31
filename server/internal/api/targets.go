package api

import (
	"context"
	"fmt"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/insights"
	"github.com/nc1107/new-me/server/internal/plan"
	"github.com/nc1107/new-me/server/internal/readiness"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/targets"
)

// Target keys.
const (
	tgtResting     = "restingEnergy"
	tgtMaintenance = "maintenance"
	tgtEstimated   = "estimatedFromLogs"
	tgtCalories    = "calories"
	tgtProtein     = "protein"
	tgtFat         = "fat"
	tgtSatFat      = "saturatedFatMax"
	tgtCarbs       = "carbs"
	tgtFiber       = "fiber"
	tgtSleep       = "sleep"
	tgtActivity    = "activity"
	tgtExercise    = "exercise"
	tgtSteps       = "steps"
	tgtPushups     = "pushups"
	tgtWater       = "water"
	tgtProduce     = "produce"
	tgtBreathing   = "breathing"
)

// Input keys.
const (
	inWeight = "weightKg"
	inHeight = "heightCm"
	inAge    = "age"
	inSex    = "sex"
	inGoal   = "goal"
	inSteps  = "steps14"
)

// Label values: how firmly the number rests on a published source.
const (
	labelGuideline  = "guideline"
	labelConvention = "convention"
	labelDerivation = "derivation"
)

// Where an input comes from.
const (
	srcProfile = "profile"
	srcHealth  = "health"
	srcMissing = "missing"
)

const targetsDisclaimer = "This is general guidance, not medical advice."

type inputJSON struct {
	Key    string `json:"key"`
	Value  any    `json:"value"`
	Unit   string `json:"unit,omitempty"`
	Source string `json:"source"`
	Note   string `json:"note,omitempty"`
}

type targetJSON struct {
	Key     string `json:"key"`
	Value   *int   `json:"value"`
	Unit    string `json:"unit"`
	Current *int   `json:"current"`
	// Formula is one plain sentence with the person's numbers plugged in; when the value cannot
	// be computed it says what is needed.
	Formula string   `json:"formula"`
	Sources []string `json:"sources"`
	Label   string   `json:"label"`
	// Missing lists the inputs (or data requirements) that keep Value null.
	Missing []string `json:"missing"`
	// Applicable is true for the targets POST /api/targets/apply can set.
	Applicable bool           `json:"applicable"`
	Details    map[string]any `json:"details,omitempty"`
	// Why is one plain line on where Value comes from and Cite the short citation for it. Both are
	// left out for targets that are not goals.
	Why  string `json:"why,omitempty"`
	Cite string `json:"cite,omitempty"`
	// Alternatives are other published figures to pick instead, each saying what it is.
	Alternatives []targets.Alternative `json:"alternatives,omitempty"`
}

type targetsResponse struct {
	AsOf       score.Date        `json:"asOf"`
	Disclaimer string            `json:"disclaimer"`
	Inputs     []inputJSON       `json:"inputs"`
	Targets    []targetJSON      `json:"targets"`
	Sources    map[string]string `json:"sources"`
}

// targetData is everything the formulas read, loaded once per request.
type targetData struct {
	User  db.User
	Today score.Date
	Loc   *time.Location

	Readings []insights.Reading
	// WeightKg is the v7 smoothed trend rounded to 0.1 kg, LatestKg the newest weigh-in.
	WeightKg, LatestKg *float64
	HeightCm           *float64
	HeightFromHealth   bool
	Age                *int
	Sex                *targets.Sex

	Steps       insights.Steps
	StepAvg14   float64
	StepAvgDays int
	Intake      map[score.Date]float64
	Nights      []insights.Night
	Activity    insights.Activity
	Templates   map[string]db.QuestTemplate
	PushupMax   *db.RepsMax
	PushupSets  map[score.Date][]int
	// RepsExercise is the exercise the daily-reps quest counts, which the max and sets are of.
	RepsExercise string
	ProteinToday int
}

// repsExercise is the exercise of the standing pushups template, push-ups before one is set.
func (d targetData) repsExercise() string {
	if e := d.Templates[db.QuestPushups].Exercise; e != "" {
		return e
	}
	return db.DefaultRepsExercise
}

// loadTargetData reads the person's inputs and history.
func (s *Server) loadTargetData(ctx context.Context, q db.Querier, u db.User, loc *time.Location) (targetData, error) {
	today := score.LocalToday(s.now(), loc)
	d := targetData{User: u, Today: today, Loc: loc, Templates: map[string]db.QuestTemplate{}}

	templates, err := db.GetQuestTemplates(ctx, q, u.ID)
	if err != nil {
		return d, err
	}
	for _, t := range templates {
		d.Templates[t.Key] = t
	}

	points, err := db.HealthSeries(ctx, q, u.ID, db.MetricWeight, "0001-01-01", today)
	if err != nil {
		return d, err
	}
	d.Readings = make([]insights.Reading, len(points))
	for i, p := range points {
		d.Readings[i] = insights.Reading{Date: p.Date, Value: p.Value}
	}
	if w := insights.ComputeWeight(d.Readings); w != nil {
		smoothed, latest := round1(w.SmoothedKg), round1(w.LatestKg)
		d.WeightKg, d.LatestKg = &smoothed, &latest
	}

	switch {
	case u.HeightCm != nil:
		d.HeightCm = u.HeightCm
	default:
		latest, err := db.LatestHealth(ctx, q, u.ID, today, []string{"height_cm"})
		if err != nil {
			return d, err
		}
		if h, ok := latest["height_cm"]; ok {
			v := round1(h.Value)
			d.HeightCm, d.HeightFromHealth = &v, true
		}
	}
	d.Age = insights.AgeOn(today, u.BirthYear)
	if u.Sex != nil {
		sex := targets.Sex(*u.Sex)
		d.Sex = &sex
	}

	stepPoints, err := db.HealthSeries(ctx, q, u.ID, db.MetricSteps, today.AddDays(-29), today)
	if err != nil {
		return d, err
	}
	days := make([]insights.StepDay, len(stepPoints))
	for i, p := range stepPoints {
		days[i] = insights.StepDay{Date: p.Date, Steps: p.Value}
	}
	d.Steps = insights.ComputeSteps(insights.StepInput{Days: days, Today: today, Goal: d.Templates[db.QuestSteps].Target, BirthYear: u.BirthYear})
	d.StepAvg14, d.StepAvgDays = targets.AverageSteps(days, today)

	if d.Intake, err = db.DailyKcal(ctx, q, u.ID, today.AddDays(-targets.BalanceMaxSpanDays), today.AddDays(-1)); err != nil {
		return d, err
	}
	stored, err := db.ListSleepNights(ctx, q, u.ID, today.AddDays(-(targets.SRIWindowDays - 1)), today)
	if err != nil {
		return d, err
	}
	d.Nights = make([]insights.Night, len(stored))
	for i, n := range stored {
		d.Nights[i] = insights.Night{Date: n.Date, BedAt: n.BedAt, WakeAt: n.WakeAt, AsleepMin: n.AsleepMin,
			DeepMin: n.DeepMin, REMMin: n.REMMin, CoreMin: n.CoreMin, AwakeMin: n.AwakeMin}
	}
	if d.Activity, err = s.activityInsight(ctx, caller{user: u, loc: loc}, today); err != nil {
		return d, err
	}
	d.RepsExercise = d.repsExercise()
	if m, err := db.LatestRepsMax(ctx, q, u.ID, d.RepsExercise); err == nil {
		d.PushupMax = &m
	} else if err != db.ErrNotFound {
		return d, err
	}
	if d.PushupSets, err = db.RepsSets(ctx, q, u.ID, d.RepsExercise, today.AddDays(-targets.ProgressionWindow), today.AddDays(-1)); err != nil {
		return d, err
	}
	protein, err := proteinFor(ctx, q, u, today, d.Templates[db.QuestProtein].Target)
	if err != nil {
		return d, err
	}
	d.ProteinToday = protein.Effective
	return d, nil
}

// trim formats a number with at most the given decimals, dropping trailing zeros.
// kgPerLb converts pounds to kilograms; lbPerKg is its inverse.
const (
	kgPerLb = 0.45359237
	lbPerKg = 1 / kgPerLb
)

// kg words a weight the way the person reads it. Formulas are defined in kg, so an imperial
// person sees the kg the formula used with their pounds beside it.
func (d targetData) kg(v float64, decimals int) string {
	if d.User.Imperial() {
		return fmt.Sprintf("%s kg (%s lb)", trim(v, decimals), trim(v*lbPerKg, 1))
	}
	return trim(v, decimals) + " kg"
}

// cm words a height the same way, with feet and inches beside it for an imperial person.
func (d targetData) cm(v float64) string {
	if !d.User.Imperial() {
		return trim(v, 1) + " cm"
	}
	inches := int(math.Round(v / 2.54))
	return fmt.Sprintf("%s cm (%d ft %d in)", trim(v, 1), inches/12, inches%12)
}

// perKg words a per-kilogram rate, with the per-pound rate beside it for an imperial person.
func (d targetData) perKg(v float64, unit string) string {
	if d.User.Imperial() {
		return fmt.Sprintf("%s %s per kg (%s per lb)", trim(v, 1), unit, trim(v*kgPerLb, 2))
	}
	return fmt.Sprintf("%s %s per kg", trim(v, 1), unit)
}

func trim(v float64, decimals int) string {
	s := strconv.FormatFloat(v, 'f', decimals, 64)
	if strings.Contains(s, ".") {
		s = strings.TrimRight(strings.TrimRight(s, "0"), ".")
	}
	return s
}

func th(v float64) string {
	n := int(math.Round(v))
	if n < 0 {
		return "-" + plan.Thousands(-n)
	}
	return plan.Thousands(n)
}

func clockText(min int) string { return score.FormatClock(min) }

func intp(v int) *int { return &v }

// inputs lists the formula inputs with where each came from.
func (d targetData) inputs() []inputJSON {
	in := func(key, unit string, value any, source, note string) inputJSON {
		if value == nil {
			source = srcMissing
		}
		return inputJSON{Key: key, Value: value, Unit: unit, Source: source, Note: note}
	}
	var weight, height, age, sex, steps any
	var weightNote, heightSrc, stepsNote = "", srcProfile, ""
	if d.WeightKg != nil {
		weight = *d.WeightKg
		weightNote = fmt.Sprintf("smoothed trend of %d weigh-ins (v7); latest reading %s", len(d.Readings), d.kg(*d.LatestKg, 1))
	}
	if d.HeightCm != nil {
		height = *d.HeightCm
		if d.HeightFromHealth {
			heightSrc = srcHealth
		}
	}
	if d.Age != nil {
		age = *d.Age
	}
	if d.Sex != nil {
		sex = string(*d.Sex)
	}
	if d.StepAvgDays >= insights.MinSuggestionDays {
		steps = math.Round(d.StepAvg14)
		stepsNote = fmt.Sprintf("average of %d days with steps in the last 14", d.StepAvgDays)
	}
	return []inputJSON{
		in(inWeight, "kg", weight, srcHealth, weightNote),
		in(inHeight, "cm", height, heightSrc, ""),
		in(inAge, "years", age, srcProfile, "calendar year minus birth year"),
		in(inSex, "", sex, srcProfile, ""),
		{Key: inGoal, Value: goalJSON{Kind: d.User.GoalKind, PaceKgPerWeek: d.User.GoalPaceKg}, Source: srcProfile},
		in(inSteps, "steps a day", steps, srcHealth, stepsNote),
	}
}

// missingFor lists the named inputs that are absent.
func (d targetData) missingFor(keys ...string) []string {
	out := []string{}
	for _, k := range keys {
		var absent bool
		switch k {
		case inWeight:
			absent = d.WeightKg == nil
		case inHeight:
			absent = d.HeightCm == nil
		case inAge:
			absent = d.Age == nil
		case inSex:
			absent = d.Sex == nil
		case inSteps:
			absent = d.StepAvgDays < insights.MinSuggestionDays
		}
		if absent {
			out = append(out, k)
		}
	}
	return out
}

func needs(missing []string) string {
	return "Needs " + strings.Join(missing, ", ") + " to be filled in; nothing is guessed."
}

// energyChain is the result of the resting energy, maintenance and calorie formulas.
type energyChain struct {
	resting     float64
	pal         targets.PAL
	calories    targets.Calories
	hasCalories bool
}

// goalPace is the chosen goal, with a gain pace never above its body-weight cap and a lose pace
// never above 1% of body weight (the caps are applied inside ComputeCalories).
func (d targetData) goalPace() (kind string, pace float64) {
	return d.User.GoalKind, d.User.GoalPaceKg
}

// computeTargets evaluates every formula for the loaded inputs.
func computeTargets(d targetData) targetsResponse {
	var chain energyChain
	var out []targetJSON
	add := func(t targetJSON) {
		if t.Missing == nil {
			t.Missing = []string{}
		}
		out = append(out, t)
	}
	tpl := func(key string) *int {
		if t, ok := d.Templates[key]; ok {
			return intp(t.Target)
		}
		return nil
	}

	// Resting energy.
	restingMissing := d.missingFor(inWeight, inHeight, inAge, inSex)
	resting := targetJSON{Key: tgtResting, Unit: "kcal", Label: labelGuideline,
		Sources: []string{"mifflin1990", "frankenfield2005"}, Missing: restingMissing}
	if len(restingMissing) == 0 {
		chain.resting = targets.RestingEnergy(*d.WeightKg, *d.HeightCm, *d.Age, *d.Sex)
		sexTerm := "+ 5"
		if *d.Sex == targets.Female {
			sexTerm = "- 161"
		}
		resting.Value = intp(int(math.Round(chain.resting)))
		resting.Formula = fmt.Sprintf("Mifflin-St Jeor: 10 × %s + 6.25 × %s - 5 × %d %s = %s kcal.",
			d.kg(*d.WeightKg, 1), d.cm(*d.HeightCm), *d.Age, sexTerm, th(chain.resting))
	} else {
		resting.Formula = "Mifflin-St Jeor: 10 × kg + 6.25 × cm - 5 × age + 5 (male) or - 161 (female). " + needs(restingMissing)
	}
	add(resting)

	// Maintenance.
	maintMissing := d.missingFor(inWeight, inHeight, inAge, inSex, inSteps)
	maint := targetJSON{Key: tgtMaintenance, Unit: "kcal", Label: labelConvention,
		Sources: []string{"faowhounu2004", "tudorlocke", "shcherbina2017", "germini2022"}, Missing: maintMissing}
	if len(maintMissing) == 0 {
		chain.pal = targets.PALForSteps(d.StepAvg14)
		maintenance := chain.resting * chain.pal.Value
		maint.Value = intp(int(math.Round(maintenance)))
		maint.Formula = fmt.Sprintf("Resting energy %s kcal × activity level %s (%s steps a day on average, in the %s band; the level inside the FAO/WHO/UNU 2004 range is our convention) = %s kcal.",
			th(chain.resting), trim(chain.pal.Value, 2), th(d.StepAvg14), chain.pal.Band, th(maintenance))
		maint.Details = map[string]any{"palValue": chain.pal.Value, "stepBand": chain.pal.Band,
			"note": "Wearable active calories are not used: reported errors are roughly 28 to 43% with no published correction."}
	} else {
		maint.Formula = "Resting energy × physical activity level from the 14-day average steps. " + needs(maintMissing)
	}
	add(maint)

	// Estimated from logs.
	bal := targets.EstimateFromLogs(targets.BalanceInput{Today: d.Today, Readings: d.Readings, IntakeKcal: d.Intake})
	est := targetJSON{Key: tgtEstimated, Unit: "kcal", Label: labelDerivation,
		Sources: []string{"racette2012", "hall2011", "lichtman1992"}, Missing: bal.Missing, Value: bal.Kcal}
	est.Details = map[string]any{
		"weighIns": bal.WeighIns, "spanDays": bal.SpanDays, "loggedDays": bal.LoggedDays,
		"need": map[string]int{"weighIns": targets.BalanceMinWeighIns, "spanDays": targets.BalanceMinSpanDays, "loggedDays": targets.BalanceMinLogged},
	}
	if bal.Kcal != nil {
		est.Formula = fmt.Sprintf("Estimated from your logs: average logged intake %s kcal minus the change in your weight trend (%s over %d days × 7,700 kcal per kg / %d days) = %s kcal, and logged intake is commonly under-reported.",
			th(bal.AvgIntake), d.kg(bal.TrendChgKg, 2), bal.SpanDays, bal.SpanDays, th(float64(*bal.Kcal)))
		est.Details["avgIntakeKcal"] = int(math.Round(bal.AvgIntake))
		est.Details["trendChangeKg"] = math.Round(bal.TrendChgKg*100) / 100
	} else {
		est.Formula = fmt.Sprintf("Estimated from your logs once there are 14 to 28 days with 10 or more days of logged intake and 8 or more weigh-ins; you have a span of %d days, %d logged days and %d weigh-in%s.",
			bal.SpanDays, bal.LoggedDays, bal.WeighIns, map[bool]string{true: "", false: "s"}[bal.WeighIns == 1])
	}
	add(est)

	// Calories.
	calMissing := maintMissing
	cal := targetJSON{Key: tgtCalories, Unit: "kcal", Label: labelDerivation, Applicable: true,
		Sources: []string{"hall2011", "helms2014", "jensen2014"}, Missing: calMissing}
	if d.User.KcalTarget != nil {
		cal.Current = d.User.KcalTarget
	}
	kind, pace := d.goalPace()
	if len(calMissing) == 0 {
		chain.calories = targets.ComputeCalories(targets.CalorieInput{Resting: chain.resting, PAL: chain.pal.Value,
			WeightKg: *d.WeightKg, Sex: *d.Sex, Kind: kind, PaceKg: pace})
		chain.hasCalories = true
		c := chain.calories
		cal.Value = intp(c.Target)
		cal.Formula = calorieFormula(d, c, kind)
		cal.Details = map[string]any{
			"goal": goalJSON{Kind: kind, PaceKgPerWeek: c.PaceKg}, "floorKcal": c.Floor,
			"paceOptions": map[string]any{"lose": targets.LosePaces, "gainMaxKgPerWeek": targets.MaxGainPace(*d.WeightKg)},
		}
	} else {
		cal.Formula = "Maintenance adjusted by the goal pace × 7,700 kcal per kg / 7 days, rounded to 50 kcal and never below the floor. " + needs(calMissing)
	}
	add(cal)

	protein, prot := proteinTarget(d, kind)
	add(prot)

	// Fat, saturated fat, carbohydrate, fiber: all fill the calorie target.
	macroMissing := calMissing
	if len(macroMissing) == 0 && protein == nil {
		macroMissing = d.missingFor(inWeight)
	}
	fat := targetJSON{Key: tgtFat, Unit: "g", Label: labelGuideline, Applicable: true, Current: d.User.FatTarget,
		Sources: []string{"iom2005", "thomas2016"}, Missing: macroMissing}
	sat := targetJSON{Key: tgtSatFat, Unit: "g", Label: labelGuideline,
		Sources: []string{"dga2020", "who2023"}, Missing: macroMissing}
	carbs := targetJSON{Key: tgtCarbs, Unit: "g", Label: labelGuideline, Applicable: true, Current: d.User.CarbsTarget,
		Sources: []string{"iom2005", "thomas2016"}, Missing: macroMissing}
	fiber := targetJSON{Key: tgtFiber, Unit: "g", Label: labelGuideline,
		Sources: []string{"iom2005", "dga2020", "reynolds2019"}, Missing: calMissing}
	if len(macroMissing) == 0 && chain.hasCalories && protein != nil {
		kcal := chain.calories.Target
		m := targets.ComputeMacros(kcal, protein.G)
		fat.Value, sat.Value, carbs.Value = intp(m.FatG), intp(m.SatFatMaxG), intp(m.CarbsG)
		fat.Formula, sat.Formula, carbs.Formula = macroFormulas(kcal, protein.G, m)
		fat.Details = map[string]any{"energyShare": math.Round(m.FatShare*1000) / 1000, "lowered": m.FatLowered}
		carbs.Details = map[string]any{"floored": m.CarbsFloored, "floorG": targets.CarbsFloorG,
			"context": "ACSM sport ranges: 3 to 5 g/kg for light activity, 5 to 7 g/kg for about an hour a day."}
	} else {
		why := needs(macroMissing)
		if len(macroMissing) == 0 {
			why = "Needs a weight to size protein first."
		}
		fat.Formula = "28% of the calorie target, never below 20%. " + why
		sat.Formula = "Under 10% of the calorie target. " + why
		carbs.Formula = "The energy left after protein and fat, never below 130 g. " + why
	}
	if len(calMissing) == 0 {
		fv := targets.FiberTarget(chain.calories.Target)
		fiber.Value = intp(fv)
		fiber.Formula = fmt.Sprintf("14 g per 1,000 kcal × %s = %d g.", trim(float64(chain.calories.Target)/1000, 2), fv)
		fiber.Details = map[string]any{"benefitObservedG": "25 to 29"}
		if d.Age != nil && d.Sex != nil {
			if ai := targets.FiberAI(*d.Age, *d.Sex); ai != nil {
				fiber.Details["adequateIntakeG"] = *ai
				fiber.Formula += fmt.Sprintf(" The adequate intake for your age and sex is %d g, for context.", *ai)
			}
		}
	} else {
		fiber.Formula = "14 g per 1,000 kcal of the calorie target. " + needs(calMissing)
	}
	add(fat)
	add(sat)
	add(carbs)
	add(fiber)

	add(d.sleepTarget(tpl(db.QuestSleep)))
	add(d.activityTarget())
	add(exerciseTarget(tpl(db.QuestExercise)))
	add(d.stepsTarget(tpl(db.QuestSteps)))
	add(d.pushupsTarget(tpl(db.QuestPushups)))
	add(d.waterTarget(tpl(db.QuestWater)))
	add(produceTarget(tpl(db.QuestProduce)))
	add(breathingTarget(tpl(db.QuestBreathing)))

	for i := range out {
		d.addAdvice(&out[i])
	}

	return targetsResponse{AsOf: d.Today, Disclaimer: targetsDisclaimer, Inputs: d.inputs(), Targets: out, Sources: targets.Sources}
}

func calorieFormula(d targetData, c targets.Calories, kind string) string {
	var b strings.Builder
	fmt.Fprintf(&b, "Maintenance %s kcal (our step-band convention)", th(c.Maintenance))
	switch kind {
	case targets.Lose:
		fmt.Fprintf(&b, " - %s a week × 7,700 kcal per kg / 7 days (%s kcal)", d.kg(c.PaceKg, 2), th(-c.DeltaKcal))
	case targets.Gain:
		fmt.Fprintf(&b, " + %s a week × 7,700 kcal per kg / 7 days (%s kcal)", d.kg(c.PaceKg, 2), th(c.DeltaKcal))
	}
	if c.DeltaKcal != 0 {
		fmt.Fprintf(&b, " = %s kcal", th(c.Maintenance+c.DeltaKcal))
	}
	b.WriteString(", rounded to 50")
	if c.Floored {
		fmt.Fprintf(&b, ", raised to the floor of %s kcal (the larger of resting energy and the minimum for your sex)", th(float64(c.Floor)))
	}
	if c.PaceCapped {
		limit := "1% of body weight"
		if kind == targets.Gain {
			limit = "0.5% of body weight"
		}
		fmt.Fprintf(&b, ", with the pace limited to %s a week, %s", d.kg(c.PaceKg, 2), limit)
	}
	fmt.Fprintf(&b, " = %s kcal.", th(float64(c.Target)))
	return b.String()
}

// proteinTarget evaluates the protein formula; the result is nil without a weight.
func proteinTarget(d targetData, kind string) (*targets.Protein, targetJSON) {
	t := targetJSON{Key: tgtProtein, Unit: "g", Label: labelGuideline, Applicable: true,
		Sources: []string{"jager2017", "morton2018", "helms2014", "longland2016", "schoenfeld2018"}}
	if d.ProteinToday > 0 {
		t.Current = intp(d.ProteinToday)
	}
	if d.WeightKg == nil {
		t.Missing = d.missingFor(inWeight)
		t.Formula = "2.0 g per kg to lose, 1.8 to gain, 1.6 to maintain, rounded to 5 g. " + needs(t.Missing)
		return nil, t
	}
	p := targets.ComputeProtein(kind, *d.WeightKg, d.HeightCm)
	t.Value = intp(p.G)
	t.Formula = fmt.Sprintf("%s × %s = %s g, rounded to 5 g.", d.perKg(p.PerKg, "g"), d.kg(*d.WeightKg, 1), th(p.PerKg**d.WeightKg))
	t.Details = map[string]any{"perKg": p.PerKg, "perMealG": p.PerMealG,
		"perMealTip": fmt.Sprintf("About 0.4 g/kg a meal, %d g, across 4 meals.", p.PerMealG)}
	if p.BMI != nil {
		t.Details["bmi"] = math.Round(*p.BMI*10) / 10
	}
	if p.Capped {
		t.Formula = fmt.Sprintf("%s × %s = %s g, capped at 2.2 g per kg of the weight at BMI 25 for your height (expert practice) = %s g, rounded to 5 g.",
			d.perKg(p.PerKg, "g"), d.kg(*d.WeightKg, 1), th(p.PerKg**d.WeightKg), th(p.CapG))
		t.Details["capped"] = true
	}
	if d.HeightCm == nil {
		t.Details["capNote"] = "With a height, a BMI of 30 or more caps the target at 2.2 g/kg of the weight at BMI 25 (expert practice)."
	}
	return &p, t
}

func macroFormulas(kcal, proteinG int, m targets.Macros) (fat, sat, carbs string) {
	fatPct := "28%"
	switch {
	case m.CarbsFloored:
		fatPct = "20%"
	case m.FatLowered:
		fatPct = trim(m.FatShare*100, 1) + "%"
	}
	fat = fmt.Sprintf("%s of %s kcal / 9 kcal per g = %d g, never below 20%%.", fatPct, plan.Thousands(kcal), m.FatG)
	if m.FatLowered {
		fat = fmt.Sprintf("Lowered from 28%% to %s of %s kcal / 9 kcal per g = %d g, so carbohydrate can reach 130 g (the floor is 20%%).",
			fatPct, plan.Thousands(kcal), m.FatG)
	}
	sat = fmt.Sprintf("Under 10%% of %s kcal / 9 kcal per g = %d g.", plan.Thousands(kcal), m.SatFatMaxG)
	carbs = fmt.Sprintf("The remaining energy (%s - 4 × %d - 9 × %d) kcal / 4 kcal per g = %d g, never below 130 g.",
		plan.Thousands(kcal), proteinG, m.FatG, m.CarbsG)
	if m.CarbsFloored {
		carbs = fmt.Sprintf("The remaining energy would be under 130 g with fat at its 20%% floor, so carbohydrate stays at the 130 g floor (%d g), which adds up to a little more than the calorie target.", m.CarbsG)
	}
	return fat, sat, carbs
}

// sleepTarget is the 7.5 h default within 7 to 9 hours, with bedtime, shortfall and regularity.
func (d targetData) sleepTarget(current *int) targetJSON {
	target := targets.DefaultSleepMin
	sched := d.User.Schedule
	bedWork := targets.BedtimeMin(sched.Workday.WakeMin, target)
	bedOff := targets.BedtimeMin(sched.DayOff.WakeMin, target)
	t := targetJSON{Key: tgtSleep, Unit: "min", Label: labelGuideline, Applicable: true, Current: current, Value: intp(target),
		Sources: []string{"watson2015", "hirshkowitz2015", "ohayon2017", "phillips2017", "windred2024", "depner2019"},
		Formula: fmt.Sprintf("Default %s within the 7 to 9 hours recommended for adults, and bedtime is wake time %s - %s - 15 min of sleep onset = %s (%s on days off).",
			readiness.Duration(target), clockText(sched.Workday.WakeMin), readiness.Duration(target), clockText(bedWork), clockText(bedOff))}
	short := targets.SevenNightShortfall(d.Nights, d.Today, target)
	reg := targets.SleepRegularity(d.Nights, d.Today, d.Loc)
	regularity := map[string]any{"score": reg.Score, "nights": reg.Nights, "pairs": reg.Pairs, "missing": reg.Missing,
		"windowDays": targets.SRIWindowDays, "minNights": targets.SRIMinNights,
		"advice": "Keep sleep and wake times regular; there is no threshold.",
		"note":   "Sleep Regularity Index (Phillips 2017) from your night records: 100 is perfectly regular. Only the 18:00 to 12:00 span each night record describes is compared."}
	if reg.Missing == nil {
		regularity["missing"] = []string{}
	}
	t.Details = map[string]any{
		"rangeMin": targets.MinSleepMin, "rangeMax": targets.MaxSleepMin,
		"bedtime": map[string]any{"workday": clockText(bedWork), "dayOff": clockText(bedOff), "onsetLatencyMin": targets.SleepOnsetMin},
		"shortfall7": map[string]any{"nights": short.Nights, "asleepMin": short.AsleepMin, "targetMin": short.TargetMin,
			"shortfallMin": short.Min, "note": "Information only; catch-up sleep has weak evidence, so there is no recovery plan."},
		"regularity": regularity,
	}
	return t
}

// activityTarget is the WHO 2020 weekly guideline with this week's numbers.
func (d targetData) activityTarget() targetJSON {
	a := d.Activity
	return targetJSON{Key: tgtActivity, Unit: "min a week", Label: labelGuideline, Value: intp(insights.GuidelineAerobicMinMin), Missing: []string{},
		Sources: []string{"who2020", "piercy2018", "impellizzeri2020"},
		Formula: fmt.Sprintf("150 to 300 minutes of moderate or 75 to 150 minutes of vigorous activity a week (a vigorous minute counts as two) plus muscle-strengthening on 2 or more days; this week you have %d moderate-equivalent minutes and %d strength days.",
			a.ModerateEquivalentMin, a.StrengthDays),
		Details: map[string]any{"week": a, "maxMin": insights.GuidelineAerobicMaxMin, "note": "No training-load ratio is used or prescribed."}}
}

// exerciseTarget is the weekly guideline spread over seven days, the shape of the exercise quest.
func exerciseTarget(current *int) targetJSON {
	perDay := targets.DailyFromWeekly(insights.GuidelineAerobicMinMin)
	return targetJSON{Key: tgtExercise, Unit: "min", Label: labelGuideline, Applicable: true, Current: current,
		Value: intp(perDay), Missing: []string{}, Sources: []string{"who2020", "piercy2018"},
		Formula: fmt.Sprintf("%d minutes of moderate activity a week (WHO 2020) spread over 7 days = %d minutes a day, rounded up. The guideline is a weekly figure, so a rest day is fine as long as the week adds up.",
			insights.GuidelineAerobicMinMin, perDay),
		Details: map[string]any{"perWeekMin": insights.GuidelineAerobicMinMin, "perWeekMaxMin": insights.GuidelineAerobicMaxMin}}
}

// stepsTarget is 7,000 a day, or the v4 age band suggestion when the person is already above it.
func (d targetData) stepsTarget(current *int) targetJSON {
	t := targetJSON{Key: tgtSteps, Unit: "steps", Label: labelGuideline, Applicable: true, Current: current, Missing: []string{},
		Sources: []string{"ding2025", "paluch2022"}}
	t.Details = map[string]any{"incrementSteps": 1000, "median14": d.Steps.Median14}
	if s := d.Steps.Suggestion; s != nil && s.Median14 > targets.DefaultSteps {
		t.Value = intp(s.Target)
		t.Formula = fmt.Sprintf("You already walk more than 7,000 a day (14-day median %s), so the age band applies: %s to %s steps a day, and the next step is %s.",
			plan.Thousands(s.Median14), plan.Thousands(s.BandLow), plan.Thousands(s.BandHigh), plan.Thousands(s.Target))
		t.Details["bandLow"], t.Details["bandHigh"], t.Details["ageKnown"] = s.BandLow, s.BandHigh, s.AgeKnown
		return t
	}
	t.Value = intp(targets.DefaultSteps)
	t.Formula = "7,000 steps a day, around where the benefit of walking starts to level off (5,000 to 7,000), raised in steps of 1,000 once you are above it."
	return t
}

// pushupsTarget is 3 sets at 75% of the latest max of the chosen exercise, with the progression
// rule. The key stays pushups for compatibility.
func (d targetData) pushupsTarget(current *int) targetJSON {
	name := db.RepsNoun(d.RepsExercise, 2)
	t := targetJSON{Key: tgtPushups, Unit: "reps", Label: labelDerivation, Applicable: true, Current: current, Missing: []string{},
		Sources: []string{"zourdos2016", "schoenfeld2017", "acsm2009"},
		Details: map[string]any{"exercise": d.RepsExercise}}
	if d.PushupMax == nil {
		t.Missing = []string{"pushupMax"}
		t.Formula = fmt.Sprintf("3 sets at about 70 to 80%% of your latest max of %s, a derivation from reps-in-reserve guidance rather than a published constant. Record a max test (one set to near failure) to size it.", name)
		return t
	}
	perSet := 0
	if current != nil {
		perSet = *current / targets.PushupSets
	}
	completed := 0
	for day := d.Today.AddDays(-targets.ProgressionWindow); day.Before(d.Today); day = day.AddDays(1) {
		if targets.DayCompleted(d.PushupSets[day], perSet) {
			completed++
		}
	}
	p := targets.ComputePushups(d.PushupMax.Reps, perSet, completed)
	t.Value = intp(p.Daily())
	t.Formula = fmt.Sprintf("%d sets × %d reps, 75%% (the middle of 70 to 80%%) of your latest max of %d %s, a derivation from reps-in-reserve guidance rather than a published constant.",
		targets.PushupSets, p.RepsPerSet, p.Max, name)
	if p.Progressed {
		t.Formula = fmt.Sprintf("%d sets × %d reps: %d reps a set raised by 5%% (at least 1 rep) because every set was completed on %d of the last 7 days, a derivation from reps-in-reserve and progression guidance.",
			targets.PushupSets, p.RepsPerSet, p.ProgressedFrom, completed)
	}
	t.Details = map[string]any{"exercise": d.RepsExercise, "sets": targets.PushupSets, "repsPerSet": p.RepsPerSet,
		"rangePerSet": []int{p.Low, p.High}, "latestMax": p.Max, "latestMaxDate": d.PushupMax.Date,
		"progressed": p.Progressed, "daysCompleted7": completed, "progressionDays": targets.ProgressionDays,
		"suggestRetestEveryWeeks": "2 to 4"}
	return t
}

// mlPerFlOz converts US fluid ounces to millilitres.
const mlPerFlOz = 29.5735

// volume words an amount of drinks the way the person reads it: litres, with US fluid ounces
// beside them for an imperial person.
func (d targetData) volume(ml int) string {
	litres := fmt.Sprintf("%.1f L", float64(ml)/1000)
	if d.User.Imperial() {
		return fmt.Sprintf("%s (%d fl oz)", litres, int(math.Round(float64(ml)/mlPerFlOz)))
	}
	return litres
}

// waterTarget is the National Academies adequate intake of drinks, which is fixed by sex.
func (d targetData) waterTarget(current *int) targetJSON {
	w := targets.ComputeWater(d.Sex)
	t := targetJSON{Key: tgtWater, Unit: "ml", Label: labelGuideline, Applicable: true, Current: current,
		Value: intp(w.ML), Missing: []string{}, Sources: []string{"nasem2005", "efsa2010"}}
	totalL, who := targets.WaterFemaleTotalL, "women"
	if d.Sex != nil && *d.Sex == targets.Male {
		totalL, who = targets.WaterMaleTotalL, "men"
	}
	t.Formula = fmt.Sprintf("Adequate intake of total water for %s aged 19 and over is %s L a day, and about 81%% of it comes from drinking water and other drinks = %s.",
		who, trim(totalL, 1), d.volume(w.ML))
	if !w.Personalized {
		t.Formula += " Set your sex in About you and this becomes the figure for you; until then it is the one for women."
	}
	t.Details = map[string]any{"personalized": w.Personalized, "totalWaterL": totalL, "drinksShare": 0.81,
		"note": "The Academies report that needs rise with activity and in heat; this is an adequate intake, not a requirement. EFSA (2010) also sets it by sex, at 2.5 L (men) and 2.0 L (women) of total water."}
	return t
}

// produceTarget is five 80 g servings, the WHO 400 g a day.
func produceTarget(current *int) targetJSON {
	return targetJSON{Key: tgtProduce, Unit: "servings", Label: labelGuideline, Applicable: true, Current: current,
		Value: intp(targets.ProduceServings), Missing: []string{}, Sources: []string{"who2003", "nhs5aday", "aune2017"},
		Formula: fmt.Sprintf("WHO advises at least %d g of fruit and vegetables a day, and one serving is %d g (NHS 5 A Day), so %d servings = %d g.",
			targets.ProduceWHOGrams, targets.ProduceServingGrams, targets.ProduceServings, targets.ProduceServings*targets.ProduceServingGrams),
		Details: map[string]any{"servingGrams": targets.ProduceServingGrams, "whoMinGrams": targets.ProduceWHOGrams,
			"lowestRiskGrams": targets.ProduceLowestRiskGrams, "servingExamples": targets.ProduceExamples,
			"note": "Potatoes do not count, beans and pulses count once a day, and juice and smoothies count once however much you drink. Aune et al. 2017 found risk kept falling up to about 800 g (10 servings) a day, so five is a floor, not a ceiling."}}
}

// breathingTarget is the five minutes a day of the Balban trial.
func breathingTarget(current *int) targetJSON {
	return targetJSON{Key: tgtBreathing, Unit: "min", Label: labelGuideline, Applicable: true, Current: current,
		Value: intp(targets.BreathingMinutes), Missing: []string{}, Sources: []string{"balban2023", "zaccaro2018"},
		Formula: fmt.Sprintf("%d minutes a day of cyclic sighing, the practice that improved mood and lowered breathing rate over a month in Balban et al. 2023.", targets.BreathingMinutes),
		Details: map[string]any{"slowPaceBreathsPerMin": targets.SlowBreathsPerMin,
			"note": "Apple Health mindful minutes also count, and the larger of Health and the minutes you log is used, never the sum."}}
}

// find returns the target with the key.
func (r targetsResponse) find(key string) (targetJSON, bool) {
	for _, t := range r.Targets {
		if t.Key == key {
			return t, true
		}
	}
	return targetJSON{}, false
}

// baselineInputs is the comparable snapshot of the inputs a baseline was computed from.
func (d targetData) baselineInputs() map[string]any {
	in := map[string]any{"goal": d.User.GoalKind, "paceKgPerWeek": d.User.GoalPaceKg}
	if d.WeightKg != nil {
		in[inWeight] = *d.WeightKg
	}
	if d.HeightCm != nil {
		in[inHeight] = *d.HeightCm
	}
	if d.Age != nil {
		in[inAge] = *d.Age
	}
	if d.Sex != nil {
		in[inSex] = string(*d.Sex)
	}
	if d.StepAvgDays >= insights.MinSuggestionDays {
		in["palBand"] = targets.PALForSteps(d.StepAvg14).Band
	}
	return in
}

func (s *Server) handleGetTargets(w http.ResponseWriter, r *http.Request) {
	c := callerFrom(r)
	d, err := s.loadTargetData(r.Context(), s.db.Pool, c.user, c.loc)
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, computeTargets(d))
}

type applyTargetsRequest struct {
	Keys []string `json:"keys"`
}

// applyTargetsResponse is the refreshed profile, plus the keys that were applied.
type applyTargetsResponse struct {
	meJSON
	Applied []string `json:"applied"`
}

// handleApplyTargets sets the chosen targets through the same path as PATCH /api/me: food targets
// on the profile, quest targets on the templates. Open days are scored first, so a change starts
// tomorrow, except on the join day.
func (s *Server) handleApplyTargets(w http.ResponseWriter, r *http.Request) {
	var req applyTargetsRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	if len(req.Keys) == 0 {
		fail(w, r, invalid("keys must name at least one target"))
		return
	}
	c := callerFrom(r)
	ctx := r.Context()
	d, err := s.loadTargetData(ctx, s.db.Pool, c.user, c.loc)
	if err != nil {
		fail(w, r, err)
		return
	}
	computed := computeTargets(d)

	user := c.user
	patch := patchMeRequest{}
	var applied []string
	var baselines []string
	seen := map[string]bool{}
	for _, key := range req.Keys {
		if seen[key] {
			continue
		}
		seen[key] = true
		t, ok := computed.find(key)
		if !ok || !t.Applicable {
			fail(w, r, invalid(key+" cannot be applied"))
			return
		}
		if t.Value == nil {
			fail(w, r, invalid(key+" has no value yet: "+strings.Join(t.Missing, ", ")+" missing"))
			return
		}
		v := *t.Value
		switch key {
		case tgtCalories:
			user.KcalTarget = &v
			baselines = append(baselines, tgtCalories)
		case tgtProtein:
			user.ProteinTarget = &v
			baselines = append(baselines, tgtProtein)
		case tgtFat:
			user.FatTarget = &v
		case tgtCarbs:
			user.CarbsTarget = &v
		case tgtSteps:
			patch.QuestTemplates = append(patch.QuestTemplates, templatePatch{Key: db.QuestSteps, Target: &v})
		case tgtExercise:
			patch.QuestTemplates = append(patch.QuestTemplates, templatePatch{Key: db.QuestExercise, Target: &v})
		case tgtSleep:
			patch.QuestTemplates = append(patch.QuestTemplates, templatePatch{Key: db.QuestSleep, Target: &v})
		case tgtWater:
			patch.QuestTemplates = append(patch.QuestTemplates, templatePatch{Key: db.QuestWater, Target: &v})
		case tgtProduce:
			patch.QuestTemplates = append(patch.QuestTemplates, templatePatch{Key: db.QuestProduce, Target: &v})
		case tgtBreathing:
			patch.QuestTemplates = append(patch.QuestTemplates, templatePatch{Key: db.QuestBreathing, Target: &v})
		case tgtPushups:
			patch.QuestTemplates = append(patch.QuestTemplates, templatePatch{Key: db.QuestPushups, Target: &v})
		}
		if key == tgtCalories || key == tgtProtein || key == tgtFat || key == tgtCarbs {
			patch.Targets = &targetsPatch{}
		}
		applied = append(applied, key)
	}

	inputs := d.baselineInputs()
	err = s.commitPatch(ctx, c, user, "", patch, func(tx pgx.Tx) error {
		for _, key := range baselines {
			t, _ := computed.find(key)
			if err := db.SetTargetBaseline(ctx, tx, user.ID, key, float64(*t.Value), inputs, d.Today); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	fresh, err := db.GetUser(ctx, s.db.Pool, user.ID)
	if err != nil {
		fail(w, r, err)
		return
	}
	me, err := s.buildMe(ctx, s.db.Pool, fresh)
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, applyTargetsResponse{meJSON: me, Applied: applied})
}

// maxPushupMax is the most reps a max test may record, mirroring the table check.
const maxPushupMax = 1000

type pushupMaxRequest struct {
	Reps int     `json:"reps"`
	Date *string `json:"date"`
}

type pushupMaxJSON struct {
	Date score.Date `json:"date"`
	Reps int        `json:"reps"`
}

// handleRecordPushupMax records a max test: one set to near failure. Testing again on the same
// day replaces the earlier test. It does not change the quest target; applying the push-ups
// target does.
func (s *Server) handleRecordPushupMax(w http.ResponseWriter, r *http.Request) {
	var req pushupMaxRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	if req.Reps < 1 || req.Reps > maxPushupMax {
		fail(w, r, invalid(fmt.Sprintf("reps must be between 1 and %d", maxPushupMax)))
		return
	}
	c := callerFrom(r)
	today := score.LocalToday(s.now(), c.loc)
	date := today
	if req.Date != nil {
		var herr *httpError
		if date, herr = parseDateParam(*req.Date, today); herr != nil {
			fail(w, r, herr)
			return
		}
	}
	if date.After(today) || !s.writable(c.user, c.loc, date) {
		fail(w, r, errDateClosed)
		return
	}
	if err := db.SetPushupMax(r.Context(), s.db.Pool, c.user.ID, date, req.Reps); err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, pushupMaxJSON{Date: date, Reps: req.Reps})
}
