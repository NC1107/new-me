package api

import (
	"context"
	"errors"
	"fmt"
	"math"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/goals"
	"github.com/nc1107/new-me/server/internal/insights"
	"github.com/nc1107/new-me/server/internal/plan"
	"github.com/nc1107/new-me/server/internal/score"
)

type proposalJSON struct {
	Key string `json:"key"`
	// Kind is "target" for a new target of a quest that is on and "enable" for an offer to
	// switch a quest on; an enable offer carries the target the quest would have.
	Kind     string `json:"kind"`
	Title    string `json:"title"`
	Unit     string `json:"unit"`
	Current  int    `json:"current"`
	Proposed int    `json:"proposed"`
	Reason   string `json:"reason"`
}

// proposalKeys are the quests that get proposals, in display order.
var proposalKeys = []string{db.QuestSteps, db.QuestSleep, db.QuestExercise, db.QuestProtein, proposalCalories}

// proposalCalories is the proposal key of the calorie target, which lives on the profile and has
// no quest template.
const proposalCalories = "calories"

// handleGoalProposals lists this week's pending target proposals. A proposal is frozen the
// first time it is shown and, once accepted or dismissed, does not come back until next week.
func (s *Server) handleGoalProposals(w http.ResponseWriter, r *http.Request) {
	c := callerFrom(r)
	ctx := r.Context()
	today := score.LocalToday(s.now(), c.loc)
	week := score.WeekStart(today)

	templates, err := db.GetQuestTemplates(ctx, s.db.Pool, c.user.ID)
	if err != nil {
		fail(w, r, err)
		return
	}
	byKey := map[string]db.QuestTemplate{}
	for _, t := range templates {
		byKey[t.Key] = t
	}
	stored, err := db.ListGoalProposals(ctx, s.db.Pool, c.user.ID, week)
	if err != nil {
		fail(w, r, err)
		return
	}
	storedByKey := map[string]db.GoalProposal{}
	for _, p := range stored {
		storedByKey[p.Key] = p
	}

	out := []proposalJSON{}
	for _, key := range proposalKeys {
		tmpl, ok := byKey[key]
		if key == proposalCalories {
			tmpl, ok = db.QuestTemplate{Key: key, Unit: "kcal"}, true
		}
		prior, hasPrior := storedByKey[key]
		if !ok || (hasPrior && prior.State != db.ProposalPending) {
			continue
		}
		kind, current, applies, err := s.proposalBasis(r, c, key, tmpl, today)
		if err != nil {
			fail(w, r, err)
			return
		}
		if !applies {
			continue
		}
		chosen := prior
		if !hasPrior || prior.Current != current || prior.Kind != kind {
			fresh, err := s.freshProposal(r, c, key, kind, current, tmpl, today)
			if err != nil {
				fail(w, r, err)
				return
			}
			if fresh == nil {
				continue
			}
			chosen = db.GoalProposal{Key: key, Kind: fresh.Kind, Current: fresh.Current, Proposed: fresh.Proposed, Reason: fresh.Reason}
			if err := db.SaveGoalProposal(ctx, s.db.Pool, c.user.ID, week, chosen); err != nil {
				fail(w, r, err)
				return
			}
		}
		out = append(out, proposalJSON{Key: key, Kind: chosen.Kind, Title: titles[key], Unit: tmpl.Unit,
			Current: chosen.Current, Proposed: chosen.Proposed, Reason: chosen.Reason})
	}
	writeJSON(w, http.StatusOK, map[string]any{"week": score.ISOWeekLabel(week), "weekStart": week, "proposals": out})
}

// proposalBasis says what kind of proposal a quest can have right now and the target it would be
// measured against. applies is false when the quest has nothing to propose.
func (s *Server) proposalBasis(r *http.Request, c caller, key string, tmpl db.QuestTemplate, today score.Date) (kind string, current int, applies bool, err error) {
	switch key {
	case db.QuestSteps:
		return goals.KindTarget, tmpl.Target, tmpl.Enabled, nil
	case db.QuestSleep:
		if tmpl.Enabled {
			return goals.KindTarget, tmpl.Target, true, nil
		}
		return goals.KindEnable, tmpl.Target, true, nil
	case db.QuestExercise:
		return goals.KindEnable, tmpl.Target, !tmpl.Enabled, nil
	case db.QuestProtein:
		if !tmpl.Enabled {
			return "", 0, false, nil
		}
		protein, err := proteinFor(r.Context(), s.db.Pool, c.user, today, tmpl.Target)
		return goals.KindTarget, protein.Effective, true, err
	case proposalCalories:
		if c.user.KcalTarget == nil {
			return "", 0, false, nil
		}
		return goals.KindTarget, *c.user.KcalTarget, true, nil
	}
	return "", 0, false, nil
}

// freshProposal computes the proposal for one quest from the recent data.
func (s *Server) freshProposal(r *http.Request, c caller, key, kind string, current int, tmpl db.QuestTemplate, today score.Date) (*goals.Proposal, error) {
	ctx := r.Context()
	if kind == goals.KindEnable {
		since := score.WeekStart(today).AddDays(-goals.EnableDismissedDays)
		dismissed, err := db.EnableDismissedSince(ctx, s.db.Pool, c.user.ID, key, since)
		if err != nil || dismissed {
			return nil, err
		}
		return goals.Enable(key, tmpl.Target), nil
	}
	switch key {
	case db.QuestSteps:
		points, err := db.HealthSeries(ctx, s.db.Pool, c.user.ID, db.MetricSteps, today.AddDays(-29), today)
		if err != nil {
			return nil, err
		}
		days := make([]insights.StepDay, len(points))
		for i, p := range points {
			days[i] = insights.StepDay{Date: p.Date, Steps: p.Value}
		}
		steps := insights.ComputeSteps(insights.StepInput{Days: days, Today: today, Goal: tmpl.Target, BirthYear: c.user.BirthYear})
		return goals.Steps(tmpl.Target, steps.Suggestion, daysAtGoal(points, tmpl.Target, today)), nil
	case db.QuestSleep:
		nights, err := db.ListSleepNights(ctx, s.db.Pool, c.user.ID, today.AddDays(-13), today)
		if err != nil {
			return nil, err
		}
		var asleep []int
		for _, n := range nights {
			if n.AsleepMin > 0 {
				asleep = append(asleep, n.AsleepMin)
			}
		}
		return goals.Sleep(tmpl.Target, asleep), nil
	case db.QuestProtein, proposalCalories:
		return s.formulaProposal(ctx, c, key, current, today)
	}
	return nil, nil
}

// formulaProposal proposes the v8 formula value of calories or protein. Protein also follows the
// 20% rule against the formula. Either is offered when the formula value moved more than 5%
// (100 kcal for calories) from its baseline; the baseline is set the first time the formula can
// be computed, so nothing is proposed before an input has changed.
func (s *Server) formulaProposal(ctx context.Context, c caller, key string, current int, today score.Date) (*goals.Proposal, error) {
	d, err := s.loadTargetData(ctx, s.db.Pool, c.user, c.loc)
	if err != nil {
		return nil, err
	}
	computed := computeTargets(d)
	t, ok := computed.find(key)
	if !ok || t.Value == nil {
		return nil, nil
	}
	value := *t.Value
	if key == db.QuestProtein && d.WeightKg != nil {
		perKg := round1(float64(value) / *d.WeightKg)
		if t.Details != nil {
			if k, ok := t.Details["perKg"].(float64); ok && t.Details["capped"] != true {
				perKg = k
			}
		}
		if p := goals.Protein(current, *d.WeightKg, value, perKg, d.User.Imperial()); p != nil {
			return p, nil
		}
	}
	base, err := db.GetTargetBaseline(ctx, s.db.Pool, c.user.ID, key)
	if errors.Is(err, db.ErrNotFound) {
		return nil, db.SetTargetBaseline(ctx, s.db.Pool, c.user.ID, key, float64(value), d.baselineInputs(), today)
	}
	if err != nil {
		return nil, err
	}
	changed := changedInputs(base.Inputs, d.baselineInputs())
	if len(changed) == 0 || value == current || !goals.FormulaMoved(key, base.Value, float64(value)) {
		return nil, nil
	}
	unit := "g"
	if key == proposalCalories {
		unit = "kcal"
	}
	return &goals.Proposal{Key: key, Kind: goals.KindTarget, Current: current, Proposed: value, Reason: fmt.Sprintf(
		"Your %s changed, so the formula now gives %s %s, not %s. %s",
		strings.Join(changed, " and "), plan.Thousands(value), unit, plan.Thousands(int(math.Round(base.Value))), t.Formula)}, nil
}

// inputNames are the readable names of the baseline inputs, in the order they are listed.
var inputNames = []struct{ key, name string }{
	{inWeight, "weight"}, {inHeight, "height"}, {inAge, "age"}, {inSex, "sex"},
	{"goal", "goal"}, {"paceKgPerWeek", "goal pace"}, {"palBand", "step count band"},
}

// changedInputs names the inputs whose value differs between two baseline snapshots.
func changedInputs(before, now map[string]any) []string {
	var out []string
	goalChanged := false
	for _, in := range inputNames {
		if fmt.Sprint(before[in.key]) == fmt.Sprint(now[in.key]) {
			continue
		}
		goalChanged = goalChanged || in.key == "goal"
		// A new goal kind carries its own pace, which is not a second change.
		if in.key == "paceKgPerWeek" && goalChanged {
			continue
		}
		out = append(out, in.name)
	}
	return out
}

// refreshBaseline records the current formula value of calories or protein as the baseline, so
// the next proposal is measured from what the person just accepted or dismissed.
func (s *Server) refreshBaseline(ctx context.Context, q db.Querier, c caller, key string) error {
	if key != db.QuestProtein && key != proposalCalories {
		return nil
	}
	d, err := s.loadTargetData(ctx, q, c.user, c.loc)
	if err != nil {
		return err
	}
	if t, ok := computeTargets(d).find(key); ok && t.Value != nil {
		return db.SetTargetBaseline(ctx, q, c.user.ID, key, float64(*t.Value), d.baselineInputs(), d.Today)
	}
	return nil
}

var errNoProposal = newErr(http.StatusNotFound, codeNotFound, "there is no pending proposal for that goal this week")

// proposalKey reads and checks the {key} path value.
func proposalKey(r *http.Request) (string, *httpError) {
	key := chi.URLParam(r, "key")
	for _, k := range proposalKeys {
		if k == key {
			return key, nil
		}
	}
	return "", errNoProposal
}

// handleAcceptProposal applies the proposed target the way PATCH /api/me does: open days are
// scored first, which freezes their quests, so the new target starts tomorrow, except on the
// join day.
func (s *Server) handleAcceptProposal(w http.ResponseWriter, r *http.Request) {
	key, herr := proposalKey(r)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	c := callerFrom(r)
	ctx := r.Context()
	week := score.WeekStart(score.LocalToday(s.now(), c.loc))
	err := s.db.WithTx(ctx, func(tx pgx.Tx) error {
		p, err := db.DecideGoalProposal(ctx, tx, c.user.ID, week, key, db.ProposalAccepted)
		if errors.Is(err, db.ErrNotFound) {
			return errNoProposal
		}
		if err != nil {
			return err
		}
		for _, date := range s.openDates(c.user, c.loc) {
			if _, err := engine.RecomputeDayAt(ctx, tx, c.user.ID, date, c.loc, s.now()); err != nil {
				return err
			}
		}
		if key == db.QuestProtein || key == proposalCalories {
			// These targets live on the profile, not on a template.
			user := c.user
			if key == proposalCalories {
				user.KcalTarget = &p.Proposed
			} else {
				user.ProteinTarget = &p.Proposed
			}
			if err := db.UpdateUser(ctx, tx, user); err != nil {
				return mapUpdateUserErr(err)
			}
			if err := s.refreshBaseline(ctx, tx, c, key); err != nil {
				return err
			}
			return s.resnapshotJoinDay(ctx, tx, c, user, patchMeRequest{Targets: &targetsPatch{}})
		}
		patch := templatePatch{Key: key, Target: &p.Proposed}
		if p.Kind == goals.KindEnable {
			on := true
			patch.Enabled = &on
		}
		patches := []templatePatch{patch}
		if err := applyTemplatePatches(ctx, tx, c.user.ID, patches); err != nil {
			return err
		}
		return s.resnapshotJoinDay(ctx, tx, c, c.user, patchMeRequest{QuestTemplates: patches})
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	fresh, err := db.GetUser(ctx, s.db.Pool, c.user.ID)
	if err != nil {
		fail(w, r, err)
		return
	}
	me, err := s.buildMe(ctx, s.db.Pool, fresh)
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, me)
}

// handleDismissProposal drops a pending proposal for the rest of the week.
func (s *Server) handleDismissProposal(w http.ResponseWriter, r *http.Request) {
	key, herr := proposalKey(r)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	c := callerFrom(r)
	week := score.WeekStart(score.LocalToday(s.now(), c.loc))
	if _, err := db.DecideGoalProposal(r.Context(), s.db.Pool, c.user.ID, week, key, db.ProposalDismissed); err != nil {
		if errors.Is(err, db.ErrNotFound) {
			fail(w, r, errNoProposal)
			return
		}
		fail(w, r, err)
		return
	}
	if err := s.refreshBaseline(r.Context(), s.db.Pool, c, key); err != nil {
		fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// daysAtGoal counts the 14 days before today on which the steps reached the goal.
func daysAtGoal(points []db.HealthPoint, goal int, today score.Date) int {
	from := today.AddDays(-14)
	n := 0
	for _, p := range points {
		if !p.Date.Before(from) && p.Date.Before(today) && p.Value >= float64(goal) {
			n++
		}
	}
	return n
}
