package api

import (
	"context"
	"errors"
	"net/http"
	"regexp"
	"slices"
	"time"

	"github.com/go-chi/chi/v5/middleware"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/push"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/together"
)

const (
	// settleTimeout bounds the work after a write, which the caller is already waiting on.
	settleTimeout = 10 * time.Second
)

// settleAfter runs the shared bookkeeping once a write has succeeded: it completes a challenge
// or reward the write finished and announces a partner whose day just counted. A failure
// there is logged and never changes the response.
func (s *Server) settleAfter(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)
		next.ServeHTTP(ww, r)
		if ww.Status() >= http.StatusMultipleChoices {
			return
		}
		ctx, cancel := context.WithTimeout(context.WithoutCancel(r.Context()), settleTimeout)
		defer cancel()
		s.together.SettleQuietly(ctx)
		s.milestones.RunQuietly(ctx)
	})
}

type cheerJSON struct {
	From     int64  `json:"from"`
	FromName string `json:"fromName"`
	Kind     string `json:"kind"`
	At       string `json:"at"`
}

func toCheerJSON(c db.Cheer) cheerJSON {
	return cheerJSON{From: c.From, FromName: c.FromName, Kind: c.Kind, At: wireTime(c.At)}
}

// cheersToday are the cheers the caller received on their own local day.
func (s *Server) cheersToday(ctx context.Context, c caller, today score.Date) ([]cheerJSON, error) {
	t := today.Time()
	start := time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, c.loc)
	cheers, err := db.CheersReceived(ctx, s.db.Pool, c.user.ID, start, start.AddDate(0, 0, 1))
	if err != nil {
		return nil, err
	}
	out := make([]cheerJSON, len(cheers))
	for i, ch := range cheers {
		out[i] = toCheerJSON(ch)
	}
	return out, nil
}

// handleCreateCheer sends a reaction to the partner. A kind may be sent once per recipient per
// sender-local day: the first answers 201 and notifies, a repeat answers 200 with the stored
// cheer and does nothing, so a retried tap is harmless.
func (s *Server) handleCreateCheer(w http.ResponseWriter, r *http.Request) {
	var req struct {
		To   int64  `json:"to"`
		Kind string `json:"kind"`
	}
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	if !slices.Contains(db.CheerKinds, req.Kind) {
		fail(w, r, invalid("kind must be clap, fire, flex or heart"))
		return
	}
	c := callerFrom(r)
	if req.To == c.user.ID {
		fail(w, r, invalid("you cannot cheer yourself"))
		return
	}
	ctx := r.Context()
	to, err := db.GetUser(ctx, s.db.Pool, req.To)
	if errors.Is(err, db.ErrNotFound) {
		fail(w, r, newErr(http.StatusNotFound, codeNotFound, "no such person"))
		return
	}
	if err != nil {
		fail(w, r, err)
		return
	}
	cheer, created, err := db.InsertCheer(ctx, s.db.Pool, c.user.ID, to.ID, req.Kind, score.LocalToday(s.now(), c.loc), s.now())
	if err != nil {
		fail(w, r, err)
		return
	}
	status := http.StatusOK
	if created {
		status = http.StatusCreated
		s.together.Notify(to, push.Message{Kind: together.EventCheer,
			Title: c.user.Name + " cheered your day", Body: cheerWords[req.Kind]})
	}
	writeJSON(w, status, map[string]any{"cheer": toCheerJSON(cheer), "to": to.ID})
}

var cheerWords = map[string]string{
	"clap": "A round of applause", "fire": "You are on fire", "flex": "Strong work", "heart": "Sending love",
}

type challengeJSON struct {
	Kind  string `json:"kind"`
	Title string `json:"title"`
	// Target is the sum of everyone's share and Progress adds each person's progress capped at
	// their own share. The challenge is done when every person has reached their own share.
	Target   int        `json:"target"`
	Progress int        `json:"progress"`
	Done     bool       `json:"done"`
	EndsOn   score.Date `json:"endsOn"`
	// People holds each person's share and progress.
	People []challengePersonJSON `json:"people"`
}

type challengePersonJSON struct {
	UserID   int64  `json:"userId"`
	Name     string `json:"name"`
	Color    string `json:"color"`
	Target   int    `json:"target"`
	Progress int    `json:"progress"`
	Done     bool   `json:"done"`
}

// challengeFor is the challenge of the week the caller is in, created on first use.
func (s *Server) challengeFor(ctx context.Context, c caller) (challengeJSON, error) {
	week := score.WeekStart(score.LocalToday(s.now(), c.loc))
	ch, err := s.together.EnsureChallenge(ctx, week)
	if err != nil {
		return challengeJSON{}, err
	}
	status, err := s.together.ChallengeProgress(ctx, ch)
	if err != nil {
		return challengeJSON{}, err
	}
	people := make([]challengePersonJSON, len(status.People))
	for i, p := range status.People {
		people[i] = challengePersonJSON{UserID: p.UserID, Name: p.Name, Color: p.Color,
			Target: p.Target, Progress: p.Progress, Done: p.Done()}
	}
	return challengeJSON{Kind: ch.Kind, Title: ch.Title, Target: status.Target, Progress: status.Progress,
		Done: ch.CompletedAt != nil, EndsOn: ch.EndsOn(), People: people}, nil
}

var pushTokenShape = regexp.MustCompile(`^[0-9a-fA-F]{32,200}$`)

// handlePutPushToken registers this install's APNs token. Repeating it is fine.
func (s *Server) handlePutPushToken(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Token string `json:"token"`
	}
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	if !pushTokenShape.MatchString(req.Token) {
		fail(w, r, invalid("token must be the hex device token from APNs"))
		return
	}
	c := callerFrom(r)
	if err := db.UpsertPushToken(r.Context(), s.db.Pool, c.deviceID, c.user.ID, lowerHex(req.Token)); err != nil {
		fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// handleDeletePushToken forgets this install's token, which stops its notifications.
func (s *Server) handleDeletePushToken(w http.ResponseWriter, r *http.Request) {
	if err := db.DeletePushToken(r.Context(), s.db.Pool, callerFrom(r).deviceID); err != nil {
		fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func lowerHex(s string) string {
	b := []byte(s)
	for i, ch := range b {
		if ch >= 'A' && ch <= 'F' {
			b[i] = ch + 'a' - 'A'
		}
	}
	return string(b)
}
