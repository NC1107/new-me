package api

import (
	"context"
	"errors"
	"net/http"

	"github.com/nc1107/new-me/server/internal/abs"
	"github.com/nc1107/new-me/server/internal/db"
)

// Bounds of the sign-in fields, generous enough for any real Audiobookshelf account.
const (
	maxABSUsername = 200
	maxABSPassword = 1000
)

// absJSON is the account's Audiobookshelf state. It is null on /api/me when the feature is
// off, and linked is false while nobody has signed in.
type absJSON struct {
	Linked   bool    `json:"linked"`
	Username *string `json:"username"`
	SyncedAt *string `json:"syncedAt"`
	// LastError is auth_failed when the person must sign in again, unreachable when the last
	// poll could not reach Audiobookshelf, and null when the last poll worked.
	LastError *string `json:"lastError"`
}

func toABSJSON(a db.ABSAccount) *absJSON {
	return &absJSON{Linked: true, Username: &a.Username, SyncedAt: wireTimePtr(a.SyncedAt), LastError: a.LastError}
}

// absState is what /api/me reports: nil when the feature is off.
func (s *Server) absState(ctx context.Context, q db.Querier, userID int64) (*absJSON, error) {
	if s.listen == nil {
		return nil, nil
	}
	a, err := db.GetABSAccount(ctx, q, userID)
	if errors.Is(err, db.ErrNotFound) {
		return &absJSON{}, nil
	}
	if err != nil {
		return nil, err
	}
	return toABSJSON(a), nil
}

var errABSDisabled = newErr(http.StatusNotFound, codeABSDisabled, "Audiobookshelf is not set up on this server")

type linkABSRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

// handleLinkAudiobookshelf signs in to Audiobookshelf once and keeps only the session tokens.
func (s *Server) handleLinkAudiobookshelf(w http.ResponseWriter, r *http.Request) {
	if s.listen == nil {
		fail(w, r, errABSDisabled)
		return
	}
	var req linkABSRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	if n := len([]rune(req.Username)); n < 1 || n > maxABSUsername || hasControlChars(req.Username) {
		fail(w, r, invalid("username must be 1 to 200 characters without control characters"))
		return
	}
	if n := len([]rune(req.Password)); n < 1 || n > maxABSPassword {
		fail(w, r, invalid("password must be 1 to 1000 characters"))
		return
	}

	ctx := r.Context()
	sess, err := s.listen.ABS.Login(ctx, req.Username, req.Password)
	switch {
	case errors.Is(err, abs.ErrAuth):
		fail(w, r, newErr(http.StatusUnprocessableEntity, codeABSLoginFailed,
			"Audiobookshelf did not accept that username and password"))
		return
	case err != nil:
		fail(w, r, newErr(http.StatusBadGateway, codeABSUnavailable, "could not reach Audiobookshelf, try again later"))
		return
	}
	if sess.Username == "" {
		sess.Username = req.Username
	}
	acct, err := s.listen.Link(ctx, callerFrom(r).user.ID, sess)
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, toABSJSON(acct))
}

// handleUnlinkAudiobookshelf forgets the stored session. It is idempotent.
func (s *Server) handleUnlinkAudiobookshelf(w http.ResponseWriter, r *http.Request) {
	if s.listen == nil {
		fail(w, r, errABSDisabled)
		return
	}
	c := callerFrom(r)
	if _, err := s.listen.Unlink(r.Context(), c.user, c.loc); err != nil {
		fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
