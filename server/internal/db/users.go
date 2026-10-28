package db

import (
	"context"
	"errors"
	"fmt"
	"time"
	// The distroless image ships no zoneinfo, and every user stores an IANA zone name.
	_ "time/tzdata"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/score"
)

var (
	// ErrServerFull means the join would exceed the configured user cap.
	ErrServerFull = errors.New("server is full")
	// ErrNameTaken means another live user already has the name, ignoring case.
	ErrNameTaken = errors.New("name already taken")
	// ErrColorTaken means another live user already has the color.
	ErrColorTaken = errors.New("color already taken")
	// ErrAdminExists means a live admin is already present.
	ErrAdminExists = errors.New("an admin already exists")
	// ErrRewardActive means a reward is still being earned, and only one may be at a time.
	ErrRewardActive = errors.New("a reward is already active")
)

// joinLockKey serializes joins; the one-argument advisory lock space is separate from the
// two-argument day locks, so the keys cannot collide.
const joinLockKey int64 = 4915012027

// User is a profile row. Targets are nil until the user sets them.
type User struct {
	ID            int64
	Name          string
	Color         string
	Timezone      string
	IsAdmin       bool
	KcalTarget    *int
	ProteinTarget *int
	CarbsTarget   *int
	FatTarget     *int
	JoinedOn      score.Date
	CreatedAt     time.Time
	// PendingTimezone is a zone the user chose that has not taken effect yet; Timezone stays the
	// zone every date is computed in until it does.
	PendingTimezone *string
	PendingFrom     *score.Date
	// BirthYear is optional and only picks the age band of the step suggestion.
	BirthYear *int
	// Notify holds the push events the person wants.
	Notify Notifications
	// Schedule is the person's wake and bed times, workdays and first-notification offset.
	Schedule score.Schedule
	// StreakRulesFrom is the first local date scored by the freeze rules; nil means all days.
	StreakRulesFrom *score.Date
	// ProteinAuto makes an unset protein target follow 1.6 g/kg of the latest weight.
	ProteinAuto bool
	// HeightCm and Sex are the v8 profile inputs; nil until entered. Health's height is used
	// when HeightCm is empty.
	HeightCm *float64
	Sex      *string
	// GoalKind is lose, maintain or gain; GoalPaceKg is kg a week, 0 for maintain.
	GoalKind   string
	GoalPaceKg float64
	// Units is metric or imperial: what the person reads. Everything is stored metric.
	Units string
}

// Unit systems a person can choose.
const (
	UnitsMetric   = "metric"
	UnitsImperial = "imperial"
)

// Imperial reports whether the person reads pounds, feet and inches.
func (u User) Imperial() bool { return u.Units == UnitsImperial }

// Notifications are the per-person switches of the push events.
type Notifications struct {
	PartnerDone bool
	Cheers      bool
	Challenge   bool
	Reward      bool
	// The v6 autopilot events.
	BehindPace  bool
	CloseToDone bool
	WindDown    bool
	MorningPlan bool
	WeeklyRecap bool
	// The v7 events: milestones and the monthly look-back.
	Milestones bool
	Lookback   bool
}

// ChosenTimezone is the zone the user last picked, which is what their profile shows.
func (u User) ChosenTimezone() string {
	if u.PendingTimezone != nil {
		return *u.PendingTimezone
	}
	return u.Timezone
}

// IsZoneStaged reports whether the zone is already waiting to take effect.
func (u User) IsZoneStaged(zone string) bool {
	return u.PendingTimezone != nil && *u.PendingTimezone == zone
}

// Location loads the user's time zone.
func (u User) Location() (*time.Location, error) {
	loc, err := time.LoadLocation(u.Timezone)
	if err != nil {
		return nil, fmt.Errorf("user %d timezone %q: %w", u.ID, u.Timezone, err)
	}
	return loc, nil
}

const userColumns = `u.id, u.name, u.color, u.timezone, u.is_admin, u.kcal_target, u.protein_target,
	u.carbs_target, u.fat_target, u.joined_on::text, u.created_at, u.pending_timezone, u.pending_from::text,
	u.birth_year, u.notify_partner_done, u.notify_cheers, u.notify_challenge, u.notify_reward,
	u.notify_behind_pace, u.notify_close_to_done, u.notify_wind_down, u.notify_morning_plan, u.notify_weekly_recap,
	u.notify_milestones, u.notify_lookback, u.streak_rules_from::text, u.protein_auto, u.workdays,
	u.workday_wake_min, u.workday_bed_min, u.dayoff_wake_min, u.dayoff_bed_min, u.first_notification_offset_min,
	u.height_cm::float8, u.sex, u.goal_kind, u.goal_pace_kg::float8, u.units`

// scanUser reads userColumns, after any leading columns the query selected first.
func scanUser(row pgx.Row, leading ...any) (User, error) {
	var u User
	dest := append(leading, &u.ID, &u.Name, &u.Color, &u.Timezone, &u.IsAdmin, &u.KcalTarget, &u.ProteinTarget,
		&u.CarbsTarget, &u.FatTarget, &u.JoinedOn, &u.CreatedAt, &u.PendingTimezone, &u.PendingFrom, &u.BirthYear,
		&u.Notify.PartnerDone, &u.Notify.Cheers, &u.Notify.Challenge, &u.Notify.Reward,
		&u.Notify.BehindPace, &u.Notify.CloseToDone, &u.Notify.WindDown, &u.Notify.MorningPlan, &u.Notify.WeeklyRecap,
		&u.Notify.Milestones, &u.Notify.Lookback, &u.StreakRulesFrom, &u.ProteinAuto, &u.Schedule.Workdays,
		&u.Schedule.Workday.WakeMin, &u.Schedule.Workday.BedMin, &u.Schedule.DayOff.WakeMin, &u.Schedule.DayOff.BedMin,
		&u.Schedule.FirstOffsetMin, &u.HeightCm, &u.Sex, &u.GoalKind, &u.GoalPaceKg, &u.Units)
	return u, row.Scan(dest...)
}

// NewUser is what a join supplies. JoinedOn is the user's local date at join time.
type NewUser struct {
	Name     string
	Color    string
	Timezone string
	IsAdmin  bool
	JoinedOn score.Date
}

// CreateUser inserts a user and seeds the default quest templates. It takes the join lock
// first, so the user cap and the single-admin rule hold even for simultaneous joins. The first
// admin also flips the server to initialized.
func CreateUser(ctx context.Context, tx pgx.Tx, n NewUser, maxUsers int) (User, error) {
	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock($1)`, joinLockKey); err != nil {
		return User{}, err
	}
	var live int
	if err := tx.QueryRow(ctx, `SELECT count(*) FROM users WHERE deleted_at IS NULL`).Scan(&live); err != nil {
		return User{}, err
	}
	if live >= maxUsers {
		return User{}, ErrServerFull
	}

	u, err := scanUser(tx.QueryRow(ctx, `
		INSERT INTO users AS u (name, color, timezone, is_admin, joined_on)
		VALUES ($1, $2, $3, $4, $5::date)
		RETURNING `+userColumns, n.Name, n.Color, n.Timezone, n.IsAdmin, n.JoinedOn))
	if err != nil {
		switch violatedConstraint(err) {
		case "users_name_live":
			return User{}, ErrNameTaken
		case "users_color_live":
			return User{}, ErrColorTaken
		case "users_single_admin":
			return User{}, ErrAdminExists
		}
		return User{}, err
	}
	if err := SeedDefaultTemplates(ctx, tx, u.ID); err != nil {
		return User{}, err
	}
	if n.IsAdmin {
		if err := MarkInitialized(ctx, tx); err != nil {
			return User{}, err
		}
	}
	return u, nil
}

// MarkInitialized flags the server as having its admin.
func MarkInitialized(ctx context.Context, q Querier) error {
	_, err := q.Exec(ctx, `UPDATE server_config SET initialized = true WHERE id = 1`)
	return err
}

// GetUser returns a live user.
func GetUser(ctx context.Context, q Querier, id int64) (User, error) {
	u, err := scanUser(q.QueryRow(ctx,
		`SELECT `+userColumns+` FROM users u WHERE u.id = $1 AND u.deleted_at IS NULL`, id))
	return u, notFound(err)
}

// ListUsers returns every live user, oldest first.
func ListUsers(ctx context.Context, q Querier) ([]User, error) {
	rows, err := q.Query(ctx,
		`SELECT `+userColumns+` FROM users u WHERE u.deleted_at IS NULL ORDER BY u.id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var users []User
	for rows.Next() {
		u, err := scanUser(rows)
		if err != nil {
			return nil, err
		}
		users = append(users, u)
	}
	return users, rows.Err()
}

// CountUsers returns how many live users exist.
func CountUsers(ctx context.Context, q Querier) (int, error) {
	var n int
	err := q.QueryRow(ctx, `SELECT count(*) FROM users WHERE deleted_at IS NULL`).Scan(&n)
	return n, err
}

// UpdateUser writes back the editable profile fields: name, color, targets, birth year, height, sex, goal, schedule and notification switches. The time zone
// has its own functions, because it changes on a schedule rather than at the moment of the edit.
func UpdateUser(ctx context.Context, q Querier, u User) error {
	tag, err := q.Exec(ctx, `
		UPDATE users SET name = $2, color = $3,
			kcal_target = $4, protein_target = $5, carbs_target = $6, fat_target = $7,
			birth_year = $8, notify_partner_done = $9, notify_cheers = $10, notify_challenge = $11,
			notify_reward = $12, notify_behind_pace = $13, notify_close_to_done = $14,
			notify_wind_down = $15, notify_morning_plan = $16, notify_weekly_recap = $17,
			notify_milestones = $18, notify_lookback = $19, workdays = $20,
			workday_wake_min = $21, workday_bed_min = $22, dayoff_wake_min = $23, dayoff_bed_min = $24,
			first_notification_offset_min = $25, protein_auto = $26,
			height_cm = $27::numeric, sex = $28, goal_kind = $29, goal_pace_kg = $30::numeric, units = $31
		WHERE id = $1 AND deleted_at IS NULL`,
		u.ID, u.Name, u.Color, u.KcalTarget, u.ProteinTarget, u.CarbsTarget, u.FatTarget, u.BirthYear,
		u.Notify.PartnerDone, u.Notify.Cheers, u.Notify.Challenge, u.Notify.Reward,
		u.Notify.BehindPace, u.Notify.CloseToDone, u.Notify.WindDown, u.Notify.MorningPlan, u.Notify.WeeklyRecap,
		u.Notify.Milestones, u.Notify.Lookback, u.Schedule.Workdays,
		u.Schedule.Workday.WakeMin, u.Schedule.Workday.BedMin, u.Schedule.DayOff.WakeMin, u.Schedule.DayOff.BedMin,
		u.Schedule.FirstOffsetMin, u.ProteinAuto, u.HeightCm, u.Sex, u.GoalKind, u.GoalPaceKg, u.Units)
	if err != nil {
		switch violatedConstraint(err) {
		case "users_name_live":
			return ErrNameTaken
		case "users_color_live":
			return ErrColorTaken
		}
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// SoftDeleteUser retires a user and revokes their devices, freeing the name and color.
func SoftDeleteUser(ctx context.Context, tx pgx.Tx, id int64) error {
	tag, err := tx.Exec(ctx, `UPDATE users SET deleted_at = now() WHERE id = $1 AND deleted_at IS NULL`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	if _, err = tx.Exec(ctx, `DELETE FROM devices WHERE user_id = $1`, id); err != nil {
		return err
	}
	// The stored Audiobookshelf tokens are credentials, so they go with the person.
	_, err = tx.Exec(ctx, `DELETE FROM audiobookshelf_accounts WHERE user_id = $1`, id)
	return err
}

// StageTimezone records the zone the user picked to take effect from the given local date of
// their current zone. Picking the zone already in force cancels any staged change.
func StageTimezone(ctx context.Context, q Querier, userID int64, zone string, from score.Date) error {
	_, err := q.Exec(ctx, `
		UPDATE users SET
			pending_timezone = CASE WHEN timezone = $2 THEN NULL ELSE $2 END,
			pending_from = CASE WHEN timezone = $2 THEN NULL ELSE $3::date END
		WHERE id = $1 AND deleted_at IS NULL`, userID, zone, from)
	return err
}

// SwitchTimezoneIfDue puts a staged zone into force and returns the refreshed user. It waits
// until the current zone has reached the staged date and the new zone's date is not behind the
// current one's, so no local date is repeated or skipped by the switch.
func SwitchTimezoneIfDue(ctx context.Context, q Querier, u User, now time.Time) (User, error) {
	if u.PendingTimezone == nil || u.PendingFrom == nil {
		return u, nil
	}
	current, err := u.Location()
	if err != nil {
		return u, err
	}
	next, err := time.LoadLocation(*u.PendingTimezone)
	if err != nil {
		return u, fmt.Errorf("user %d pending timezone %q: %w", u.ID, *u.PendingTimezone, err)
	}
	currentDay := score.LocalToday(now, current)
	if currentDay.Before(*u.PendingFrom) || score.LocalToday(now, next).Before(currentDay) {
		return u, nil
	}
	// The staged values in the WHERE keep two racing requests from switching twice.
	if _, err := q.Exec(ctx, `
		UPDATE users SET timezone = pending_timezone, pending_timezone = NULL, pending_from = NULL
		WHERE id = $1 AND pending_timezone = $2 AND pending_from = $3::date`,
		u.ID, *u.PendingTimezone, *u.PendingFrom); err != nil {
		return u, err
	}
	return GetUser(ctx, q, u.ID)
}
