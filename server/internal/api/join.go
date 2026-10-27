package api

import (
	"context"
	"errors"
	"net/http"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/auth"
	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/score"
)

type userJSON struct {
	ID       int64  `json:"id"`
	Name     string `json:"name"`
	Color    string `json:"color"`
	Timezone string `json:"timezone"`
	IsAdmin  bool   `json:"isAdmin"`
}

func toUserJSON(u db.User) userJSON {
	return userJSON{ID: u.ID, Name: u.Name, Color: u.Color, Timezone: u.ChosenTimezone(), IsAdmin: u.IsAdmin}
}

type joinRequest struct {
	Code     *string `json:"code"`
	UserID   *int64  `json:"userId"`
	Name     *string `json:"name"`
	Color    *string `json:"color"`
	Timezone *string `json:"timezone"`
}

func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

// errBadCode marks a join whose invite code was not redeemable, so the handler can charge the
// miss outside the transaction that rolled back.
var errBadCode = errors.New("invite code not redeemable")

// handleJoin pairs a device. The first join on an uninitialized server creates the admin and
// needs no code; every later join and every re-pair redeems a single-use invite code.
func (s *Server) handleJoin(w http.ResponseWriter, r *http.Request) {
	var req joinRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	info, err := s.db.GetServerInfo(r.Context())
	if err != nil {
		fail(w, r, err)
		return
	}

	var result joinResult
	switch {
	case !info.Initialized:
		result, err = s.joinNew(r.Context(), req, "", true)
	case req.UserID != nil:
		result, err = s.repair(r.Context(), req)
	default:
		result, err = s.joinNew(r.Context(), req, deref(req.Code), false)
	}
	if errors.Is(err, errBadCode) {
		s.rejectCode(w, r)
		return
	}
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"user": toUserJSON(result.user), "token": result.token})
}

type joinResult struct {
	user  db.User
	token string
}

// rejectCode charges a wrong code against the outstanding invites and answers 403. The charge
// goes through the pool so it survives the rollback of the join transaction.
func (s *Server) rejectCode(w http.ResponseWriter, r *http.Request) {
	if err := db.RecordInviteMiss(r.Context(), s.db.Pool); err != nil {
		fail(w, r, err)
		return
	}
	writeErr(w, http.StatusForbidden, codeInvalidCode, "that code is not valid")
}

// spendCode redeems the code inside the join transaction.
func spendCode(ctx context.Context, tx pgx.Tx, code string) error {
	err := db.ConsumeInvite(ctx, tx, auth.HashInviteCode(code))
	if errors.Is(err, db.ErrInviteInvalid) {
		return errBadCode
	}
	return err
}

// joinNew creates a user. The admin join passes first=true and no code.
func (s *Server) joinNew(ctx context.Context, req joinRequest, code string, first bool) (joinResult, error) {
	name, herr := cleanName(deref(req.Name))
	if herr != nil {
		return joinResult{}, herr
	}
	color := deref(req.Color)
	if herr := checkColor(color); herr != nil {
		return joinResult{}, herr
	}
	loc, herr := loadZone(deref(req.Timezone))
	if herr != nil {
		return joinResult{}, herr
	}
	if !first && auth.NormalizeInviteCode(code) == "" {
		if code == "" {
			return joinResult{}, invalid("an invite code is required")
		}
		return joinResult{}, errBadCode
	}

	now := s.now()
	today := score.LocalToday(now, loc)
	var out joinResult
	err := s.db.WithTx(ctx, func(tx pgx.Tx) error {
		if !first {
			if err := spendCode(ctx, tx, code); err != nil {
				return err
			}
		}
		user, err := db.CreateUser(ctx, tx, db.NewUser{
			Name: name, Color: color, Timezone: loc.String(), IsAdmin: first, JoinedOn: today,
		}, s.cfg.MaxUsers)
		if err != nil {
			return mapCreateUserErr(err)
		}
		// Scoring the join day makes it a real day for the streak instead of a missing one.
		if _, err := engine.RecomputeDayAt(ctx, tx, user.ID, today, loc, now); err != nil {
			return err
		}
		out.user = user
		out.token, err = issueDevice(ctx, tx, user.ID)
		return err
	})
	return out, err
}

func mapCreateUserErr(err error) error {
	switch {
	case errors.Is(err, db.ErrServerFull):
		return newErr(http.StatusConflict, codeServerFull, "this server has no room for another person")
	case errors.Is(err, db.ErrNameTaken):
		return newErr(http.StatusConflict, codeNameTaken, "that name is already taken")
	case errors.Is(err, db.ErrColorTaken):
		return newErr(http.StatusConflict, codeColorTaken, "that color is already taken")
	case errors.Is(err, db.ErrAdminExists):
		return newErr(http.StatusConflict, codeInitialized, "this server is already set up, ask for an invite code")
	}
	return err
}

// repair gives an existing user a fresh device and signs out their other installs.
func (s *Server) repair(ctx context.Context, req joinRequest) (joinResult, error) {
	if req.Name != nil || req.Color != nil || req.Timezone != nil {
		return joinResult{}, invalid("a re-pair takes only a code and a user")
	}
	code := deref(req.Code)
	if auth.NormalizeInviteCode(code) == "" {
		if code == "" {
			return joinResult{}, invalid("an invite code is required")
		}
		return joinResult{}, errBadCode
	}
	var out joinResult
	err := s.db.WithTx(ctx, func(tx pgx.Tx) error {
		if err := spendCode(ctx, tx, code); err != nil {
			return err
		}
		user, err := db.GetUser(ctx, tx, *req.UserID)
		if errors.Is(err, db.ErrNotFound) {
			return newErr(http.StatusNotFound, codeNotFound, "no such user")
		}
		if err != nil {
			return err
		}
		if err := db.DeleteUserDevices(ctx, tx, user.ID); err != nil {
			return err
		}
		out.user = user
		out.token, err = issueDevice(ctx, tx, user.ID)
		return err
	})
	return out, err
}

// issueDevice registers a new install and returns its plaintext token, shown once.
func issueDevice(ctx context.Context, tx pgx.Tx, userID int64) (string, error) {
	token, hash, err := auth.NewToken()
	if err != nil {
		return "", err
	}
	if _, err := db.CreateDevice(ctx, tx, userID, hash, ""); err != nil {
		return "", err
	}
	return token, nil
}

type checkInviteRequest struct {
	Code string `json:"code"`
}

type userSummary struct {
	ID    int64  `json:"id"`
	Name  string `json:"name"`
	Color string `json:"color"`
}

// handleCheckInvite validates a code without spending it, so the app can offer the re-pair
// chips. Only a valid code reveals who is on the server.
func (s *Server) handleCheckInvite(w http.ResponseWriter, r *http.Request) {
	var req checkInviteRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	ctx := r.Context()
	valid := auth.NormalizeInviteCode(req.Code) != ""
	if valid {
		err := db.CheckInvite(ctx, s.db.Pool, auth.HashInviteCode(req.Code))
		if errors.Is(err, db.ErrInviteInvalid) {
			valid = false
		} else if err != nil {
			fail(w, r, err)
			return
		}
	}
	if !valid {
		if err := db.RecordInviteMiss(ctx, s.db.Pool); err != nil {
			fail(w, r, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"valid": false, "users": []userSummary{}, "canJoinNew": false})
		return
	}

	users, err := db.ListUsers(ctx, s.db.Pool)
	if err != nil {
		fail(w, r, err)
		return
	}
	summaries := make([]userSummary, 0, len(users))
	for _, u := range users {
		summaries = append(summaries, userSummary{ID: u.ID, Name: u.Name, Color: u.Color})
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"valid":      true,
		"users":      summaries,
		"canJoinNew": len(users) < s.cfg.MaxUsers,
	})
}

// handleCreateInvite mints a code for the admin to hand over.
func (s *Server) handleCreateInvite(w http.ResponseWriter, r *http.Request) {
	adminID := callerFrom(r).user.ID
	code, expiresAt, err := auth.IssueInvite(r.Context(), s.db.Pool, &adminID)
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"code": code, "expiresAt": wireTime(expiresAt)})
}

// handleDeleteDevice signs out the calling install.
func (s *Server) handleDeleteDevice(w http.ResponseWriter, r *http.Request) {
	if err := db.DeleteDevice(r.Context(), s.db.Pool, callerFrom(r).deviceID); err != nil && !errors.Is(err, db.ErrNotFound) {
		fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
