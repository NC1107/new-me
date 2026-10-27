package api

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/milestone"
	"github.com/nc1107/new-me/server/internal/push"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/together"
)

const (
	codeAwayOverlap = "away_overlap"
	codeCoverClosed = "cover_closed"
	codeNoFreeze    = "no_freeze"
)

type streakJSON struct {
	Current int `json:"current"`
	// RestAvailable and RestUsedOn predate freezes: they say a freeze is ready, and which day
	// of this week was last frozen.
	RestAvailable bool        `json:"restAvailable"`
	RestUsedOn    *score.Date `json:"restUsedOn"`
}

func toStreakJSON(res score.StreakResult, today score.Date) streakJSON {
	out := streakJSON{Current: res.Count, RestAvailable: res.Count > 0 && res.Freezes.Held > 0}
	if used, ok := res.LastFrozenIn(score.WeekStart(today)); ok {
		out.RestUsedOn = &used
	}
	return out
}

type repairJSON struct {
	Date            score.Date `json:"date"`
	Until           string     `json:"until"`
	ProgressPercent int        `json:"progressPercent"`
}

func toRepairJSON(r *engine.Repair, percent int) *repairJSON {
	if r == nil {
		return nil
	}
	return &repairJSON{Date: r.Date, Until: wireTime(r.Until), ProgressPercent: percent}
}

type awaySpanJSON struct {
	ID   int64      `json:"id"`
	From score.Date `json:"from"`
	To   score.Date `json:"to"`
	Note string     `json:"note"`
}

func toAwaySpanJSON(a db.AwaySpan) awaySpanJSON {
	return awaySpanJSON{ID: a.ID, From: a.From, To: a.To, Note: a.Note}
}

// awayJSON is the person's away state: whether today is away, the span covering today, and the
// spans that start later.
type awayJSON struct {
	Today    bool           `json:"today"`
	Current  *awaySpanJSON  `json:"current"`
	Upcoming []awaySpanJSON `json:"upcoming"`
}

func (s *Server) awayFor(ctx context.Context, q db.Querier, userID int64, today score.Date) (awayJSON, error) {
	spans, err := db.AwaySpansFrom(ctx, q, userID, today)
	if err != nil {
		return awayJSON{}, err
	}
	out := awayJSON{Upcoming: []awaySpanJSON{}}
	for _, sp := range spans {
		j := toAwaySpanJSON(sp)
		if sp.Contains(today) {
			out.Today, out.Current = true, &j
		} else {
			out.Upcoming = append(out.Upcoming, j)
		}
	}
	return out, nil
}

type createAwayRequest struct {
	From string `json:"from"`
	To   string `json:"to"`
	Note string `json:"note"`
}

// handleCreateAway marks a span of days as away: it starts today or up to 14 days ahead and lasts
// at most 14 days. It answers the span and the person's away state.
func (s *Server) handleCreateAway(w http.ResponseWriter, r *http.Request) {
	var req createAwayRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	c := callerFrom(r)
	today := score.LocalToday(s.now(), c.loc)
	from, err := score.ParseDate(req.From)
	if err != nil {
		fail(w, r, invalid("from must be YYYY-MM-DD"))
		return
	}
	to, err := score.ParseDate(req.To)
	if err != nil {
		fail(w, r, invalid("to must be YYYY-MM-DD"))
		return
	}
	note := strings.TrimSpace(req.Note)
	switch {
	case from.Before(today) || from.After(today.AddDays(db.MaxAwayDays)):
		fail(w, r, invalid("from must be between today and 14 days ahead"))
		return
	case to.Before(from) || to.After(from.AddDays(db.MaxAwayDays-1)):
		fail(w, r, invalid("an away span is 1 to 14 days"))
		return
	case utf8.RuneCountInString(note) > 200 || hasControlChars(note):
		fail(w, r, invalid("note must be at most 200 characters without control characters"))
		return
	}

	ctx := r.Context()
	var span db.AwaySpan
	txErr := s.db.WithTx(ctx, func(tx pgx.Tx) error {
		if err := db.LockUserRows(ctx, tx, c.user.ID); err != nil {
			return err
		}
		overlap, err := db.OverlappingAway(ctx, tx, c.user.ID, from, to)
		if err != nil {
			return err
		}
		if overlap {
			return newErr(http.StatusConflict, codeAwayOverlap, "you already have an away span on some of those days")
		}
		span, err = db.CreateAway(ctx, tx, c.user.ID, from, to, note)
		return err
	})
	if txErr != nil {
		fail(w, r, txErr)
		return
	}
	away, err2 := s.awayFor(ctx, s.db.Pool, c.user.ID, today)
	if err2 != nil {
		fail(w, r, err2)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"away": toAwaySpanJSON(span), "state": away})
}

// handleDeleteAway removes one of the caller's spans. Days that already finalized as away keep
// that outcome.
func (s *Server) handleDeleteAway(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id < 1 {
		fail(w, r, newErr(http.StatusNotFound, codeNotFound, "no such away span"))
		return
	}
	c := callerFrom(r)
	if _, err := db.DeleteAway(r.Context(), s.db.Pool, c.user.ID, id); err != nil {
		if errors.Is(err, db.ErrNotFound) {
			fail(w, r, newErr(http.StatusNotFound, codeNotFound, "no such away span"))
			return
		}
		fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type coverRequest struct {
	Date string `json:"date"`
}

// coverOpen is whether the partner's date still accepts a cover: it is their yesterday and
// their grace window, which ends at 10:00 their next day, has not closed.
func coverOpen(date score.Date, s *Server, partner db.User) bool {
	loc, err := partner.Location()
	if err != nil {
		return false
	}
	return score.DateAllowed(date, s.now(), loc) == score.DateYesterday
}

// handleCoverStreak spends one of the caller's freezes on the partner's missed day. It is open
// from the partner's yesterday until 10:00 their next day, while the partner has no freeze of
// their own to use and the day has not counted.
func (s *Server) handleCoverStreak(w http.ResponseWriter, r *http.Request) {
	var req coverRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	date, err := score.ParseDate(req.Date)
	if err != nil {
		fail(w, r, invalid("date must be YYYY-MM-DD"))
		return
	}
	c := callerFrom(r)
	ctx := r.Context()
	users, err := db.ListUsers(ctx, s.db.Pool)
	if err != nil {
		fail(w, r, err)
		return
	}
	var partner *db.User
	for i := range users {
		if users[i].ID != c.user.ID {
			partner = &users[i]
		}
	}
	if partner == nil {
		fail(w, r, newErr(http.StatusNotFound, codeNotFound, "there is nobody to cover"))
		return
	}

	var freezes score.Freezes
	txErr := s.db.WithTx(ctx, func(tx pgx.Tx) error {
		// One lock for the pair, taken in id order, so two covers cannot spend the same freeze.
		for _, id := range []int64{min(c.user.ID, partner.ID), max(c.user.ID, partner.ID)} {
			if err := db.LockUserRows(ctx, tx, id); err != nil {
				return err
			}
		}
		now := s.now()
		if !coverOpen(date, s, *partner) || date.Before(partner.JoinedOn) {
			return newErr(http.StatusUnprocessableEntity, codeCoverClosed, "that day can no longer be covered")
		}
		ploc, err := partner.Location()
		if err != nil {
			return err
		}
		theirs, err := engine.StreakFor(ctx, tx, *partner, now, ploc)
		if err != nil {
			return err
		}
		if o := theirs.Outcome(date); o.Reason == score.ReasonCover {
			return newErr(http.StatusConflict, codeCoverClosed, "that day is already covered")
		} else if o.Counted || o.Status == score.StatusAway || o.Status == score.StatusFrozen {
			return newErr(http.StatusUnprocessableEntity, codeCoverClosed, "that day does not need covering")
		}
		if theirs.Freezes.Held > 0 {
			return newErr(http.StatusUnprocessableEntity, codeCoverClosed, "they still have a freeze of their own")
		}
		mine, err := engine.StreakFor(ctx, tx, c.user, now, c.loc)
		if err != nil {
			return err
		}
		if mine.Freezes.Held < 1 {
			return newErr(http.StatusUnprocessableEntity, codeNoFreeze, "you have no freeze to spend")
		}
		created, err := db.CreateCover(ctx, tx, partner.ID, c.user.ID, date)
		if err != nil {
			return err
		}
		if !created {
			return newErr(http.StatusConflict, codeCoverClosed, "that day is already covered")
		}
		freezes = score.Freezes{Held: mine.Freezes.Held - 1, EarnedTowardNext: mine.Freezes.EarnedTowardNext}
		return nil
	})
	if txErr != nil {
		fail(w, r, txErr)
		return
	}
	s.together.Notify(*partner, push.Message{Kind: together.EventCover,
		Title: c.user.Name + " covered your day", Body: "A freeze kept your streak going."})
	writeJSON(w, http.StatusCreated, map[string]any{"covered": partner.ID, "date": date, "freezes": freezes})
}

type milestoneJSON struct {
	ID         int64      `json:"id"`
	Kind       string     `json:"kind"`
	Value      int        `json:"value"`
	Shared     bool       `json:"shared"`
	Title      string     `json:"title"`
	AchievedOn score.Date `json:"achievedOn"`
}

func toMilestoneJSON(m db.Milestone) milestoneJSON {
	return milestoneJSON{ID: m.ID, Kind: m.Kind, Value: m.Value, Shared: m.UserID == nil,
		Title: milestone.Title(m), AchievedOn: m.AchievedOn}
}

func toMilestonesJSON(ms []db.Milestone) []milestoneJSON {
	out := make([]milestoneJSON, len(ms))
	for i, m := range ms {
		out[i] = toMilestoneJSON(m)
	}
	return out
}

// handleListMilestones lists the caller's milestones and the couple's, newest first.
func (s *Server) handleListMilestones(w http.ResponseWriter, r *http.Request) {
	s.milestones.RunQuietly(r.Context())
	ms, err := db.ListMilestones(r.Context(), s.db.Pool, callerFrom(r).user.ID)
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"milestones": toMilestonesJSON(ms)})
}
