package api

import (
	"context"
	"errors"
	"net/http"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/score"
)

type targetsJSON struct {
	Kcal    *int `json:"kcal"`
	Protein *int `json:"protein"`
	Carbs   *int `json:"carbs"`
	Fat     *int `json:"fat"`
}

func toTargetsJSON(u db.User) targetsJSON {
	return targetsJSON{Kcal: u.KcalTarget, Protein: u.ProteinTarget, Carbs: u.CarbsTarget, Fat: u.FatTarget}
}

type templateJSON struct {
	Key       string  `json:"key"`
	Title     string  `json:"title"`
	Enabled   bool    `json:"enabled"`
	Target    int     `json:"target"`
	Unit      string  `json:"unit"`
	TargetAlt *int    `json:"targetAlt"`
	UnitAlt   *string `json:"unitAlt"`
	Points    int     `json:"points"`
	Position  int     `json:"position"`
}

type meJSON struct {
	User           userJSON       `json:"user"`
	Targets        targetsJSON    `json:"targets"`
	QuestTemplates []templateJSON `json:"questTemplates"`
	LocalToday     score.Date     `json:"localToday"`
	BackdateUntil  *string        `json:"backdateUntil"`
	ServerNow      string         `json:"serverNow"`
}

func (s *Server) buildMe(ctx context.Context, q db.Querier, u db.User) (meJSON, error) {
	loc, err := u.Location()
	if err != nil {
		return meJSON{}, err
	}
	templates, err := db.GetQuestTemplates(ctx, q, u.ID)
	if err != nil {
		return meJSON{}, err
	}
	out := make([]templateJSON, 0, len(templates))
	for _, t := range templates {
		out = append(out, templateJSON{
			Key: t.Key, Title: titles[t.Key], Enabled: t.Enabled, Target: t.Target, Unit: t.Unit,
			TargetAlt: t.TargetAlt, UnitAlt: t.UnitAlt, Points: t.Points, Position: t.Position,
		})
	}
	now := s.now()
	return meJSON{
		User:           toUserJSON(u),
		Targets:        toTargetsJSON(u),
		QuestTemplates: out,
		LocalToday:     score.LocalToday(now, loc),
		BackdateUntil:  s.backdateUntil(u, loc),
		ServerNow:      wireTime(now),
	}, nil
}

func (s *Server) handleGetMe(w http.ResponseWriter, r *http.Request) {
	me, err := s.buildMe(r.Context(), s.db.Pool, callerFrom(r).user)
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, me)
}

type targetsPatch struct {
	Kcal    nullable[int] `json:"kcal"`
	Protein nullable[int] `json:"protein"`
	Carbs   nullable[int] `json:"carbs"`
	Fat     nullable[int] `json:"fat"`
}

type templatePatch struct {
	Key       string `json:"key"`
	Enabled   *bool  `json:"enabled"`
	Target    *int   `json:"target"`
	TargetAlt *int   `json:"targetAlt"`
}

type patchMeRequest struct {
	Name           *string         `json:"name"`
	Color          *string         `json:"color"`
	Timezone       *string         `json:"timezone"`
	Targets        *targetsPatch   `json:"targets"`
	QuestTemplates []templatePatch `json:"questTemplates"`
}

// Bounds of the profile targets, mirroring the users table checks.
const (
	maxKcalTarget  = 10000
	maxMacroTarget = 1000
)

// applyTarget updates one target field from a PATCH, where null clears it.
func applyTarget(field **int, patch nullable[int], upper int, name string) *httpError {
	if !patch.Set {
		return nil
	}
	if patch.Value != nil && (*patch.Value < 1 || *patch.Value > upper) {
		return invalid(name + " target is out of range")
	}
	*field = patch.Value
	return nil
}

// handlePatchMe edits the profile and the quest templates. Every still-open day is scored first,
// which freezes its snapshot, so a template or protein-target change applies from the next day, except on the join day, which is re-snapshotted.
func (s *Server) handlePatchMe(w http.ResponseWriter, r *http.Request) {
	var req patchMeRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	c := callerFrom(r)
	user := c.user
	if err := s.applyProfilePatch(&user, req); err != nil {
		fail(w, r, err)
		return
	}
	var zone string
	if req.Timezone != nil {
		loc, herr := loadZone(*req.Timezone)
		if herr != nil {
			fail(w, r, herr)
			return
		}
		zone = loc.String()
	}

	ctx := r.Context()
	err := s.db.WithTx(ctx, func(tx pgx.Tx) error {
		for _, date := range s.openDates(c.user, c.loc) {
			if _, err := engine.RecomputeDayAt(ctx, tx, user.ID, date, c.loc, s.now()); err != nil {
				return err
			}
		}
		if err := db.UpdateUser(ctx, tx, user); err != nil {
			return mapUpdateUserErr(err)
		}
		if zone != "" && !c.user.IsZoneStaged(zone) {
			// Tomorrow in the current zone, so today keeps its date whatever the new zone says.
			from := score.LocalToday(s.now(), c.loc).AddDays(1)
			if err := db.StageTimezone(ctx, tx, user.ID, zone, from); err != nil {
				return err
			}
		}
		if err := applyTemplatePatches(ctx, tx, user.ID, req.QuestTemplates); err != nil {
			return err
		}
		return s.resnapshotJoinDay(ctx, tx, c, user, req)
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
	writeJSON(w, http.StatusOK, me)
}

// resnapshotJoinDay lets a brand-new person's first day follow the quests and targets they
// pick during onboarding. The day lock taken by the earlier rescore is still held, so a
// concurrent log or Health write waits and then scores against the new snapshot. Every later
// day keeps the next-day rule.
func (s *Server) resnapshotJoinDay(ctx context.Context, tx pgx.Tx, c caller, user db.User, req patchMeRequest) error {
	today := score.LocalToday(s.now(), c.loc)
	if today != c.user.JoinedOn || (len(req.QuestTemplates) == 0 && req.Targets == nil) {
		return nil
	}
	if err := db.LockUserDay(ctx, tx, user.ID, today); err != nil {
		return err
	}
	if err := db.ResetDaySnapshot(ctx, tx, user.ID, today); err != nil {
		return err
	}
	_, err := engine.RecomputeDayAt(ctx, tx, user.ID, today, c.loc, s.now())
	return err
}

// applyProfilePatch validates the profile fields of a PATCH and writes them onto u.
func (s *Server) applyProfilePatch(u *db.User, req patchMeRequest) *httpError {
	if req.Name != nil {
		name, err := cleanName(*req.Name)
		if err != nil {
			return err
		}
		u.Name = name
	}
	if req.Color != nil {
		if err := checkColor(*req.Color); err != nil {
			return err
		}
		u.Color = *req.Color
	}
	if t := req.Targets; t != nil {
		for _, step := range []*httpError{
			applyTarget(&u.KcalTarget, t.Kcal, maxKcalTarget, "kcal"),
			applyTarget(&u.ProteinTarget, t.Protein, maxMacroTarget, "protein"),
			applyTarget(&u.CarbsTarget, t.Carbs, maxMacroTarget, "carbs"),
			applyTarget(&u.FatTarget, t.Fat, maxMacroTarget, "fat"),
		} {
			if step != nil {
				return step
			}
		}
	}
	return nil
}

func mapUpdateUserErr(err error) error {
	switch {
	case errors.Is(err, db.ErrNameTaken):
		return newErr(http.StatusConflict, codeNameTaken, "that name is already taken")
	case errors.Is(err, db.ErrColorTaken):
		return newErr(http.StatusConflict, codeColorTaken, "that color is already taken")
	}
	return err
}

// applyTemplatePatches writes the editable parts of the named templates: enabled and targets.
func applyTemplatePatches(ctx context.Context, tx pgx.Tx, userID int64, patches []templatePatch) error {
	if len(patches) == 0 {
		return nil
	}
	templates, err := db.GetQuestTemplates(ctx, tx, userID)
	if err != nil {
		return err
	}
	byKey := make(map[string]db.QuestTemplate, len(templates))
	for _, t := range templates {
		byKey[t.Key] = t
	}
	for _, p := range patches {
		t, ok := byKey[p.Key]
		if !ok {
			return invalid("unknown quest " + p.Key)
		}
		if p.Enabled != nil {
			t.Enabled = *p.Enabled
		}
		if p.Target != nil {
			t.Target = *p.Target
		}
		if p.TargetAlt != nil {
			if t.UnitAlt == nil {
				return invalid(p.Key + " has no second target")
			}
			t.TargetAlt = p.TargetAlt
		}
		if err := db.UpsertQuestTemplate(ctx, tx, userID, t); err != nil {
			var pgErr *pgconn.PgError
			if errors.As(err, &pgErr) && pgErr.Code == "23514" {
				return invalid(p.Key + " target is out of range")
			}
			return err
		}
		byKey[p.Key] = t
	}
	return nil
}
