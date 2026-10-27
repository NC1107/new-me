package api

import (
	"context"
	"errors"
	"net/http"
	"sync"
	"time"

	"github.com/nc1107/new-me/server/internal/abs"
	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/score"
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

// syncThrottle is the shortest gap between two syncs a person can trigger by hand.
const syncThrottle = time.Minute

var errABSNotLinked = newErr(http.StatusNotFound, codeABSNotLinked, "Audiobookshelf is not linked")

// absSyncJSON is the answer of a manual sync: the account state plus today's listening.
type absSyncJSON struct {
	Linked       bool    `json:"linked"`
	Username     *string `json:"username"`
	SyncedAt     *string `json:"syncedAt"`
	LastError    *string `json:"lastError"`
	MinutesToday int     `json:"minutesToday"`
}

// throttle remembers when each person last triggered a manual sync.
type throttle struct {
	mu   sync.Mutex
	last map[int64]time.Time
}

// try reports whether the person may sync now, and records the attempt when they may.
func (t *throttle) try(userID int64, now time.Time) bool {
	t.mu.Lock()
	defer t.mu.Unlock()
	if last, ok := t.last[userID]; ok && now.Sub(last) < syncThrottle {
		return false
	}
	if t.last == nil {
		t.last = map[int64]time.Time{}
	}
	t.last[userID] = now
	return true
}

// handleSyncAudiobookshelf reads the caller's listening now, so opening the app shows what was
// just heard. Within a minute of the previous sync it answers with the stored state instead of
// asking Audiobookshelf again.
func (s *Server) handleSyncAudiobookshelf(w http.ResponseWriter, r *http.Request) {
	if s.listen == nil {
		fail(w, r, errABSDisabled)
		return
	}
	c := callerFrom(r)
	ctx := r.Context()
	if _, err := db.GetABSAccount(ctx, s.db.Pool, c.user.ID); errors.Is(err, db.ErrNotFound) {
		fail(w, r, errABSNotLinked)
		return
	} else if err != nil {
		fail(w, r, err)
		return
	}
	if s.absSync.try(c.user.ID, s.now()) {
		// A failed poll is recorded on the account and reported below as lastError.
		if err := s.listen.SyncUser(ctx, c.user.ID); err != nil && ctx.Err() != nil {
			fail(w, r, ctx.Err())
			return
		}
	}
	acct, err := db.GetABSAccount(ctx, s.db.Pool, c.user.ID)
	if errors.Is(err, db.ErrNotFound) {
		fail(w, r, errABSNotLinked)
		return
	}
	if err != nil {
		fail(w, r, err)
		return
	}
	minutes, err := db.ListeningMinutes(ctx, s.db.Pool, c.user.ID, score.LocalToday(s.now(), c.loc))
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, absSyncJSON{
		Linked: true, Username: &acct.Username, SyncedAt: wireTimePtr(acct.SyncedAt),
		LastError: acct.LastError, MinutesToday: minutes,
	})
}
