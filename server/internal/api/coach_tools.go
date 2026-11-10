package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/http"
	"slices"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/coach"
	"github.com/nc1107/new-me/server/internal/db"
)

const (
	// proposalLife is how long a card stays appliable.
	proposalLife = 24 * time.Hour
	// undoWindow bounds Undo so it cannot overwrite changes made long after.
	undoWindow = 24 * time.Hour

	codeProposalExpired = "proposal_expired"
	codeProposalState   = "proposal_state"
)

var (
	errProposalExpired = newErr(http.StatusGone, codeProposalExpired, "this suggestion expired, ask the coach again")
	errProposalState   = newErr(http.StatusConflict, codeProposalState, "this suggestion was already settled")
	errNoCoachItem     = newErr(http.StatusNotFound, codeNotFound, "that is not something the coach has for you")
)

// coachState is the part of a person's settings a proposal writes. It is the same shape before
// and after, so Undo is Apply of what Apply replaced. A nil field is left alone.
type coachState struct {
	Quests    []coachQuest    `json:"quests,omitempty"`
	Food      map[string]*int `json:"food,omitempty"`
	Training  *coachTraining  `json:"training,omitempty"`
	Height    *coachNum       `json:"height,omitempty"`
	BirthYear *coachNum       `json:"birthYear,omitempty"`
	Units     *string         `json:"units,omitempty"`
	Goal      *coachGoal      `json:"goal,omitempty"`
	Accept    string          `json:"accept,omitempty"`
}

type coachQuest struct {
	Key     string `json:"key"`
	Target  int    `json:"target"`
	Enabled *bool  `json:"enabled,omitempty"`
}

// coachNum holds a number that may be cleared, so a nil V is "no value".
type coachNum struct {
	V *float64 `json:"v"`
}

type coachTraining struct {
	Days    *int `json:"days,omitempty"`
	Minutes *int `json:"minutes,omitempty"`
}

type coachGoal struct {
	Kind   string  `json:"kind"`
	PaceKg float64 `json:"paceKg"`
}

// coachChangeLine is one row of a card: a label, what it is now and what it would become.
type coachChangeLine struct {
	Label string `json:"label"`
	From  string `json:"from"`
	To    string `json:"to"`
}

// coachStored is what a proposal keeps in after_state.
type coachStored struct {
	State   coachState        `json:"state"`
	Changes []coachChangeLine `json:"changes"`
	// Source is computed, guideline or stated: where the figure came from.
	Source string `json:"source"`
}

type coachProposalJSON struct {
	ID        int64             `json:"id"`
	Kind      string            `json:"kind"`
	Summary   string            `json:"summary"`
	Changes   []coachChangeLine `json:"changes"`
	Why       string            `json:"why"`
	Source    string            `json:"source"`
	Status    string            `json:"status"`
	ExpiresAt string            `json:"expiresAt"`
	CanUndo   bool              `json:"canUndo"`
}

type coachFactJSON struct {
	ID        int64  `json:"id"`
	Category  string `json:"category"`
	Text      string `json:"text"`
	CreatedAt string `json:"createdAt"`
}

// coachAction is something the coach did while answering, shown under its message.
type coachAction struct {
	Type     string             `json:"type"`
	Proposal *coachProposalJSON `json:"proposal,omitempty"`
	Fact     *coachFactJSON     `json:"fact,omitempty"`
}

func toFactJSON(f db.CoachFact) coachFactJSON {
	return coachFactJSON{ID: f.ID, Category: f.Category, Text: f.Text, CreatedAt: wireTime(f.CreatedAt)}
}

func (s *Server) toProposalJSON(p db.CoachProposal) coachProposalJSON {
	var stored coachStored
	_ = json.Unmarshal(p.After, &stored)
	status := p.Status
	now := s.now()
	if status == db.ProposalPendingStatus && !now.Before(p.ExpiresAt) {
		status = "expired"
	}
	canUndo := status == db.ProposalAppliedStatus && p.DecidedAt != nil && now.Before(p.DecidedAt.Add(undoWindow))
	why := ""
	if p.Reason != "" {
		why = p.Reason
	}
	return coachProposalJSON{ID: p.ID, Kind: p.Kind, Summary: p.Summary, Changes: stored.Changes, Why: why,
		Source: stored.Source, Status: status, ExpiresAt: wireTime(p.ExpiresAt), CanUndo: canUndo}
}

// coachQuestTarget maps a quest to the computed target that prices it, where one exists.
var coachQuestTarget = map[string]string{
	db.QuestSteps: tgtSteps, db.QuestExercise: tgtExercise, db.QuestSleep: tgtSleep, db.QuestWater: tgtWater,
	db.QuestProduce: tgtProduce, db.QuestBreathing: tgtBreathing, db.QuestReading: tgtReading, db.QuestPushups: tgtPushups,
}

// coachQuestBounds mirrors quest_target_ok, so a bad figure is refused with a sentence instead
// of a database error.
var coachQuestBounds = map[string][2]int{
	db.QuestSteps: {1, 100000}, db.QuestPushups: {1, 500}, db.QuestReading: {1, 1440}, db.QuestMealsLogged: {1, 20}, db.QuestCalories: {5, 30},
	db.QuestYoga: {1, 1440}, db.QuestExercise: {5, 300}, db.QuestSleep: {240, 720}, db.QuestWater: {250, 6000},
	db.QuestProduce: {1, 30}, db.QuestBreathing: {1, 60},
}

var minuteFactors = []coach.Factor{{Mul: 1, Tol: 0.5}, {Mul: 60, Tol: 0.5}}

// coachQuestFactors lists the units a person may have used for a quest's figure.
func coachQuestFactors(key string) []coach.Factor {
	switch key {
	case db.QuestSleep, db.QuestExercise, db.QuestYoga, db.QuestBreathing, db.QuestReading:
		return minuteFactors
	case db.QuestWater:
		return []coach.Factor{{Mul: 1, Tol: 0.5}, {Mul: 1000, Tol: 5}, {Mul: mlPerFlOz, Tol: mlPerFlOz / 2}, {Mul: 236.588, Tol: 118}}
	}
	return coach.Same
}

var coachFoodTarget = map[string]string{"calories": tgtCalories, "protein": tgtProtein, "fat": tgtFat, "carbs": tgtCarbs}

var coachFoodBounds = map[string][2]int{"calories": {1, maxKcalTarget}, "protein": {1, maxMacroTarget}, "fat": {1, maxMacroTarget}, "carbs": {1, maxMacroTarget}}

var coachFoodLabel = map[string]string{"calories": "Calorie target", "protein": "Protein target", "fat": "Fat target", "carbs": "Carbs target"}

func userFoodTarget(u db.User, key string) *int {
	switch key {
	case "calories":
		return u.KcalTarget
	case "protein":
		return u.ProteinTarget
	case "fat":
		return u.FatTarget
	case "carbs":
		return u.CarbsTarget
	}
	return nil
}

// questValueText words a quest figure in the units the app shows the person.
func questValueText(u db.User, key string, v int) string {
	switch key {
	case db.QuestSteps:
		return th(float64(v)) + " steps"
	case db.QuestSleep:
		return hours(float64(v))
	case db.QuestWater:
		return volumeText(u, v)
	case db.QuestExercise, db.QuestBreathing, db.QuestReading, db.QuestYoga:
		return fmt.Sprintf("%d min", v)
	case db.QuestPushups:
		return fmt.Sprintf("%d reps", v)
	case db.QuestProduce:
		return fmt.Sprintf("%d servings", v)
	}
	return fmt.Sprint(v)
}

func foodValueText(key string, v int) string {
	if key == "calories" {
		return th(float64(v)) + " kcal"
	}
	return th(float64(v)) + " g"
}

// coachTools runs the tool calls of one chat message for one person. Every tool reads and writes
// the caller's own rows only; there is no argument that names another person.
type coachTools struct {
	s       *Server
	c       caller
	turns   []coach.ChatTurn
	actions []coachAction

	computed *targetsResponse
	data     targetData
}

func (t *coachTools) targets(ctx context.Context) (targetsResponse, error) {
	if t.computed == nil {
		d, err := t.s.loadTargetData(ctx, t.s.db.Pool, t.c.user, t.c.loc)
		if err != nil {
			return targetsResponse{}, err
		}
		t.data = d
		r := computeTargets(d)
		t.computed = &r
	}
	return *t.computed, nil
}

func refuse(format string, args ...any) coach.ToolResult {
	return coach.ToolResult{Text: fmt.Sprintf(format, args...), IsError: true}
}

// Run executes one tool call.
func (t *coachTools) Run(ctx context.Context, name string, input json.RawMessage) coach.ToolResult {
	switch name {
	case coach.ToolQuestTarget:
		var in struct {
			Quest      string `json:"quest"`
			Value      int    `json:"value"`
			StatedText string `json:"stated_text"`
		}
		if json.Unmarshal(input, &in) != nil {
			return refuse("The arguments were not understood.")
		}
		return t.proposeQuestTarget(ctx, in.Quest, in.Value, in.StatedText)
	case coach.ToolFoodTarget:
		var in struct {
			Target     string `json:"target"`
			Value      int    `json:"value"`
			StatedText string `json:"stated_text"`
		}
		if json.Unmarshal(input, &in) != nil {
			return refuse("The arguments were not understood.")
		}
		return t.proposeFoodTarget(ctx, in.Target, in.Value, in.StatedText)
	case coach.ToolTrainingPlan:
		var in struct {
			Days       *int   `json:"days_per_week"`
			Minutes    *int   `json:"session_minutes"`
			StatedText string `json:"stated_text"`
		}
		if json.Unmarshal(input, &in) != nil {
			return refuse("The arguments were not understood.")
		}
		return t.proposeTraining(ctx, in.Days, in.Minutes, in.StatedText)
	case coach.ToolWeightGoal:
		var in struct {
			Kind       string  `json:"kind"`
			Pace       float64 `json:"pace_kg_per_week"`
			StatedText string  `json:"stated_text"`
		}
		if json.Unmarshal(input, &in) != nil {
			return refuse("The arguments were not understood.")
		}
		return t.proposeWeightGoal(ctx, in.Kind, in.Pace, in.StatedText)
	case coach.ToolBodyInfo:
		var in struct {
			HeightCm   *float64 `json:"height_cm"`
			BirthYear  *int     `json:"birth_year"`
			Units      *string  `json:"units"`
			StatedText string   `json:"stated_text"`
		}
		if json.Unmarshal(input, &in) != nil {
			return refuse("The arguments were not understood.")
		}
		return t.proposeBody(ctx, in.HeightCm, in.BirthYear, in.Units, in.StatedText)
	case coach.ToolWeeklyGoal:
		var in struct {
			Key string `json:"key"`
		}
		if json.Unmarshal(input, &in) != nil {
			return refuse("The arguments were not understood.")
		}
		return t.proposeWeekly(ctx, in.Key)
	case coach.ToolRememberFact:
		var in struct {
			Category string `json:"category"`
			Text     string `json:"text"`
		}
		if json.Unmarshal(input, &in) != nil {
			return refuse("The arguments were not understood.")
		}
		return t.remember(ctx, in.Category, in.Text)
	case coach.ToolForgetFact:
		var in struct {
			ID int64 `json:"id"`
		}
		if json.Unmarshal(input, &in) != nil {
			return refuse("The arguments were not understood.")
		}
		return t.forget(ctx, in.ID)
	}
	return refuse("There is no tool called %s.", name)
}

// figureSource says where a proposed figure comes from, or why it may not be used. A figure is
// allowed when it is the app's computed value, one of its published alternatives, or a number
// in words the person wrote.
func (t *coachTools) figureSource(tg targetJSON, hasTarget bool, value int, quote string, factors []coach.Factor, render func(int) string) (source, why string, err string) {
	if hasTarget && tg.Value != nil && *tg.Value == value {
		why = tg.Why
		if why == "" {
			why = tg.Formula
		}
		if tg.Cite != "" {
			why += " (" + tg.Cite + ")"
		}
		return "computed", why, ""
	}
	if hasTarget {
		for _, a := range tg.Alternatives {
			if a.Value == value {
				why = a.Label
				if tg.Cite != "" {
					why += " (" + tg.Cite + ")"
				}
				return "guideline", why, ""
			}
		}
	}
	if coach.QuoteIsFromPerson(quote, t.turns) && coach.Matches(float64(value), quote, factors) {
		return "stated", "You asked for this number.", ""
	}
	var options []string
	if hasTarget && tg.Value != nil {
		options = append(options, render(*tg.Value)+" (computed)")
	}
	if hasTarget {
		for _, a := range tg.Alternatives {
			options = append(options, render(a.Value)+" ("+a.Label+")")
		}
	}
	msg := "That number is not in DATA and the person did not say it. "
	if len(options) > 0 {
		msg += "Allowed: " + strings.Join(options, "; ") + ". "
	}
	return "", "", msg + "Otherwise ask them what number they want and pass their exact words as stated_text."
}

func (t *coachTools) store(ctx context.Context, kind, summary, why string, stored coachStored) coach.ToolResult {
	raw, err := json.Marshal(stored)
	if err != nil {
		return refuse("Could not store the suggestion.")
	}
	if len(t.actions) >= 3 {
		return refuse("Enough suggestions for one message; ask which they want first.")
	}
	p, err := db.CreateCoachProposal(ctx, t.s.db.Pool, db.CoachProposal{UserID: t.c.user.ID, Kind: kind, Summary: summary,
		Reason: why, After: raw, ExpiresAt: t.s.now().Add(proposalLife)})
	if err != nil {
		return refuse("Could not store the suggestion.")
	}
	card := t.s.toProposalJSON(p)
	t.actions = append(t.actions, coachAction{Type: "proposal", Proposal: &card})
	return coach.ToolResult{Text: fmt.Sprintf("Shown to the person as a card: %s. It is not changed until they tap Apply, so do not say it is.", summary)}
}

func (t *coachTools) proposeQuestTarget(ctx context.Context, quest string, value int, quote string) coach.ToolResult {
	bounds, ok := coachQuestBounds[quest]
	if !ok {
		return refuse("%s is not a quest with a target.", quest)
	}
	if value < bounds[0] || value > bounds[1] {
		return refuse("%s must be between %d and %d.", quest, bounds[0], bounds[1])
	}
	templates, err := db.GetQuestTemplates(ctx, t.s.db.Pool, t.c.user.ID)
	if err != nil {
		return refuse("Could not read their quests.")
	}
	idx := slices.IndexFunc(templates, func(q db.QuestTemplate) bool { return q.Key == quest })
	if idx < 0 {
		return refuse("They have no %s quest.", quest)
	}
	tmpl := templates[idx]
	if tmpl.Target == value {
		return refuse("%s is already %s.", questTitle(quest), questValueText(t.c.user, quest, value))
	}
	all, err := t.targets(ctx)
	if err != nil {
		return refuse("Could not read their targets.")
	}
	tg, hasTarget := all.find(coachQuestTarget[quest])
	if coachQuestTarget[quest] == "" {
		hasTarget = false
	}
	render := func(v int) string { return questValueText(t.c.user, quest, v) }
	source, why, bad := t.figureSource(tg, hasTarget, value, quote, coachQuestFactors(quest), render)
	if bad != "" {
		return refuse("%s", bad)
	}
	title := questTitleFor(quest, tmpl.Exercise) + " goal"
	line := coachChangeLine{Label: title, From: render(tmpl.Target), To: render(value)}
	return t.store(ctx, "quest_target", title+" "+line.From+" -> "+line.To, why, coachStored{
		State: coachState{Quests: []coachQuest{{Key: quest, Target: value}}}, Changes: []coachChangeLine{line}, Source: source})
}

func (t *coachTools) proposeFoodTarget(ctx context.Context, target string, value int, quote string) coach.ToolResult {
	bounds, ok := coachFoodBounds[target]
	if !ok {
		return refuse("%s is not a food target.", target)
	}
	if value < bounds[0] || value > bounds[1] {
		return refuse("%s must be between %d and %d.", target, bounds[0], bounds[1])
	}
	cur := userFoodTarget(t.c.user, target)
	if cur != nil && *cur == value {
		return refuse("The %s target is already %s.", target, foodValueText(target, value))
	}
	all, err := t.targets(ctx)
	if err != nil {
		return refuse("Could not read their targets.")
	}
	tg, hasTarget := all.find(coachFoodTarget[target])
	render := func(v int) string { return foodValueText(target, v) }
	source, why, bad := t.figureSource(tg, hasTarget && tg.Applicable, value, quote, coach.Same, render)
	if bad != "" {
		return refuse("%s", bad)
	}
	from := "not set"
	if cur != nil {
		from = render(*cur)
	}
	line := coachChangeLine{Label: coachFoodLabel[target], From: from, To: render(value)}
	return t.store(ctx, "food_target", line.Label+" "+line.From+" -> "+line.To, why, coachStored{
		State: coachState{Food: map[string]*int{target: &value}}, Changes: []coachChangeLine{line}, Source: source})
}

func (t *coachTools) proposeTraining(ctx context.Context, days, minutes *int, quote string) coach.ToolResult {
	if days == nil && minutes == nil {
		return refuse("Give days_per_week, session_minutes or both.")
	}
	cur, err := db.GetTrainingProfile(ctx, t.s.db.Pool, t.c.user.ID)
	if errors.Is(err, db.ErrNotFound) {
		return refuse("They have not set up training yet. Tell them to open Training and answer the setup questions first.")
	}
	if err != nil {
		return refuse("Could not read their training profile.")
	}
	next := toTrainingProfileJSON(cur)
	var changes []coachChangeLine
	if days != nil && *days != cur.DaysPerWeek {
		if !coach.QuoteIsFromPerson(quote, t.turns) || !coach.Matches(float64(*days), quote, coach.Same) {
			return refuse("The number of days must be one the person said; pass their exact words as stated_text.")
		}
		next.DaysPerWeek = *days
		changes = append(changes, coachChangeLine{Label: "Training days a week", From: fmt.Sprint(cur.DaysPerWeek), To: fmt.Sprint(*days)})
	}
	if minutes != nil && *minutes != cur.SessionMinutes {
		if !coach.QuoteIsFromPerson(quote, t.turns) || !coach.Matches(float64(*minutes), quote, minuteFactors) {
			return refuse("The session length must be one the person said; pass their exact words as stated_text.")
		}
		next.SessionMinutes = *minutes
		changes = append(changes, coachChangeLine{Label: "Session length", From: fmt.Sprintf("%d min", cur.SessionMinutes), To: fmt.Sprintf("%d min", *minutes)})
	}
	if len(changes) == 0 {
		return refuse("Their training profile already has those values.")
	}
	if _, herr := validTrainingProfile(next); herr != nil {
		return refuse("%s", herr.msg)
	}
	state := coachState{Training: &coachTraining{}}
	parts := make([]string, len(changes))
	for i, ch := range changes {
		parts[i] = ch.Label + " " + ch.From + " -> " + ch.To
		switch ch.Label {
		case "Session length":
			state.Training.Minutes = minutes
		default:
			state.Training.Days = days
		}
	}
	return t.store(ctx, "training_profile", strings.Join(parts, ", "), "You asked for this.", coachStored{State: state, Changes: changes, Source: "stated"})
}

func (t *coachTools) proposeWeightGoal(ctx context.Context, kind string, pace float64, quote string) coach.ToolResult {
	u := t.c.user
	probe := u
	if herr := applyGoal(&probe, &goalPatch{Kind: &kind, PaceKgPerWeek: &pace}); herr != nil {
		return refuse("%s", herr.msg)
	}
	if probe.GoalKind == u.GoalKind && probe.GoalPaceKg == u.GoalPaceKg {
		return refuse("That is already their goal.")
	}
	source := "stated"
	why := "You asked for this."
	if !coach.QuoteIsFromPerson(quote, t.turns) {
		return refuse("A weight goal must come from the person; pass their exact words as stated_text.")
	}
	if probe.GoalPaceKg > 0 {
		factors := []coach.Factor{{Mul: 1, Tol: 0.011}, {Mul: 1 / lbPerKg, Tol: 0.011}}
		if !coach.Matches(probe.GoalPaceKg, quote, factors) {
			return refuse("The pace must be a number the person said, in kg or lb a week; ask them how fast they want it.")
		}
	}
	describe := func(x db.User) string {
		if s := goalSentence(x); s != "" {
			return s
		}
		return "maintain weight"
	}
	line := coachChangeLine{Label: "Weight goal", From: describe(u), To: describe(probe)}
	return t.store(ctx, "weight_goal", "Weight goal "+line.From+" -> "+line.To, why, coachStored{
		State: coachState{Goal: &coachGoal{Kind: probe.GoalKind, PaceKg: probe.GoalPaceKg}}, Changes: []coachChangeLine{line}, Source: source})
}

func (t *coachTools) proposeBody(ctx context.Context, height *float64, birth *int, units *string, quote string) coach.ToolResult {
	if height == nil && birth == nil && units == nil {
		return refuse("Give height_cm, birth_year, units or several.")
	}
	if !coach.QuoteIsFromPerson(quote, t.turns) {
		return refuse("Body info must come from the person; pass their exact words as stated_text.")
	}
	u := t.c.user
	state := coachState{}
	var changes []coachChangeLine
	if height != nil {
		probe := u
		if herr := applyBody(&probe, patchMeRequest{HeightCm: nullable[float64]{Set: true, Value: height}}); herr != nil {
			return refuse("%s", herr.msg)
		}
		if !coach.HeightMatches(*height, quote) {
			return refuse("The height is not a number the person said.")
		}
		from := "not set"
		if u.HeightCm != nil {
			from = trim(*u.HeightCm, 1) + " cm"
		}
		state.Height = &coachNum{V: probe.HeightCm}
		changes = append(changes, coachChangeLine{Label: "Height", From: from, To: trim(*probe.HeightCm, 1) + " cm"})
	}
	if birth != nil {
		probe := u
		if herr := t.s.applyBirthYear(&probe, birth); herr != nil {
			return refuse("%s", herr.msg)
		}
		if !coach.BirthYearMatches(*birth, t.s.now().In(t.c.loc).Year(), quote) {
			return refuse("The birth year is not a number the person said.")
		}
		from := "not set"
		if u.BirthYear != nil {
			from = fmt.Sprint(*u.BirthYear)
		}
		v := float64(*birth)
		state.BirthYear = &coachNum{V: &v}
		changes = append(changes, coachChangeLine{Label: "Birth year", From: from, To: fmt.Sprint(*birth)})
	}
	if units != nil {
		if *units != db.UnitsMetric && *units != db.UnitsImperial {
			return refuse("units must be metric or imperial.")
		}
		state.Units = units
		changes = append(changes, coachChangeLine{Label: "Units", From: u.Units, To: *units})
	}
	parts := make([]string, len(changes))
	for i, ch := range changes {
		parts[i] = ch.Label + " " + ch.From + " -> " + ch.To
	}
	return t.store(ctx, "body", strings.Join(parts, ", "), "You told me this.", coachStored{State: state, Changes: changes, Source: "stated"})
}

func (t *coachTools) proposeWeekly(ctx context.Context, key string) coach.ToolResult {
	_, pending, err := t.s.weeklyProposals(ctx, t.c)
	if err != nil {
		return refuse("Could not read this week's suggestions.")
	}
	for _, p := range pending {
		if p.Key != key {
			continue
		}
		render := func(v int) string { return questValueText(t.c.user, key, v) }
		if key == proposalCalories {
			render = func(v int) string { return foodValueText("calories", v) }
		}
		if key == db.QuestProtein {
			render = func(v int) string { return foodValueText("protein", v) }
		}
		title := p.Title + " goal"
		line := coachChangeLine{Label: title, From: render(p.Current), To: render(p.Proposed)}
		return t.store(ctx, "goal_proposal", title+" "+line.From+" -> "+line.To, p.Reason, coachStored{
			State: coachState{Accept: key}, Changes: []coachChangeLine{line}, Source: "computed"})
	}
	return refuse("There is no pending suggestion with the key %q this week.", key)
}

func (t *coachTools) remember(ctx context.Context, category, text string) coach.ToolResult {
	text = strings.TrimSpace(text)
	switch {
	case !slices.Contains(db.CoachFactCategories, category):
		return refuse("category must be one of %s.", strings.Join(db.CoachFactCategories, ", "))
	case text == "" || utf8.RuneCountInString(text) > 200 || hasControlChars(text):
		return refuse("A fact is 1 to 200 characters of plain text.")
	}
	f, err := db.AddCoachFact(ctx, t.s.db.Pool, t.c.user.ID, category, text)
	if errors.Is(err, db.ErrCoachFactsFull) {
		return refuse("They already have %d saved facts. Ask which one to forget first.", db.MaxCoachFacts)
	}
	if err != nil {
		return refuse("Could not save that.")
	}
	card := toFactJSON(f)
	t.actions = append(t.actions, coachAction{Type: "fact_saved", Fact: &card})
	return coach.ToolResult{Text: fmt.Sprintf("Saved as fact %d. The person sees a note that it was saved to their profile.", f.ID)}
}

func (t *coachTools) forget(ctx context.Context, id int64) coach.ToolResult {
	facts, err := db.ListCoachFacts(ctx, t.s.db.Pool, t.c.user.ID)
	if err != nil {
		return refuse("Could not read their saved facts.")
	}
	idx := slices.IndexFunc(facts, func(f db.CoachFact) bool { return f.ID == id })
	if idx < 0 {
		return refuse("There is no saved fact %d.", id)
	}
	if err := db.DeleteCoachFact(ctx, t.s.db.Pool, t.c.user.ID, id); err != nil {
		return refuse("Could not forget that.")
	}
	card := toFactJSON(facts[idx])
	t.actions = append(t.actions, coachAction{Type: "fact_removed", Fact: &card})
	return coach.ToolResult{Text: "Forgotten."}
}

// captureCoachState reads the current values of exactly the fields after would write.
func (s *Server) captureCoachState(ctx context.Context, c caller, after coachState) (coachState, error) {
	var before coachState
	u, err := db.GetUser(ctx, s.db.Pool, c.user.ID)
	if err != nil {
		return before, err
	}
	if len(after.Quests) > 0 || after.Accept != "" {
		templates, err := db.GetQuestTemplates(ctx, s.db.Pool, u.ID)
		if err != nil {
			return before, err
		}
		keys := []string{}
		for _, q := range after.Quests {
			keys = append(keys, q.Key)
		}
		if after.Accept != "" && after.Accept != proposalCalories && after.Accept != db.QuestProtein {
			keys = append(keys, after.Accept)
		}
		for _, key := range keys {
			idx := slices.IndexFunc(templates, func(q db.QuestTemplate) bool { return q.Key == key })
			if idx < 0 {
				return before, invalid("unknown quest " + key)
			}
			enabled := templates[idx].Enabled
			before.Quests = append(before.Quests, coachQuest{Key: key, Target: templates[idx].Target, Enabled: &enabled})
		}
	}
	if len(after.Food) > 0 || after.Accept == proposalCalories || after.Accept == db.QuestProtein {
		before.Food = map[string]*int{}
		for key := range after.Food {
			before.Food[key] = userFoodTarget(u, key)
		}
		switch after.Accept {
		case proposalCalories:
			before.Food["calories"] = u.KcalTarget
		case db.QuestProtein:
			before.Food["protein"] = u.ProteinTarget
		}
	}
	if after.Training != nil {
		p, err := db.GetTrainingProfile(ctx, s.db.Pool, u.ID)
		if err != nil {
			return before, err
		}
		before.Training = &coachTraining{}
		if after.Training.Days != nil {
			before.Training.Days = intp(p.DaysPerWeek)
		}
		if after.Training.Minutes != nil {
			before.Training.Minutes = intp(p.SessionMinutes)
		}
	}
	if after.Height != nil {
		before.Height = &coachNum{V: u.HeightCm}
	}
	if after.BirthYear != nil {
		before.BirthYear = &coachNum{}
		if u.BirthYear != nil {
			v := float64(*u.BirthYear)
			before.BirthYear.V = &v
		}
	}
	if after.Units != nil {
		before.Units = &u.Units
	}
	if after.Goal != nil {
		before.Goal = &coachGoal{Kind: u.GoalKind, PaceKg: u.GoalPaceKg}
	}
	return before, nil
}

// applyCoachState writes a state through the same functions the settings pages call, so every
// bound and every rescoring rule applies as if the person had typed it there.
func (s *Server) applyCoachState(ctx context.Context, c caller, st coachState) error {
	req := patchMeRequest{}
	baselines := []string{}
	for _, q := range st.Quests {
		target := q.Target
		req.QuestTemplates = append(req.QuestTemplates, templatePatch{Key: q.Key, Target: &target, Enabled: q.Enabled})
	}
	if len(st.Food) > 0 {
		req.Targets = &targetsPatch{}
		for key, v := range st.Food {
			n := nullable[int]{Set: true, Value: v}
			switch key {
			case "calories":
				req.Targets.Kcal = n
				baselines = append(baselines, proposalCalories)
			case "protein":
				req.Targets.Protein = n
				baselines = append(baselines, db.QuestProtein)
			case "fat":
				req.Targets.Fat = n
			case "carbs":
				req.Targets.Carbs = n
			}
		}
	}
	if st.Height != nil {
		req.HeightCm = nullable[float64]{Set: true, Value: st.Height.V}
	}
	if st.BirthYear != nil {
		req.BirthYear = nullable[int]{Set: true}
		if st.BirthYear.V != nil {
			year := int(math.Round(*st.BirthYear.V))
			req.BirthYear.Value = &year
		}
	}
	req.Units = st.Units
	if st.Goal != nil {
		pace := st.Goal.PaceKg
		req.Goal = &goalPatch{Kind: &st.Goal.Kind, PaceKgPerWeek: &pace}
	}
	if st.Accept != "" {
		return s.acceptProposal(ctx, c, st.Accept)
	}
	hasPatch := len(req.QuestTemplates) > 0 || req.Targets != nil || req.HeightCm.Set || req.BirthYear.Set || req.Units != nil || req.Goal != nil
	if hasPatch {
		err := s.patchMe(ctx, c, req, func(tx pgx.Tx) error {
			for _, key := range baselines {
				if err := s.refreshBaseline(ctx, tx, c, key); err != nil {
					return err
				}
			}
			return nil
		})
		if err != nil {
			return err
		}
	}
	if st.Training != nil {
		cur, err := db.GetTrainingProfile(ctx, s.db.Pool, c.user.ID)
		if err != nil {
			return err
		}
		next := toTrainingProfileJSON(cur)
		if st.Training.Days != nil {
			next.DaysPerWeek = *st.Training.Days
		}
		if st.Training.Minutes != nil {
			next.SessionMinutes = *st.Training.Minutes
		}
		if _, err := s.putTrainingProfile(ctx, c, next); err != nil {
			return err
		}
	}
	return nil
}

func pathID(r *http.Request) (int64, *httpError) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id < 1 {
		return 0, errNoCoachItem
	}
	return id, nil
}

// loadCoachProposal finds one of the caller's own proposals; anyone else's is not found.
func (s *Server) loadCoachProposal(ctx context.Context, c caller, id int64) (db.CoachProposal, error) {
	p, err := db.GetCoachProposal(ctx, s.db.Pool, c.user.ID, id)
	if errors.Is(err, db.ErrNotFound) {
		return p, errNoCoachItem
	}
	return p, err
}

func (s *Server) handleApplyCoachProposal(w http.ResponseWriter, r *http.Request) {
	s.decideCoachProposal(w, r, "apply")
}

func (s *Server) handleDismissCoachProposal(w http.ResponseWriter, r *http.Request) {
	s.decideCoachProposal(w, r, "dismiss")
}

func (s *Server) handleUndoCoachProposal(w http.ResponseWriter, r *http.Request) {
	s.decideCoachProposal(w, r, "undo")
}

func (s *Server) handleGetCoachProposal(w http.ResponseWriter, r *http.Request) {
	if s.chatter == nil {
		fail(w, r, errCoachDisabled)
		return
	}
	id, herr := pathID(r)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	p, err := s.loadCoachProposal(r.Context(), callerFrom(r), id)
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, s.toProposalJSON(p))
}

// decideCoachProposal applies, dismisses or undoes a card. Each is idempotent: repeating it
// returns the settled card instead of repeating the change.
func (s *Server) decideCoachProposal(w http.ResponseWriter, r *http.Request, action string) {
	if s.chatter == nil {
		fail(w, r, errCoachDisabled)
		return
	}
	id, herr := pathID(r)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	c := callerFrom(r)
	ctx := r.Context()
	p, err := s.loadCoachProposal(ctx, c, id)
	if err != nil {
		fail(w, r, err)
		return
	}
	if err := s.settleCoachProposal(ctx, c, &p, action); err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, s.toProposalJSON(p))
}

func (s *Server) settleCoachProposal(ctx context.Context, c caller, p *db.CoachProposal, action string) error {
	now := s.now()
	var stored coachStored
	if err := json.Unmarshal(p.After, &stored); err != nil {
		return err
	}
	move := func(from, to string, before json.RawMessage) (bool, error) {
		return db.MoveCoachProposal(ctx, s.db.Pool, c.user.ID, p.ID, from, to, before, now)
	}
	reload := func() error {
		fresh, err := s.loadCoachProposal(ctx, c, p.ID)
		*p = fresh
		return err
	}
	switch action {
	case "dismiss":
		switch p.Status {
		case db.ProposalDismissedStatus:
			return nil
		case db.ProposalPendingStatus:
			if _, err := move(db.ProposalPendingStatus, db.ProposalDismissedStatus, nil); err != nil {
				return err
			}
			return reload()
		}
		return errProposalState
	case "apply":
		switch p.Status {
		case db.ProposalAppliedStatus:
			return nil
		case db.ProposalPendingStatus:
		default:
			return errProposalState
		}
		if !now.Before(p.ExpiresAt) {
			return errProposalExpired
		}
		before, err := s.captureCoachState(ctx, c, stored.State)
		if err != nil {
			return err
		}
		raw, err := json.Marshal(before)
		if err != nil {
			return err
		}
		won, err := move(db.ProposalPendingStatus, db.ProposalAppliedStatus, raw)
		if err != nil {
			return err
		}
		if !won {
			return reload()
		}
		if err := s.applyCoachState(ctx, c, stored.State); err != nil {
			_, _ = move(db.ProposalAppliedStatus, db.ProposalPendingStatus, nil)
			return err
		}
		return reload()
	case "undo":
		switch p.Status {
		case db.ProposalUndoneStatus:
			return nil
		case db.ProposalAppliedStatus:
		default:
			return errProposalState
		}
		if p.DecidedAt == nil || !now.Before(p.DecidedAt.Add(undoWindow)) {
			return errProposalExpired
		}
		var before coachState
		if err := json.Unmarshal(p.Before, &before); err != nil {
			return err
		}
		won, err := move(db.ProposalAppliedStatus, db.ProposalUndoneStatus, nil)
		if err != nil {
			return err
		}
		if !won {
			return reload()
		}
		if err := s.applyCoachState(ctx, c, before); err != nil {
			_, _ = move(db.ProposalUndoneStatus, db.ProposalAppliedStatus, nil)
			return err
		}
		return reload()
	}
	return errProposalState
}

func (s *Server) handleListCoachFacts(w http.ResponseWriter, r *http.Request) {
	if s.chatter == nil {
		fail(w, r, errCoachDisabled)
		return
	}
	facts, err := db.ListCoachFacts(r.Context(), s.db.Pool, callerFrom(r).user.ID)
	if err != nil {
		fail(w, r, err)
		return
	}
	out := make([]coachFactJSON, len(facts))
	for i, f := range facts {
		out[i] = toFactJSON(f)
	}
	writeJSON(w, http.StatusOK, map[string]any{"facts": out, "max": db.MaxCoachFacts})
}

func (s *Server) handleDeleteCoachFact(w http.ResponseWriter, r *http.Request) {
	if s.chatter == nil {
		fail(w, r, errCoachDisabled)
		return
	}
	id, herr := pathID(r)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	if err := db.DeleteCoachFact(r.Context(), s.db.Pool, callerFrom(r).user.ID, id); err != nil {
		if errors.Is(err, db.ErrNotFound) {
			fail(w, r, errNoCoachItem)
			return
		}
		fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// addCoachContext adds what the coach needs to use its tools well: body info, the training
// profile, the facts the person told it, and this week's suggestions.
func (s *Server) addCoachContext(ctx context.Context, c caller, facts *coach.ChatFacts) error {
	u := c.user
	if u.HeightCm != nil {
		facts.Body = append(facts.Body, "height "+trim(*u.HeightCm, 1)+" cm")
	}
	if u.BirthYear != nil {
		facts.Body = append(facts.Body, fmt.Sprintf("birth year %d", *u.BirthYear))
	}
	p, err := db.GetTrainingProfile(ctx, s.db.Pool, u.ID)
	switch {
	case err == nil:
		facts.Training = fmt.Sprintf("%d days a week, %d minute sessions, experience %s", p.DaysPerWeek, p.SessionMinutes, p.Experience)
		if p.Focus != "" {
			facts.Training += ", focus: " + p.Focus
		}
	case !errors.Is(err, db.ErrNotFound):
		return err
	}
	saved, err := db.ListCoachFacts(ctx, s.db.Pool, u.ID)
	if err != nil {
		return err
	}
	for _, f := range saved {
		facts.Saved = append(facts.Saved, fmt.Sprintf("id %d, %s: %s", f.ID, f.Category, f.Text))
	}
	_, pending, err := s.weeklyProposals(ctx, c)
	if err != nil {
		return err
	}
	for _, p := range pending {
		facts.Suggestions = append(facts.Suggestions, fmt.Sprintf("key %s: %s, %d to %d %s. %s", p.Key, p.Title, p.Current, p.Proposed, p.Unit, p.Reason))
	}
	return nil
}
