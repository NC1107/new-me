package api

import (
	"errors"
	"net/http"
	"slices"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/yogaplan"
)

// yogaCitation is shown with the weekly default so the person can see where it comes from.
const yogaCitation = "ACSM position stand (Garber et al., Med Sci Sports Exerc 2011;43:1334): flexibility exercise on at least 2 to 3 days a week, with more benefit from daily practice."

type yogaPlanJSON struct {
	DaysPerWeek int        `json:"daysPerWeek"`
	FlowMinutes int        `json:"flowMinutes"`
	Weekdays    []int      `json:"weekdays"`
	LevelSince  score.Date `json:"levelSince"`
}

type yogaDayJSON struct {
	Date    score.Date `json:"date"`
	Weekday int        `json:"weekday"`
	Planned bool       `json:"planned"`
	Done    bool       `json:"done"`
}

type yogaWeekJSON struct {
	Start   score.Date    `json:"start"`
	Planned int           `json:"planned"`
	Done    int           `json:"done"`
	Days    []yogaDayJSON `json:"days"`
}

type yogaProgressionJSON struct {
	Offer       bool `json:"offer"`
	NextMinutes int  `json:"nextMinutes"`
}

type yogaTodayJSON struct {
	Planned     bool `json:"planned"`
	Done        bool `json:"done"`
	FlowMinutes int  `json:"flowMinutes"`
}

type yogaPlanRequest struct {
	DaysPerWeek int `json:"daysPerWeek"`
	FlowMinutes int `json:"flowMinutes"`
	// RestartLevel turns a declined progression offer into another two weeks at this length.
	RestartLevel bool `json:"restartLevel"`
}

// avoidedYogaWeekdays are the weekdays of the active strength plan that are heavy lower-body days.
func (s *Server) avoidedYogaWeekdays(r *http.Request, userID int64) (map[int]bool, error) {
	ctx := r.Context()
	stored, err := db.ActivePlan(ctx, s.db.Pool, userID)
	if errors.Is(err, db.ErrNotFound) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	exercises, err := db.ListExercises(ctx, s.db.Pool, userID)
	if err != nil {
		return nil, err
	}
	primary := map[string][]string{}
	for _, e := range exercises {
		primary[e.Key] = e.PrimaryMuscles
	}
	days := make([]yogaplan.Day, 0, len(stored.Days))
	for _, d := range stored.Days {
		day := yogaplan.Day{Weekday: d.Weekday}
		for _, p := range d.Exercises {
			day.Exercises = append(day.Exercises, p.Exercise)
		}
		days = append(days, day)
	}
	return yogaplan.LowerBodyDays(days, primary), nil
}

// handleGetYogaPlan returns the caller's weekly yoga plan, this week's progress and whether a
// longer flow is on offer. Without a plan it returns the days a new plan would use.
func (s *Server) handleGetYogaPlan(w http.ResponseWriter, r *http.Request) {
	c := callerFrom(r)
	ctx := r.Context()
	today := score.LocalToday(s.now(), c.loc)
	avoid, err := s.avoidedYogaWeekdays(r, c.user.ID)
	if err != nil {
		fail(w, r, err)
		return
	}
	body := map[string]any{
		"plan": nil,
		"suggested": yogaPlanJSON{DaysPerWeek: yogaplan.DefaultDays, FlowMinutes: yogaplan.Flows[0],
			Weekdays: yogaplan.Place(yogaplan.DefaultDays, avoid), LevelSince: today},
		"citation":    yogaCitation,
		"avoidedDays": sortedKeys(avoid),
		"progression": yogaProgressionJSON{},
		"week":        nil,
		"today":       yogaTodayJSON{},
		"flows":       yogaplan.Flows,
	}
	plan, err := db.GetYogaPlan(ctx, s.db.Pool, c.user.ID)
	if errors.Is(err, db.ErrNotFound) {
		writeJSON(w, http.StatusOK, body)
		return
	}
	if err != nil {
		fail(w, r, err)
		return
	}
	week := score.WeekStart(today)
	from := week.AddDays(-7 * yogaplan.ProgressionWeeks)
	history, err := db.TrainingHistory(ctx, s.db.Pool, c.user.ID, from, today)
	if err != nil {
		fail(w, r, err)
		return
	}
	yogaDays := map[score.Date]bool{}
	for _, d := range history {
		if d.YogaMinutes > 0 {
			yogaDays[d.Date] = true
		}
	}
	days := make([]yogaDayJSON, 0, 7)
	for i := 0; i < 7; i++ {
		d := week.AddDays(i)
		weekday := i + 1
		days = append(days, yogaDayJSON{Date: d, Weekday: weekday, Planned: slices.Contains(plan.Weekdays, weekday), Done: yogaDays[d]})
	}
	todayDay := days[int(today.Weekday()+6)%7]
	body["plan"] = yogaPlanJSON{DaysPerWeek: plan.DaysPerWeek, FlowMinutes: plan.FlowMinutes, Weekdays: plan.Weekdays, LevelSince: plan.LevelSince}
	body["week"] = yogaWeekJSON{Start: week, Planned: plan.DaysPerWeek, Done: yogaplan.Count(week, yogaDays, today), Days: days}
	body["today"] = yogaTodayJSON{Planned: todayDay.Planned, Done: todayDay.Done, FlowMinutes: plan.FlowMinutes}
	if yogaplan.OfferLonger(today, plan.LevelSince, plan.DaysPerWeek, plan.FlowMinutes, yogaDays) {
		body["progression"] = yogaProgressionJSON{Offer: true, NextMinutes: yogaplan.NextFlow(plan.FlowMinutes)}
	}
	writeJSON(w, http.StatusOK, body)
}

func sortedKeys(m map[int]bool) []int {
	out := []int{}
	for k := range m {
		out = append(out, k)
	}
	slices.Sort(out)
	return out
}

// handlePutYogaPlan saves how many days and which flow, and places the days around the
// caller's strength plan. A changed flow length starts a new progression count.
func (s *Server) handlePutYogaPlan(w http.ResponseWriter, r *http.Request) {
	c := callerFrom(r)
	var req yogaPlanRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	switch {
	case req.DaysPerWeek < 1 || req.DaysPerWeek > 7:
		fail(w, r, invalid("daysPerWeek must be between 1 and 7"))
		return
	case !slices.Contains(yogaplan.Flows, req.FlowMinutes):
		fail(w, r, invalid("flowMinutes must be 10, 20 or 30"))
		return
	}
	ctx := r.Context()
	today := score.LocalToday(s.now(), c.loc)
	avoid, err := s.avoidedYogaWeekdays(r, c.user.ID)
	if err != nil {
		fail(w, r, err)
		return
	}
	level := today
	if prior, err := db.GetYogaPlan(ctx, s.db.Pool, c.user.ID); err == nil {
		if prior.FlowMinutes == req.FlowMinutes && !req.RestartLevel {
			level = prior.LevelSince
		}
	} else if !errors.Is(err, db.ErrNotFound) {
		fail(w, r, err)
		return
	}
	plan := db.YogaPlan{DaysPerWeek: req.DaysPerWeek, FlowMinutes: req.FlowMinutes,
		Weekdays: yogaplan.Place(req.DaysPerWeek, avoid), LevelSince: level}
	if err := db.PutYogaPlan(ctx, s.db.Pool, c.user.ID, plan); err != nil {
		fail(w, r, err)
		return
	}
	s.handleGetYogaPlan(w, r)
}
