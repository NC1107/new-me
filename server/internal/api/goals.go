package api

import (
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/goals"
	"github.com/nc1107/new-me/server/internal/insights"
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
var proposalKeys = []string{db.QuestSteps, db.QuestSleep, db.QuestExercise, db.QuestProtein}

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
	case db.QuestProtein:
		latest, err := db.LatestHealth(ctx, s.db.Pool, c.user.ID, today, []string{db.MetricWeight})
		if err != nil {
			return nil, err
		}
		w, ok := latest[db.MetricWeight]
		if !ok {
			return nil, nil
		}
		return goals.Protein(current, w.Value), nil
	}
	return nil, nil
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
		if key == db.QuestProtein {
			// The protein target lives on the profile, not on the template.
			user := c.user
			user.ProteinTarget = &p.Proposed
			if err := db.UpdateUser(ctx, tx, user); err != nil {
				return mapUpdateUserErr(err)
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
