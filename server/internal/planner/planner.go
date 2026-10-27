// Package planner asks Claude for a training plan and holds it to the evidence limits in the
// training package before anything is saved.
package planner

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strings"

	"github.com/nc1107/new-me/server/internal/anthropic"
	"github.com/nc1107/new-me/server/internal/training"
)

// ErrInvalid means the model's plan still broke the rules after the repair round.
var ErrInvalid = errors.New("planner: plan breaks the training rules")

// InvalidPlan carries the violations of a rejected plan.
type InvalidPlan struct {
	Violations []training.Violation
}

func (e *InvalidPlan) Error() string { return ErrInvalid.Error() }
func (e *InvalidPlan) Unwrap() error { return ErrInvalid }

// Exercise is one catalog exercise offered to the model.
type Exercise struct {
	Key            string
	Name           string
	PrimaryMuscles []string
	Timed          bool
	Loaded         bool
	Equipment      []string
}

// Input is everything a plan is built from.
type Input struct {
	Profile training.Profile
	// Focus is the person's own words about what they want.
	Focus string
	// Goal is lose, maintain or gain from the v8 profile, empty when unset.
	Goal string
	// Workdays are ISO weekdays (1 Monday) the person works, which the model should avoid
	// stacking long sessions on.
	Workdays []int
	Catalog  []Exercise
	Weeks    int
	// Current and Change are set when rewriting an existing plan.
	Current *training.Plan
	Change  string
}

// Planner wraps the Claude client.
type Planner struct {
	Client *anthropic.Client
}

const systemPrompt = `You design resistance-training plans for a personal habit app.
Answer only by calling the tool. Use only exercise keys from the catalog given. Build a weekly
template that repeats for the block. Respect every limit you are given exactly: they come from
published guidelines and the server rejects plans that break them. Prefer compound exercises,
balance pushing and pulling, and match the person's focus. Keep notes to one or two short
sentences in plain words.`

var toolSchema = map[string]any{
	"type": "object",
	"properties": map[string]any{
		"weeks": map[string]any{"type": "integer"},
		"notes": map[string]any{"type": "string"},
		"days": map[string]any{
			"type": "array",
			"items": map[string]any{
				"type": "object",
				"properties": map[string]any{
					"label":   map[string]any{"type": "string"},
					"weekday": map[string]any{"type": "integer", "description": "1 is Monday, 7 is Sunday"},
					"exercises": map[string]any{
						"type": "array",
						"items": map[string]any{
							"type": "object",
							"properties": map[string]any{
								"exercise": map[string]any{"type": "string"},
								"sets":     map[string]any{"type": "integer"},
								"min":      map[string]any{"type": "integer", "description": "bottom of the rep range, or seconds for timed exercises"},
								"max":      map[string]any{"type": "integer", "description": "top of the rep range, or seconds for timed exercises"},
								"rir":      map[string]any{"type": "integer", "description": "target reps in reserve"},
								"restSec":  map[string]any{"type": "integer"},
							},
							"required": []string{"exercise", "sets", "min", "max", "rir", "restSec"},
						},
					},
				},
				"required": []string{"label", "weekday", "exercises"},
			},
		},
	},
	"required": []string{"weeks", "notes", "days"},
}

type wirePlan struct {
	Weeks int    `json:"weeks"`
	Notes string `json:"notes"`
	Days  []struct {
		Label     string `json:"label"`
		Weekday   int    `json:"weekday"`
		Exercises []struct {
			Exercise string `json:"exercise"`
			Sets     int    `json:"sets"`
			Min      int    `json:"min"`
			Max      int    `json:"max"`
			RIR      int    `json:"rir"`
			RestSec  int    `json:"restSec"`
		} `json:"exercises"`
	} `json:"days"`
}

func (w wirePlan) plan() training.Plan {
	p := training.Plan{Weeks: w.Weeks, Notes: strings.TrimSpace(w.Notes)}
	for _, d := range w.Days {
		day := training.PlanDay{Label: strings.TrimSpace(d.Label), Weekday: d.Weekday}
		for _, e := range d.Exercises {
			day.Exercises = append(day.Exercises, training.Prescription{Exercise: e.Exercise, Sets: e.Sets,
				Min: e.Min, Max: e.Max, RIR: e.RIR, RestSec: e.RestSec})
		}
		p.Days = append(p.Days, day)
	}
	return p
}

// Generate asks for a plan, validates it, sends the violations back once, and returns a valid
// plan or an *InvalidPlan.
func (p *Planner) Generate(ctx context.Context, in Input) (training.Plan, error) {
	catalog := map[string]training.CatalogEntry{}
	for _, e := range in.Catalog {
		catalog[e.Key] = training.CatalogEntry{Key: e.Key, PrimaryMuscles: e.PrimaryMuscles, Timed: e.Timed, Equipment: e.Equipment}
	}
	prompt := Prompt(in)
	plan, err := p.ask(ctx, prompt)
	if err != nil {
		return training.Plan{}, err
	}
	violations := training.Validate(plan, in.Profile, catalog)
	if len(violations) == 0 {
		return plan, nil
	}
	repair := prompt + "\n\nYour previous plan broke these rules; return a corrected plan:\n" + listViolations(violations)
	if plan, err = p.ask(ctx, repair); err != nil {
		return training.Plan{}, err
	}
	if violations = training.Validate(plan, in.Profile, catalog); len(violations) == 0 {
		return plan, nil
	}
	return training.Plan{}, &InvalidPlan{Violations: violations}
}

func (p *Planner) ask(ctx context.Context, prompt string) (training.Plan, error) {
	raw, err := p.Client.ToolInput(ctx, anthropic.Request{
		System: systemPrompt, User: []anthropic.Block{{Text: prompt}}, MaxTokens: 4000,
		Tool: &anthropic.Tool{Name: "submit_plan", Description: "Submit the weekly training plan.", Schema: toolSchema},
	})
	if err != nil {
		return training.Plan{}, err
	}
	var w wirePlan
	if err := json.Unmarshal(raw, &w); err != nil {
		return training.Plan{}, fmt.Errorf("planner: decode plan: %w", err)
	}
	return w.plan(), nil
}

// Prompt is the user message: the person, the limits and the allowed exercises. Exported so
// tests can check the limits reach the model.
func Prompt(in Input) string {
	r := training.WeeklySetRange(in.Profile.Experience)
	var b strings.Builder
	fmt.Fprintf(&b, "Training days a week: %d\n", in.Profile.DaysPerWeek)
	fmt.Fprintf(&b, "Minutes per session: %d (estimate each set as %d seconds of work plus its rest; stay within %d%% of this)\n",
		in.Profile.SessionMinutes, training.WorkSecondsPerSet, int((training.TimeSlack-1)*100))
	fmt.Fprintf(&b, "Experience: %s\n", in.Profile.Experience)
	fmt.Fprintf(&b, "Equipment: %s\n", strings.Join(orNone(in.Profile.Equipment), ", "))
	if in.Goal != "" {
		fmt.Fprintf(&b, "Body-weight goal: %s\n", in.Goal)
	}
	if len(in.Workdays) > 0 {
		days := make([]string, len(in.Workdays))
		for i, d := range in.Workdays {
			days[i] = fmt.Sprint(d)
		}
		fmt.Fprintf(&b, "Workdays (ISO weekday numbers): %s\n", strings.Join(days, ", "))
	}
	if f := strings.TrimSpace(in.Focus); f != "" {
		fmt.Fprintf(&b, "Their focus in their own words: %q\n", f)
	}
	weeks := in.Weeks
	if weeks == 0 {
		weeks = training.MinWeeks
	}
	fmt.Fprintf(&b, "\nLimits (all required):\n")
	fmt.Fprintf(&b, "- Block of %d weeks (allowed %d to %d).\n", weeks, training.MinWeeks, training.MaxWeeks)
	fmt.Fprintf(&b, "- Exactly %d training days, each on its own weekday.\n", in.Profile.DaysPerWeek)
	fmt.Fprintf(&b, "- Muscle-strengthening work on at least %d days (WHO 2020).\n", training.MinStrengthDays)
	fmt.Fprintf(&b, "- Weekly sets per muscle group (count each exercise's sets for every primary muscle): between %d and %d; chest, back, shoulders, quads, and hamstrings or glutes must each reach %d (%s).\n",
		r.Min, r.Max, r.Min, r.Label)
	fmt.Fprintf(&b, "- Reps in reserve 0 to %d; 1 to %d sets per exercise; rep ranges within 1 to %d, or %d to %d seconds for timed exercises; rest %d to %d seconds.\n",
		training.MaxRIR, training.MaxSetsPerExercise, training.MaxRepsInRange, training.MinSeconds, training.MaxSeconds,
		training.MinRestSec, training.MaxRestSec)
	if in.Current != nil {
		current, _ := json.Marshal(in.Current)
		fmt.Fprintf(&b, "\nCurrent plan:\n%s\nRequested change: %s\nChange only what the request needs.\n", current, in.Change)
	}
	fmt.Fprintf(&b, "\nCatalog (key: name; primary muscles; measure; equipment):\n")
	exercises := slicesSorted(in.Catalog)
	for _, e := range exercises {
		measure := "reps"
		if e.Timed {
			measure = "seconds"
		}
		if e.Loaded {
			measure += ", loaded"
		}
		fmt.Fprintf(&b, "- %s: %s; %s; %s; %s\n", e.Key, e.Name, strings.Join(e.PrimaryMuscles, "+"), measure,
			strings.Join(orNone(e.Equipment), "+"))
	}
	return b.String()
}

func listViolations(v []training.Violation) string {
	var b strings.Builder
	for _, x := range v {
		fmt.Fprintf(&b, "- %s\n", x.Message)
	}
	return b.String()
}

func orNone(s []string) []string {
	if len(s) == 0 {
		return []string{"none"}
	}
	return s
}

func slicesSorted(in []Exercise) []Exercise {
	out := append([]Exercise(nil), in...)
	sort.SliceStable(out, func(i, j int) bool { return out[i].Key < out[j].Key })
	return out
}
