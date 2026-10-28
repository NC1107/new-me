package nudge

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/push"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/together"
)

// runPartner sends the person at most one partner nudge about the partner. Everything cheap is
// checked first (switches, quiet hours, the day's budget), so a person with nothing due costs a
// few queries. The partner's stored day is read, never rescored, so a pass writes nothing.
func (s *Service) runPartner(ctx context.Context, u, partner db.User, now time.Time) error {
	prefs := PartnerPrefs{Cover: u.Notify.Cover, Nudges: u.Notify.PartnerNudges}
	if !prefs.Cover && !prefs.Nudges {
		return nil
	}
	loc, err := u.Location()
	if err != nil {
		return err
	}
	today := score.LocalToday(now, loc)
	if today.Before(u.JoinedOn) || s.Together.Held(u, together.EventPartnerCheer) {
		return nil
	}
	room, err := s.Together.PartnerRoom(ctx, u.ID, today)
	if err != nil || !room {
		return err
	}
	facts, err := s.partnerFacts(ctx, u, partner, prefs, loc, today, now)
	if err != nil {
		return err
	}
	n, ok := DecidePartner(facts)
	if !ok {
		return nil
	}
	body := s.Polisher.Vary(ctx, n.Body, together.WordsOK)
	_, err = s.Together.SendPartnerNudge(ctx, u, today, n.Kind,
		push.Message{Kind: n.Kind, Title: n.Title, Body: body})
	return err
}

func (s *Service) partnerFacts(ctx context.Context, u, partner db.User, prefs PartnerPrefs, loc *time.Location,
	today score.Date, now time.Time) (PartnerFacts, error) {
	f := PartnerFacts{Now: now.In(loc), Prefs: prefs, PartnerName: partner.Name}
	var err error
	if prefs.Cover {
		if f.Freezes, f.CoverOpen, err = s.coverChance(ctx, u, partner, now); err != nil {
			return f, err
		}
	}
	if !prefs.Nudges {
		return f, nil
	}
	if f.Hard, f.Cheered, err = s.partnerHardQuest(ctx, u, partner, now); err != nil {
		return f, err
	}
	f.Challenge, err = s.challengeStanding(ctx, u, today)
	return f, err
}

// coverChance mirrors the conditions under which POST /streak/cover accepts: the partner's
// yesterday is still open, has not counted and is not away or frozen, the partner has no freeze
// of their own, and this person holds one. It returns how many freezes this person holds.
func (s *Service) coverChance(ctx context.Context, u, partner db.User, now time.Time) (freezes int, ok bool, err error) {
	ploc, err := partner.Location()
	if err != nil {
		return 0, false, err
	}
	date := score.LocalToday(now, ploc).AddDays(-1)
	if score.DateAllowed(date, now, ploc) != score.DateYesterday || date.Before(partner.JoinedOn) {
		return 0, false, nil
	}
	theirs, err := engine.StreakFor(ctx, s.DB.Pool, partner, now, ploc)
	if err != nil {
		return 0, false, err
	}
	o := theirs.Outcome(date)
	if o.Counted || o.Reason == score.ReasonCover || o.Status == score.StatusAway || o.Status == score.StatusFrozen ||
		theirs.Freezes.Held > 0 {
		return 0, false, nil
	}
	loc, err := u.Location()
	if err != nil {
		return 0, false, err
	}
	mine, err := engine.StreakFor(ctx, s.DB.Pool, u, now, loc)
	if err != nil {
		return 0, false, err
	}
	return mine.Freezes.Held, mine.Freezes.Held > 0, nil
}

// partnerHardQuest finds a hard quest the partner finished on their own today, read from the day
// score stored when they last logged, and whether this person has already cheered them on their
// own day.
func (s *Service) partnerHardQuest(ctx context.Context, u, partner db.User, now time.Time) (*HardQuest, bool, error) {
	ploc, err := partner.Location()
	if err != nil {
		return nil, false, err
	}
	ptoday := score.LocalToday(now, ploc)
	row, err := db.GetDayScore(ctx, s.DB.Pool, partner.ID, ptoday)
	if errors.Is(err, db.ErrNotFound) {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, err
	}
	var quests []score.QuestScore
	if err := json.Unmarshal(row.Detail, &quests); err != nil {
		return nil, false, err
	}
	var hard *HardQuest
	for _, q := range quests {
		if q.Complete && q.Points >= HardQuestPoints {
			hard = &HardQuest{Key: q.Key, Actual: q.Actual}
			break
		}
	}
	if hard == nil {
		return nil, false, nil
	}
	loc, err := u.Location()
	if err != nil {
		return nil, false, err
	}
	cheered, err := db.CheeredToday(ctx, s.DB.Pool, u.ID, partner.ID, score.LocalToday(now, loc))
	return hard, cheered, err
}

// challengeStanding is the person's own progress on their share of this week's challenge.
func (s *Service) challengeStanding(ctx context.Context, u db.User, today score.Date) (*ChallengeFacts, error) {
	if today.Weekday() != checkInWeekday {
		return nil, nil
	}
	ch, err := s.Together.EnsureChallenge(ctx, score.WeekStart(today))
	if err != nil || ch.CompletedAt != nil {
		return nil, err
	}
	status, err := s.Together.ChallengeProgress(ctx, ch)
	if err != nil {
		return nil, err
	}
	for _, p := range status.People {
		if p.UserID == u.ID {
			return &ChallengeFacts{Kind: ch.Kind, Progress: p.Progress, Target: p.Target}, nil
		}
	}
	return nil, nil
}
