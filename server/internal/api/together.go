package api

import (
	"context"
	"errors"
	"net/http"
	"regexp"
	"slices"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/push"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/together"
)

const (
	codeRewardActive     = "reward_active"
	codeRewardNotReached = "reward_not_reached"

	maxRewardTarget = 100000
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
	// Missed is true once the week ended with the challenge unfinished. Reason is why this
	// kind was picked, empty for challenges from before v13.
	Missed bool   `json:"missed"`
	Reason string `json:"reason"`
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
	return s.toChallengeJSON(ctx, ch)
}

// lastMissedChallenge is the previous week's challenge when it ended unfinished, or nil.
func (s *Server) lastMissedChallenge(ctx context.Context, c caller) (*challengeJSON, error) {
	week := score.WeekStart(score.LocalToday(s.now(), c.loc)).AddDays(-7)
	ch, err := db.GetChallenge(ctx, s.db.Pool, week)
	if errors.Is(err, db.ErrNotFound) || (err == nil && ch.MissedAt == nil) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	out, err := s.toChallengeJSON(ctx, ch)
	return &out, err
}

func (s *Server) toChallengeJSON(ctx context.Context, ch db.Challenge) (challengeJSON, error) {
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
		Done: ch.CompletedAt != nil, EndsOn: ch.EndsOn(), Missed: ch.MissedAt != nil, Reason: ch.PickReason,
		People: people}, nil
}

type rewardJSON struct {
	ID        int64   `json:"id"`
	Name      string  `json:"name"`
	Target    int     `json:"target"`
	Progress  int     `json:"progress"`
	StartedAt string  `json:"startedAt"`
	ReachedAt *string `json:"reachedAt"`
	ClaimedAt *string `json:"claimedAt"`
	CreatedBy *int64  `json:"createdBy"`
}

func toRewardJSON(r db.Reward, total int) rewardJSON {
	progress := together.RewardProgress(total, r.Baseline, r.Target)
	if r.ReachedAt != nil {
		progress = r.Target
	}
	return rewardJSON{ID: r.ID, Name: r.Name, Target: r.Target, Progress: progress,
		StartedAt: wireTime(r.StartedAt), ReachedAt: wireTimePtr(r.ReachedAt), ClaimedAt: wireTimePtr(r.ClaimedAt),
		CreatedBy: r.CreatedBy}
}

// boardReward is the reward the Us screen shows: the one being earned, or else the newest one
// that was reached and not yet enjoyed. It is nil when there is neither.
func (s *Server) boardReward(ctx context.Context) (*rewardJSON, error) {
	r, err := db.ActiveReward(ctx, s.db.Pool)
	if errors.Is(err, db.ErrNotFound) {
		r, err = db.LatestUnclaimedReward(ctx, s.db.Pool)
	}
	if errors.Is(err, db.ErrNotFound) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	total, err := s.together.RewardTotals(ctx)
	if err != nil {
		return nil, err
	}
	out := toRewardJSON(r, total)
	return &out, nil
}

// handleListRewards answers the reward being earned (null when none) and the history of
// reached ones, newest first.
func (s *Server) handleListRewards(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	s.together.SettleQuietly(ctx)
	total, err := s.together.RewardTotals(ctx)
	if err != nil {
		fail(w, r, err)
		return
	}
	var active *rewardJSON
	switch a, err := db.ActiveReward(ctx, s.db.Pool); {
	case err == nil:
		j := toRewardJSON(a, total)
		active = &j
	case !errors.Is(err, db.ErrNotFound):
		fail(w, r, err)
		return
	}
	reached, err := db.ListReachedRewards(ctx, s.db.Pool)
	if err != nil {
		fail(w, r, err)
		return
	}
	history := make([]rewardJSON, len(reached))
	for i, rw := range reached {
		history[i] = toRewardJSON(rw, total)
	}
	writeJSON(w, http.StatusOK, map[string]any{"reward": active, "history": history})
}

// handleCreateReward starts the next reward. Only one may be active; a second answers 409.
func (s *Server) handleCreateReward(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Name   string `json:"name"`
		Target int    `json:"target"`
	}
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	name, herr := cleanName(req.Name)
	if herr != nil {
		fail(w, r, invalid("name must be 1 to 40 characters without control characters"))
		return
	}
	if req.Target < 1 || req.Target > maxRewardTarget {
		fail(w, r, invalid("target must be between 1 and 100000"))
		return
	}
	ctx := r.Context()
	// A reward that has just been earned must move to history before the next can start.
	s.together.SettleQuietly(ctx)
	total, err := s.together.RewardTotals(ctx)
	if err != nil {
		fail(w, r, err)
		return
	}
	reward, err := db.CreateReward(ctx, s.db.Pool, name, req.Target, total, callerFrom(r).user.ID)
	if errors.Is(err, db.ErrRewardActive) {
		fail(w, r, newErr(http.StatusConflict, codeRewardActive, "a reward is already being earned"))
		return
	}
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"reward": toRewardJSON(reward, total)})
}

// handleClaimReward marks a reached reward as enjoyed. Claiming again keeps the first time.
func (s *Server) handleClaimReward(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id < 1 {
		fail(w, r, newErr(http.StatusNotFound, codeNotFound, "no such reward"))
		return
	}
	ctx := r.Context()
	s.together.SettleQuietly(ctx)
	existing, err := db.GetReward(ctx, s.db.Pool, id)
	if errors.Is(err, db.ErrNotFound) {
		fail(w, r, newErr(http.StatusNotFound, codeNotFound, "no such reward"))
		return
	}
	if err != nil {
		fail(w, r, err)
		return
	}
	if existing.ReachedAt == nil {
		fail(w, r, newErr(http.StatusConflict, codeRewardNotReached, "that reward has not been reached yet"))
		return
	}
	claimed, err := db.ClaimReward(ctx, s.db.Pool, id)
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"reward": toRewardJSON(claimed, claimed.Target)})
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
