package api

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"slices"
	"strconv"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/targets"
)

// maxRepsMax is the highest max test the daily-reps setup takes: three sets at 75% of it must stay
// inside the 500 reps a day the quest allows.
const maxRepsMax = 200

// maxRepsPerSet bounds a self-chosen starting set the same way.
const maxRepsPerSet = 150

type repsExerciseJSON struct {
	Key       string       `json:"key"`
	Name      string       `json:"name"`
	Noun      string       `json:"noun"`
	Singular  string       `json:"singular"`
	Hint      string       `json:"hint"`
	Needs     string       `json:"needs,omitempty"`
	Available bool         `json:"available"`
	LatestMax *maxTestJSON `json:"latestMax"`
}

type repsSourceJSON struct {
	Key  string `json:"key"`
	Text string `json:"text"`
}

type dailyRepsJSON struct {
	Exercise string `json:"exercise"`
	Target   int    `json:"target"`
	Enabled  bool   `json:"enabled"`
	// DayExercise is what today's quest counts, which differs from Exercise only on a day that
	// was snapshotted before an exercise change reached it.
	DayExercise string             `json:"dayExercise"`
	Sets        int                `json:"sets"`
	Exercises   []repsExerciseJSON `json:"exercises"`
	Sources     []repsSourceJSON   `json:"sources"`
}

type repsPreviewJSON struct {
	Exercise   string           `json:"exercise"`
	Max        int              `json:"max"`
	Sets       int              `json:"sets"`
	RepsPerSet int              `json:"repsPerSet"`
	Low        int              `json:"low"`
	High       int              `json:"high"`
	Daily      int              `json:"daily"`
	Formula    string           `json:"formula"`
	Sources    []repsSourceJSON `json:"sources"`
}

var repsSourceKeys = []string{"zourdos2016", "schoenfeld2017", "acsm2009"}

func repsSources() []repsSourceJSON {
	out := make([]repsSourceJSON, 0, len(repsSourceKeys))
	for _, k := range repsSourceKeys {
		out = append(out, repsSourceJSON{Key: k, Text: targets.Sources[k]})
	}
	return out
}

// validRepsExercise checks a daily-reps choice for the pushups quest: a known exercise whose
// equipment the person has.
func validRepsExercise(ctx context.Context, q db.Querier, userID int64, questKey, exercise string) error {
	if questKey != db.QuestPushups {
		return invalid("exercise is only for the pushups quest")
	}
	e, ok := db.RepsExerciseByKey(exercise)
	if !ok {
		return invalid("exercise is not a daily-reps choice")
	}
	if e.Needs == "" {
		return nil
	}
	has, err := hasEquipment(ctx, q, userID, e.Needs)
	if err != nil {
		return err
	}
	if !has {
		return invalid(e.Name + " need equipment you have not set in your training profile")
	}
	return nil
}

func hasEquipment(ctx context.Context, q db.Querier, userID int64, tag string) (bool, error) {
	p, err := db.GetTrainingProfile(ctx, q, userID)
	if errors.Is(err, db.ErrNotFound) {
		return false, nil
	}
	return slices.Contains(p.Equipment, tag), err
}

func (s *Server) dailyReps(ctx context.Context, c caller) (dailyRepsJSON, error) {
	q := s.db.Pool
	templates, err := db.GetQuestTemplates(ctx, q, c.user.ID)
	if err != nil {
		return dailyRepsJSON{}, err
	}
	out := dailyRepsJSON{Exercise: db.DefaultRepsExercise, Sets: targets.PushupSets, Sources: repsSources(),
		Exercises: make([]repsExerciseJSON, 0, len(db.RepsExercises))}
	for _, t := range templates {
		if t.Key == db.QuestPushups {
			out.Exercise, out.Target, out.Enabled = t.Exercise, t.Target, t.Enabled
		}
	}
	today := score.LocalToday(s.now(), c.loc)
	if out.DayExercise, err = db.RepsExerciseOf(ctx, q, c.user.ID, today); err != nil {
		return out, err
	}
	for _, e := range db.RepsExercises {
		item := repsExerciseJSON{Key: e.Key, Name: e.Name, Noun: e.Noun, Singular: e.Singular, Hint: e.Hint,
			Needs: e.Needs, Available: true}
		if e.Needs != "" {
			if item.Available, err = hasEquipment(ctx, q, c.user.ID, e.Needs); err != nil {
				return out, err
			}
		}
		m, err := db.LatestRepsMax(ctx, q, c.user.ID, e.Key)
		if err != nil && !errors.Is(err, db.ErrNotFound) {
			return out, err
		}
		if err == nil {
			reps := m.Reps
			item.LatestMax = &maxTestJSON{Date: m.Date, Reps: &reps}
		}
		out.Exercises = append(out.Exercises, item)
	}
	return out, nil
}

// handleGetDailyReps lists the exercises the daily-reps quest can count, with the person's
// latest max of each and the quest's current choice.
func (s *Server) handleGetDailyReps(w http.ResponseWriter, r *http.Request) {
	out, err := s.dailyReps(r.Context(), callerFrom(r))
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}

// handlePreviewDailyReps shows the target a max would give, before anything is saved.
func (s *Server) handlePreviewDailyReps(w http.ResponseWriter, r *http.Request) {
	e, ok := db.RepsExerciseByKey(r.URL.Query().Get("exercise"))
	if !ok {
		fail(w, r, invalid("exercise is not a daily-reps choice"))
		return
	}
	max, err := strconv.Atoi(r.URL.Query().Get("max"))
	if err != nil || max < 1 || max > maxRepsMax {
		fail(w, r, invalid(fmt.Sprintf("max must be between 1 and %d", maxRepsMax)))
		return
	}
	p := targets.ComputePushups(max, 0, 0)
	writeJSON(w, http.StatusOK, repsPreviewJSON{Exercise: e.Key, Max: max, Sets: targets.PushupSets,
		RepsPerSet: p.RepsPerSet, Low: p.Low, High: p.High, Daily: p.Daily(),
		Formula: fmt.Sprintf("%d sets of %d %s: 75%% (the middle of 70 to 80%%) of your max of %d, a derivation from reps-in-reserve guidance rather than a published constant.",
			targets.PushupSets, p.RepsPerSet, e.Noun, max),
		Sources: repsSources()})
}

type putDailyRepsRequest struct {
	Exercise string `json:"exercise"`
	// Max is a max test: one set to near failure. RepsPerSet is a starting set the person picks
	// when they do not know their max yet. Exactly one of the two is sent.
	Max        *int `json:"max"`
	RepsPerSet *int `json:"repsPerSet"`
}

// handlePutDailyReps sets the exercise and the daily target of the pushups quest. A max is
// recorded as a max test of that exercise and sized into three sets; a starting set is taken as
// given. Like every goal edit, the change applies to today (docs/design-v18-quests.md).
func (s *Server) handlePutDailyReps(w http.ResponseWriter, r *http.Request) {
	var req putDailyRepsRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	if (req.Max == nil) == (req.RepsPerSet == nil) {
		fail(w, r, invalid("send either max or repsPerSet"))
		return
	}
	perSet := 0
	switch {
	case req.Max != nil && (*req.Max < 1 || *req.Max > maxRepsMax):
		fail(w, r, invalid(fmt.Sprintf("max must be between 1 and %d", maxRepsMax)))
		return
	case req.Max != nil:
		perSet = targets.ComputePushups(*req.Max, 0, 0).RepsPerSet
	case *req.RepsPerSet < 1 || *req.RepsPerSet > maxRepsPerSet:
		fail(w, r, invalid(fmt.Sprintf("repsPerSet must be between 1 and %d", maxRepsPerSet)))
		return
	default:
		perSet = *req.RepsPerSet
	}
	target := perSet * targets.PushupSets

	c := callerFrom(r)
	ctx := r.Context()
	enabled := true
	patch := patchMeRequest{QuestTemplates: []templatePatch{{Key: db.QuestPushups, Enabled: &enabled,
		Target: &target, Exercise: &req.Exercise}}}
	err := s.commitPatch(ctx, c, c.user, "", patch, func(tx pgx.Tx) error {
		if req.Max == nil {
			return nil
		}
		return s.recordRepsMax(ctx, tx, c, req.Exercise, *req.Max)
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	out, err := s.dailyReps(ctx, c)
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) recordRepsMax(ctx context.Context, tx pgx.Tx, c caller, key string, reps int) error {
	exercise, err := db.ExerciseByKey(ctx, tx, c.user.ID, key)
	if err != nil {
		return err
	}
	today := score.LocalToday(s.now(), c.loc)
	if err := db.UpsertMaxTest(ctx, tx, c.user.ID, db.MaxTest{ExerciseID: exercise.ID, LocalDate: today, Reps: &reps}); err != nil {
		return err
	}
	if key == db.DefaultRepsExercise {
		return db.SetPushupMax(ctx, tx, c.user.ID, today, reps)
	}
	return nil
}
