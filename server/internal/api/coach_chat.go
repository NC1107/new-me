package api

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"net/http"
	"strconv"
	"strings"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/coach"
	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/insights"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/targets"
)

// coachChatPerHour caps coach messages per person, since each one is a Claude call carrying the
// person's whole month of data.
const coachChatPerHour = 30

// chatWindowDays is how far back the coach sees.
const chatWindowDays = 28

const (
	codeCoachDisabled = "coach_disabled"
	codeCoachFailed   = "coach_unavailable"
)

var (
	errCoachDisabled = newErr(http.StatusNotFound, codeCoachDisabled, "the coach is not set up on this server")
	errCoachFailed   = newErr(http.StatusBadGateway, codeCoachFailed, "the coach could not answer right now, try again in a moment")
)

type coachChatRequest struct {
	Messages []coach.ChatTurn `json:"messages"`
}

type coachChatResponse struct {
	Reply string `json:"reply"`
}

// handleCoachChat answers one message of a conversation about the caller's own data. The
// conversation lives on the phone; the server keeps nothing and never logs what was said.
func (s *Server) handleCoachChat(w http.ResponseWriter, r *http.Request) {
	if s.chatter == nil {
		fail(w, r, errCoachDisabled)
		return
	}
	var req coachChatRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	if err := coach.ValidateChat(req.Messages); err != nil {
		fail(w, r, invalid(strings.TrimPrefix(err.Error(), coach.ErrBadChat.Error()+": ")))
		return
	}
	c := callerFrom(r)
	if ok, retry := s.coachChats.Allow(strconv.FormatInt(c.user.ID, 10)); !ok {
		w.Header().Set("Retry-After", strconv.Itoa(int(retry.Seconds())+1))
		writeErr(w, http.StatusTooManyRequests, codeRateLimited, "too many coach messages this hour, try again later")
		return
	}
	facts, err := s.loadChatFacts(r.Context(), c)
	if err != nil {
		fail(w, r, err)
		return
	}
	reply, err := s.chatter.Reply(r.Context(), facts, req.Messages)
	if err != nil {
		if r.Context().Err() == nil {
			log.Printf("[NEWME] coach chat for user %d: %v", c.user.ID, err)
		}
		fail(w, r, errCoachFailed)
		return
	}
	writeJSON(w, http.StatusOK, coachChatResponse{Reply: reply})
}

// loadChatFacts gathers the caller's own data, and nobody else's, for the coach.
func (s *Server) loadChatFacts(ctx context.Context, c caller) (coach.ChatFacts, error) {
	now := s.now()
	today := score.LocalToday(now, c.loc)
	from := today.AddDays(-(chatWindowDays - 1))
	if c.user.JoinedOn.After(from) {
		from = c.user.JoinedOn
	}
	q := s.db.Pool

	var (
		scored engine.Scored
		streak score.StreakResult
	)
	err := s.db.WithTx(ctx, func(tx pgx.Tx) error {
		var err error
		scored, streak, err = engine.ScoreWithStreak(ctx, tx, c.user, today, c.loc, now)
		return err
	})
	if err != nil {
		return coach.ChatFacts{}, err
	}

	facts := coach.ChatFacts{
		Name: c.user.Name, Units: c.user.Units, Today: today,
		Streak: streak.Count, BestStreak: streak.Best,
		Age: insights.AgeOn(today, c.user.BirthYear), Goal: goalSentence(c.user),
		Sources: targets.Sources,
	}
	if c.user.Sex != nil {
		facts.Sex = *c.user.Sex
	}
	for _, quest := range toQuestsJSON(scored) {
		facts.TodayQuests = append(facts.TodayQuests, questLine(quest.Title, quest.Actual, quest.Target, quest.Unit, quest.Done, quest.Key))
	}

	series := map[string]map[score.Date]float64{}
	for _, metric := range []string{db.MetricSteps, db.MetricSleep, db.MetricExercise} {
		points, err := db.HealthSeries(ctx, q, c.user.ID, metric, from, today)
		if err != nil {
			return facts, err
		}
		series[metric] = pointMap(points)
	}
	food, err := db.DailyFood(ctx, q, c.user.ID, from, today)
	if err != nil {
		return facts, err
	}
	stored, err := db.ListDayScores(ctx, q, c.user.ID, from, today)
	if err != nil {
		return facts, err
	}
	scores := map[score.Date]db.DayScoreRow{}
	for _, row := range stored {
		scores[row.LocalDate] = row
	}
	history, err := db.TrainingHistory(ctx, q, c.user.ID, from, today)
	if err != nil {
		return facts, err
	}
	trained := map[score.Date]db.HistoryDay{}
	for _, h := range history {
		trained[h.Date] = h
	}
	workouts, err := db.ListWorkouts(ctx, q, c.user.ID, from, today)
	if err != nil {
		return facts, err
	}
	workoutsBy := map[score.Date][]string{}
	for _, wo := range workouts {
		if wo.Type == "yoga" {
			continue
		}
		workoutsBy[wo.LocalDate] = append(workoutsBy[wo.LocalDate], fmt.Sprintf("%s %d min", wo.Type, int(math.Round(wo.DurationMin))))
	}

	for d := from; !d.After(today); d = d.AddDays(1) {
		facts.Days = append(facts.Days, dayLine(d, scores[d], series, food[d], trained[d], workoutsBy[d]))
	}

	if facts.Health, err = s.healthLines(ctx, c, today, from, series); err != nil {
		return facts, err
	}
	if facts.Habits, err = s.habitLines(ctx, c, from, today); err != nil {
		return facts, err
	}

	data, err := s.loadTargetData(ctx, q, c.user, c.loc)
	if err != nil {
		return facts, err
	}
	for _, t := range computeTargets(data).Targets {
		facts.Targets = append(facts.Targets, toChatTarget(t))
	}
	return facts, nil
}

func pointMap(points []db.HealthPoint) map[score.Date]float64 {
	out := make(map[score.Date]float64, len(points))
	for _, p := range points {
		out[p.Date] = p.Value
	}
	return out
}

func goalSentence(u db.User) string {
	switch u.GoalKind {
	case "lose", "gain":
		if u.GoalPaceKg > 0 {
			return fmt.Sprintf("%s %s kg a week", u.GoalKind, trim(u.GoalPaceKg, 2))
		}
		return u.GoalKind + " weight"
	case "maintain":
		return "maintain weight"
	}
	return ""
}

// questLine is one quest as the coach reads it. Reading keeps no figures because its stored
// progress is a blended basis of minutes and pages, not either of them.
func questLine(title string, actual, target int, unit string, done bool, key string) string {
	state := "not yet"
	if done {
		state = "done"
	}
	if key == db.QuestReading {
		return title + ": " + state
	}
	return fmt.Sprintf("%s: %s (%d of %d %s)", title, state, actual, target, unit)
}

func dayLine(d score.Date, row db.DayScoreRow, series map[string]map[score.Date]float64,
	food db.FoodDay, trained db.HistoryDay, workouts []string) string {
	parts := []string{fmt.Sprintf("%s %s", d.Weekday().String()[:3], d)}
	if row.UserID == 0 {
		parts = append(parts, "no score recorded")
	} else {
		verdict := "counts toward the streak"
		if !row.Counted {
			verdict = "does not count toward the streak"
		}
		parts = append(parts, fmt.Sprintf("%d points, %d%% of base points, %s", row.Points(), row.Percent, verdict))
		var done, missed []string
		var results []score.QuestScore
		if json.Unmarshal(row.Detail, &results) == nil {
			for _, qs := range results {
				if qs.Complete {
					done = append(done, questTitle(qs.Key))
					continue
				}
				missed = append(missed, missedLine(qs))
			}
		}
		if len(done) > 0 {
			parts = append(parts, "done: "+strings.Join(done, ", "))
		}
		if len(missed) > 0 {
			parts = append(parts, "not done: "+strings.Join(missed, ", "))
		}
	}
	if v, ok := series[db.MetricSteps][d]; ok {
		parts = append(parts, fmt.Sprintf("steps %d", int(math.Round(v))))
	}
	if v, ok := series[db.MetricSleep][d]; ok && v > 0 {
		parts = append(parts, "slept "+hours(v))
	}
	if v, ok := series[db.MetricExercise][d]; ok {
		parts = append(parts, fmt.Sprintf("exercise %d min", int(math.Round(v))))
	}
	if food.Kcal > 0 {
		parts = append(parts, fmt.Sprintf("food %d kcal, protein %d g, %d meal%s", int(math.Round(food.Kcal)),
			int(math.Round(food.ProteinG)), food.Meals, plural(food.Meals)))
	}
	var training []string
	if trained.SessionCompleted {
		training = append(training, "planned session completed")
	}
	if trained.SetCount > 0 {
		training = append(training, fmt.Sprintf("%d logged set%s", trained.SetCount, plural(trained.SetCount)))
	}
	if trained.YogaMinutes > 0 {
		training = append(training, fmt.Sprintf("yoga %d min", trained.YogaMinutes))
	}
	training = append(training, workouts...)
	if len(training) > 0 {
		parts = append(parts, "training: "+strings.Join(training, ", "))
	}
	return strings.Join(parts, " | ")
}

// missedLine gives a missed quest as a share of its target, because a stored day keeps progress
// in the engine's own basis (protein in tenths of a gram, reading as a minutes-and-pages blend),
// which no unit describes.
func missedLine(qs score.QuestScore) string {
	title := questTitle(qs.Key)
	if qs.Target <= 0 || qs.Actual <= 0 {
		return title + " (nothing recorded)"
	}
	return fmt.Sprintf("%s (%d%% of target)", title, min(99, qs.Actual*100/qs.Target))
}

func plural(n int) string {
	if n == 1 {
		return ""
	}
	return "s"
}

func hours(minutes float64) string { return trim(minutes/60, 1) + " h" }

// average is the mean of the values on days from..to that have a reading, with how many did.
func average(m map[score.Date]float64, from, to score.Date) (mean float64, n int) {
	sum := 0.0
	for d, v := range m {
		if !d.Before(from) && !d.After(to) {
			sum += v
			n++
		}
	}
	if n == 0 {
		return 0, 0
	}
	return sum / float64(n), n
}

func (s *Server) weightText(u db.User, kg float64) string {
	if u.Imperial() {
		return fmt.Sprintf("%s lb (%s kg)", trim(kg*2.2046226218, 1), trim(kg, 1))
	}
	return trim(kg, 1) + " kg"
}

// healthLines summarizes the synced Health metrics. A metric with no readings in the window is
// left out, so the coach cannot mistake silence for a value.
func (s *Server) healthLines(ctx context.Context, c caller, today, from score.Date, series map[string]map[score.Date]float64) ([]string, error) {
	var out []string
	week := today.AddDays(-6)
	summary := func(name string, m map[score.Date]float64, format func(float64) string) {
		a7, n7 := average(m, week, today)
		a28, n28 := average(m, from, today)
		if n28 == 0 {
			return
		}
		line := fmt.Sprintf("%s: 28-day average %s over %d days", name, format(a28), n28)
		if n7 > 0 {
			line += fmt.Sprintf("; 7-day average %s over %d days", format(a7), n7)
		}
		out = append(out, line)
	}
	whole := func(v float64) string { return strconv.Itoa(int(math.Round(v))) }
	summary("steps a day", series[db.MetricSteps], whole)
	summary("time asleep a night", series[db.MetricSleep], func(v float64) string { return hours(v) })
	summary("exercise minutes a day", series[db.MetricExercise], whole)

	templates, err := db.GetQuestTemplates(ctx, s.db.Pool, c.user.ID)
	if err != nil {
		return nil, err
	}
	sleepTarget := defaultSleepTargetMin
	for _, t := range templates {
		if t.Key == db.QuestSleep && t.Enabled {
			sleepTarget = t.Target
		}
	}
	nights, err := db.ListSleepNights(ctx, s.db.Pool, c.user.ID, from, today)
	if err != nil {
		return nil, err
	}
	in := make([]insights.Night, len(nights))
	for i, n := range nights {
		in[i] = insights.Night{Date: n.Date, BedAt: n.BedAt, WakeAt: n.WakeAt, AsleepMin: n.AsleepMin,
			DeepMin: n.DeepMin, REMMin: n.REMMin, CoreMin: n.CoreMin, AwakeMin: n.AwakeMin}
	}
	if sleep := insights.ComputeSleep(insights.SleepInput{Nights: in, Today: today, TargetMin: sleepTarget, Loc: c.loc}); len(sleep.Nights) > 0 {
		line := fmt.Sprintf("sleep goal: %s a night", hours(float64(sleepTarget)))
		if sleep.AvgBedtime != nil && sleep.AvgWake != nil {
			line += fmt.Sprintf("; average bedtime %s, average wake time %s, bedtime spread %d min", *sleep.AvgBedtime, *sleep.AvgWake, sleep.BedtimeSpreadMin)
		}
		out = append(out, line)
	}

	points, err := db.HealthSeries(ctx, s.db.Pool, c.user.ID, db.MetricWeight, "0001-01-01", today)
	if err != nil {
		return nil, err
	}
	readings := make([]insights.Reading, len(points))
	for i, p := range points {
		readings[i] = insights.Reading{Date: p.Date, Value: p.Value}
	}
	if w := insights.ComputeWeight(readings); w != nil {
		line := fmt.Sprintf("weight: trend %s, latest weigh-in %s", s.weightText(c.user, w.SmoothedKg), s.weightText(c.user, w.LatestKg))
		if w.WeeklyRateKg != nil {
			line += fmt.Sprintf(", trend change %s kg a week", trim(*w.WeeklyRateKg, 2))
		}
		out = append(out, line)
	}

	for _, m := range []struct{ key, name, unit string }{
		{"resting_hr", "resting heart rate", "bpm"}, {"hrv_ms", "heart rate variability", "ms"}, {"vo2max", "VO2 max", "mL/kg/min"},
	} {
		pts, err := db.HealthSeries(ctx, s.db.Pool, c.user.ID, m.key, from, today)
		if err != nil {
			return nil, err
		}
		if len(pts) == 0 {
			continue
		}
		last := pts[len(pts)-1]
		avg, n := average(pointMap(pts), from, today)
		out = append(out, fmt.Sprintf("%s: latest %s %s on %s; 28-day average %s over %d readings",
			m.name, trim(last.Value, 1), m.unit, last.Date, trim(avg, 1), n))
	}
	return out, nil
}

// habitLines reports, per live habit, the days it was marked against the days it was due.
func (s *Server) habitLines(ctx context.Context, c caller, from, today score.Date) ([]string, error) {
	habits, err := db.ListHabits(ctx, s.db.Pool, c.user.ID)
	if err != nil {
		return nil, err
	}
	marked, err := db.HabitMarkedDays(ctx, s.db.Pool, c.user.ID, from, today)
	if err != nil {
		return nil, err
	}
	var out []string
	for _, h := range habits {
		if h.Paused {
			continue
		}
		due := 0
		for d := maxDate(from, score.Date(h.CreatedAt.In(c.loc).Format("2006-01-02"))); !d.After(today); d = d.AddDays(1) {
			if score.HabitDue(h.Weekdays, d) {
				due++
			}
		}
		out = append(out, fmt.Sprintf("%s: marked on %d of %d days it was due", h.Name, min(marked[h.ID], due), due))
	}
	return out, nil
}

func maxDate(a, b score.Date) score.Date {
	if a.After(b) {
		return a
	}
	return b
}

func toChatTarget(t targetJSON) coach.ChatTarget {
	value := "no value yet"
	if t.Value != nil {
		value = fmt.Sprintf("%s %s", th(float64(*t.Value)), t.Unit)
		if t.Current != nil && *t.Current != *t.Value {
			value += fmt.Sprintf(" (currently set to %s)", th(float64(*t.Current)))
		}
	}
	return coach.ChatTarget{Key: t.Key, Value: value, Formula: t.Formula, Label: t.Label, Sources: t.Sources}
}
