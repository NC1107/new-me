package api

import (
	"context"
	"errors"
	"fmt"
	"math"
	"net/http"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/targets"
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
	User           userJSON          `json:"user"`
	Targets        targetsJSON       `json:"targets"`
	QuestTemplates []templateJSON    `json:"questTemplates"`
	LocalToday     score.Date        `json:"localToday"`
	BackdateUntil  *string           `json:"backdateUntil"`
	ServerNow      string            `json:"serverNow"`
	Audiobookshelf *absJSON          `json:"audiobookshelf"`
	Notifications  notificationsJSON `json:"notifications"`
	Features       featuresJSON      `json:"features"`
	Schedule       scheduleJSON      `json:"schedule"`
	Protein        proteinJSON       `json:"protein"`
}

type dayTimesJSON struct {
	Wake string `json:"wake"`
	Bed  string `json:"bed"`
}

// scheduleJSON is the person's general rhythm: wake and bed times for workdays and days off,
// which weekdays are workdays (ISO 1 to 7), and how long after waking the first notification may
// come.
type scheduleJSON struct {
	Workdays                   []int        `json:"workdays"`
	Workday                    dayTimesJSON `json:"workday"`
	DayOff                     dayTimesJSON `json:"dayOff"`
	FirstNotificationOffsetMin int          `json:"firstNotificationOffsetMin"`
}

func toScheduleJSON(s score.Schedule) scheduleJSON {
	return scheduleJSON{
		Workdays:                   score.ISOWeekdays(s.Workdays),
		Workday:                    dayTimesJSON{Wake: score.FormatClock(s.Workday.WakeMin), Bed: score.FormatClock(s.Workday.BedMin)},
		DayOff:                     dayTimesJSON{Wake: score.FormatClock(s.DayOff.WakeMin), Bed: score.FormatClock(s.DayOff.BedMin)},
		FirstNotificationOffsetMin: s.FirstOffsetMin,
	}
}

type dayTimesPatch struct {
	Wake *string `json:"wake"`
	Bed  *string `json:"bed"`
}

type schedulePatch struct {
	Workdays                   *[]int         `json:"workdays"`
	Workday                    *dayTimesPatch `json:"workday"`
	DayOff                     *dayTimesPatch `json:"dayOff"`
	FirstNotificationOffsetMin *int           `json:"firstNotificationOffsetMin"`
}

func applyDayTimes(day *score.DaySchedule, p *dayTimesPatch, name string) *httpError {
	if p == nil {
		return nil
	}
	for _, f := range []struct {
		field *int
		patch *string
		label string
	}{{&day.WakeMin, p.Wake, "wake"}, {&day.BedMin, p.Bed, "bed"}} {
		if f.patch == nil {
			continue
		}
		minutes, err := score.ParseClock(*f.patch)
		if err != nil {
			return invalid(name + " " + f.label + " must be HH:MM")
		}
		*f.field = minutes
	}
	return nil
}

// applySchedulePatch writes a schedule PATCH onto u.
func applySchedulePatch(u *db.User, p *schedulePatch) *httpError {
	if p == nil {
		return nil
	}
	if p.Workdays != nil {
		mask := 0
		if len(*p.Workdays) > 0 {
			var ok bool
			if mask, ok = score.WeekdaysFromISO(*p.Workdays); !ok {
				return invalid("workdays must be weekday numbers from 1 (Monday) to 7 (Sunday)")
			}
		}
		u.Schedule.Workdays = mask
	}
	if err := applyDayTimes(&u.Schedule.Workday, p.Workday, "workday"); err != nil {
		return err
	}
	if err := applyDayTimes(&u.Schedule.DayOff, p.DayOff, "dayOff"); err != nil {
		return err
	}
	if p.FirstNotificationOffsetMin != nil {
		u.Schedule.FirstOffsetMin = *p.FirstNotificationOffsetMin
	}
	if err := u.Schedule.Validate(); err != nil {
		return invalid(err.Error())
	}
	return nil
}

// proteinJSON explains the protein target: the per-kilogram default, the latest weight it
// comes from, what it would be, and the target in force.
type proteinJSON struct {
	PerKg float64 `json:"perKg"`
	// Auto is true while the target follows the per-kilogram default.
	Auto      bool     `json:"auto"`
	WeightKg  *float64 `json:"weightKg"`
	Suggested *int     `json:"suggested"`
	Effective int      `json:"effective"`
}

// featuresJSON tells the app which optional server features are switched on, so it can hide
// the buttons of the ones that are not.
type featuresJSON struct {
	MealEstimate bool `json:"mealEstimate"`
	PlanPolish   bool `json:"planPolish"`
}

type notificationsJSON struct {
	PartnerDone bool `json:"partnerDone"`
	Cheers      bool `json:"cheers"`
	Challenge   bool `json:"challenge"`
	Reward      bool `json:"reward"`
	BehindPace  bool `json:"behindPace"`
	CloseToDone bool `json:"closeToDone"`
	WindDown    bool `json:"windDown"`
	MorningPlan bool `json:"morningPlan"`
	WeeklyRecap bool `json:"weeklyRecap"`
	Milestones  bool `json:"milestones"`
	Lookback    bool `json:"lookback"`
}

type notificationsPatch struct {
	PartnerDone *bool `json:"partnerDone"`
	Cheers      *bool `json:"cheers"`
	Challenge   *bool `json:"challenge"`
	Reward      *bool `json:"reward"`
	BehindPace  *bool `json:"behindPace"`
	CloseToDone *bool `json:"closeToDone"`
	WindDown    *bool `json:"windDown"`
	MorningPlan *bool `json:"morningPlan"`
	WeeklyRecap *bool `json:"weeklyRecap"`
	Milestones  *bool `json:"milestones"`
	Lookback    *bool `json:"lookback"`
}

// proteinFor describes the protein target in force for the person.
func proteinFor(ctx context.Context, q db.Querier, u db.User, today score.Date, templateTarget int) (proteinJSON, error) {
	out := proteinJSON{PerKg: score.ProteinPerKg, Effective: templateTarget}
	latest, err := db.LatestHealth(ctx, q, u.ID, today, []string{db.MetricWeight})
	if err != nil {
		return out, err
	}
	if w, ok := latest[db.MetricWeight]; ok {
		kg := round1(w.Value)
		suggested := score.ProteinTarget(w.Value)
		out.WeightKg, out.Suggested = &kg, &suggested
	}
	switch {
	case u.ProteinTarget != nil:
		out.Effective = *u.ProteinTarget
	case u.ProteinAuto && out.Suggested != nil:
		out.Auto, out.Effective = true, *out.Suggested
	case u.ProteinAuto:
		out.Auto = true
	}
	return out, nil
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
	abs, err := s.absState(ctx, q, u.ID)
	if err != nil {
		return meJSON{}, err
	}
	now := s.now()
	proteinTemplate := db.DefaultProteinTarget
	for _, t := range templates {
		if t.Key == db.QuestProtein {
			proteinTemplate = t.Target
		}
	}
	protein, err := proteinFor(ctx, q, u, score.LocalToday(now, loc), proteinTemplate)
	if err != nil {
		return meJSON{}, err
	}
	return meJSON{
		User:           toUserJSON(u),
		Targets:        toTargetsJSON(u),
		QuestTemplates: out,
		LocalToday:     score.LocalToday(now, loc),
		BackdateUntil:  s.backdateUntil(u, loc),
		ServerNow:      wireTime(now),
		Audiobookshelf: abs,
		Notifications: notificationsJSON{PartnerDone: u.Notify.PartnerDone, Cheers: u.Notify.Cheers,
			Challenge: u.Notify.Challenge, Reward: u.Notify.Reward, BehindPace: u.Notify.BehindPace,
			CloseToDone: u.Notify.CloseToDone, WindDown: u.Notify.WindDown, MorningPlan: u.Notify.MorningPlan,
			WeeklyRecap: u.Notify.WeeklyRecap, Milestones: u.Notify.Milestones, Lookback: u.Notify.Lookback},
		Features: featuresJSON{MealEstimate: s.estimator != nil, PlanPolish: s.cfg.Anthropic.Enabled()},
		Schedule: toScheduleJSON(u.Schedule),
		Protein:  protein,
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
	Name           *string             `json:"name"`
	Color          *string             `json:"color"`
	Timezone       *string             `json:"timezone"`
	Targets        *targetsPatch       `json:"targets"`
	BirthYear      nullable[int]       `json:"birthYear"`
	QuestTemplates []templatePatch     `json:"questTemplates"`
	Notifications  *notificationsPatch `json:"notifications"`
	Schedule       *schedulePatch      `json:"schedule"`
	HeightCm       nullable[float64]   `json:"heightCm"`
	Sex            nullable[string]    `json:"sex"`
	Goal           *goalPatch          `json:"goal"`
	Units          *string             `json:"units"`
}

// goalPatch sets the weight goal. The pace is kg a week in hundredths: 0.2 to 0.5 to lose, 0.05
// to 1 to gain, and 0 (or absent) to maintain, so imperial choices (0.5 or 1 lb) store exactly.
type goalPatch struct {
	Kind          *string  `json:"kind"`
	PaceKgPerWeek *float64 `json:"paceKgPerWeek"`
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
	err := s.commitPatch(ctx, c, user, zone, req)
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

// commitPatch writes the validated profile and template changes in one transaction. Every
// still-open day is scored first, which freezes its snapshot, so the change applies from the next
// day, except on the join day (see resnapshotJoinDay). zone is the staged time zone, if any, and
// after runs inside the same transaction.
func (s *Server) commitPatch(ctx context.Context, c caller, user db.User, zone string, req patchMeRequest,
	after ...func(tx pgx.Tx) error) error {
	return s.db.WithTx(ctx, func(tx pgx.Tx) error {
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
		if err := s.resnapshotJoinDay(ctx, tx, c, user, req); err != nil {
			return err
		}
		for _, fn := range after {
			if err := fn(tx); err != nil {
				return err
			}
		}
		return nil
	})
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
	if req.BirthYear.Set {
		if err := s.applyBirthYear(u, req.BirthYear.Value); err != nil {
			return err
		}
	}
	if n := req.Notifications; n != nil {
		for _, sw := range []struct {
			field *bool
			patch *bool
		}{{&u.Notify.PartnerDone, n.PartnerDone}, {&u.Notify.Cheers, n.Cheers},
			{&u.Notify.Challenge, n.Challenge}, {&u.Notify.Reward, n.Reward},
			{&u.Notify.BehindPace, n.BehindPace}, {&u.Notify.CloseToDone, n.CloseToDone},
			{&u.Notify.WindDown, n.WindDown}, {&u.Notify.MorningPlan, n.MorningPlan},
			{&u.Notify.WeeklyRecap, n.WeeklyRecap}, {&u.Notify.Milestones, n.Milestones},
			{&u.Notify.Lookback, n.Lookback}} {
			if sw.patch != nil {
				*sw.field = *sw.patch
			}
		}
	}
	if err := applySchedulePatch(u, req.Schedule); err != nil {
		return err
	}
	if err := applyBody(u, req); err != nil {
		return err
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

// Bounds of the height, mirroring the users table check.
const (
	minHeightCm = 100
	maxHeightCm = 250
)

// applyBody sets or clears the height and sex and sets the goal.
func applyBody(u *db.User, req patchMeRequest) *httpError {
	if req.HeightCm.Set {
		if h := req.HeightCm.Value; h == nil {
			u.HeightCm = nil
		} else {
			if math.IsNaN(*h) || *h < minHeightCm || *h > maxHeightCm {
				return invalid(fmt.Sprintf("heightCm must be between %d and %d", minHeightCm, maxHeightCm))
			}
			rounded := math.Round(*h*10) / 10
			u.HeightCm = &rounded
		}
	}
	if req.Sex.Set {
		if v := req.Sex.Value; v != nil && *v != string(targets.Male) && *v != string(targets.Female) {
			return invalid("sex must be male, female or null")
		}
		u.Sex = req.Sex.Value
	}
	if req.Units != nil {
		if *req.Units != db.UnitsMetric && *req.Units != db.UnitsImperial {
			return invalid("units must be metric or imperial")
		}
		u.Units = *req.Units
	}
	return applyGoal(u, req.Goal)
}

// applyGoal validates a goal: lose at 0.25 or 0.5 kg a week, gain at a multiple of 0.05 up to 1
// kg (the 0.5% of body weight cap is applied against the weight when the target is computed),
// maintain at 0.
func applyGoal(u *db.User, g *goalPatch) *httpError {
	if g == nil {
		return nil
	}
	if g.Kind == nil {
		return invalid("goal kind is required")
	}
	pace := 0.0
	if g.PaceKgPerWeek != nil {
		pace = math.Round(*g.PaceKgPerWeek*100) / 100
	}
	switch *g.Kind {
	case targets.Maintain:
		if pace != 0 {
			return invalid("a maintain goal has no pace")
		}
	case targets.Lose:
		if pace < targets.MinLosePace || pace > targets.MaxLosePace {
			return invalid("lose pace must be 0.2 to 0.5 kg a week")
		}
	case targets.Gain:
		if pace < targets.MinGainPace || pace > 1 {
			return invalid("gain pace must be 0.05 to 1 kg a week")
		}
	default:
		return invalid("goal kind must be lose, maintain or gain")
	}
	u.GoalKind, u.GoalPaceKg = *g.Kind, pace
	return nil
}

// minBirthYear mirrors the users table check.
const minBirthYear = 1900

// applyBirthYear sets or clears the birth year. The newest allowed year is the current one in
// the person's own zone, so someone ahead of UTC is never refused a valid year.
func (s *Server) applyBirthYear(u *db.User, year *int) *httpError {
	if year == nil {
		u.BirthYear = nil
		return nil
	}
	loc, err := u.Location()
	if err != nil {
		return invalid("birthYear cannot be checked")
	}
	if thisYear := s.now().In(loc).Year(); *year < minBirthYear || *year > thisYear {
		return invalid(fmt.Sprintf("birthYear must be between %d and %d", minBirthYear, thisYear))
	}
	u.BirthYear = year
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
