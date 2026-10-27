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
	u.carbs_target, u.fat_target, u.joined_on::text, u.created_at`

// scanUser reads userColumns, after any leading columns the query selected first.
func scanUser(row pgx.Row, leading ...any) (User, error) {
	var u User
	dest := append(leading, &u.ID, &u.Name, &u.Color, &u.Timezone, &u.IsAdmin, &u.KcalTarget, &u.ProteinTarget,
		&u.CarbsTarget, &u.FatTarget, &u.JoinedOn, &u.CreatedAt)
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

// UpdateUser writes back the editable profile fields: name, color, timezone and targets.
func UpdateUser(ctx context.Context, q Querier, u User) error {
	tag, err := q.Exec(ctx, `
		UPDATE users SET name = $2, color = $3, timezone = $4,
			kcal_target = $5, protein_target = $6, carbs_target = $7, fat_target = $8
		WHERE id = $1 AND deleted_at IS NULL`,
		u.ID, u.Name, u.Color, u.Timezone, u.KcalTarget, u.ProteinTarget, u.CarbsTarget, u.FatTarget)
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
	_, err = tx.Exec(ctx, `DELETE FROM devices WHERE user_id = $1`, id)
	return err
}
