package together

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/push"
	"github.com/nc1107/new-me/server/internal/score"
)

const (
	// PartnerClaimPrefix starts the notice_log kind of every partner nudge, which is how their
	// separate daily budget is counted.
	PartnerClaimPrefix = "partner_"
	// PartnerBudget is how many partner nudges one person gets a day.
	PartnerBudget = 1
	// MaxWordsLen is the longest body of a partner nudge, in characters.
	MaxWordsLen = 90

	rewardClaimPrefix = PartnerClaimPrefix + "reward_"
)

// RewardThresholds are the percentages of a reward at which the pair is told about progress;
// 100 is the reward being ready.
var RewardThresholds = []int{50, 90, 100}

// WordsOK reports whether a partner nudge body keeps to the wording rules: not empty, under 90
// characters, plain text without emoji or the long dash. Figures are not checked here; they come
// from the templates, which only format computed values.
func WordsOK(s string) bool {
	if s == "" || utf8.RuneCountInString(s) > MaxWordsLen || strings.ContainsRune(s, '—') {
		return false
	}
	for _, r := range s {
		if unicode.IsControl(r) || unicode.Is(unicode.So, r) || unicode.Is(unicode.Sk, r) ||
			r >= 0x1F000 || (r >= 0x2600 && r <= 0x27BF) || r == 0xFE0F || r == 0x200D {
			return false
		}
	}
	return true
}

// Fit returns the text when it keeps to the wording rules and otherwise the fallback, which the
// templates keep short enough to always pass.
func Fit(text, fallback string) string {
	if WordsOK(text) {
		return text
	}
	return fallback
}

// RewardMilestone is the highest threshold the percentage has reached, or 0 below the first.
func RewardMilestone(percent int) int {
	reached := 0
	for _, t := range RewardThresholds {
		if percent >= t {
			reached = t
		}
	}
	return reached
}

// RewardWords words a reward's progress at a threshold.
func RewardWords(name string, threshold int) string {
	name = strings.TrimSpace(name)
	var text, fallback string
	switch {
	case threshold >= 100:
		text, fallback = name+" is ready to enjoy.", "Your reward is ready to enjoy."
	default:
		text = fmt.Sprintf("%s is %d%% of the way there.", name, threshold)
		fallback = fmt.Sprintf("Your reward is %d%% of the way there.", threshold)
	}
	return Fit(text, fallback)
}

// PartnerRoom reports whether the person still has a partner nudge to spare on their local date.
func (s *Service) PartnerRoom(ctx context.Context, userID int64, date score.Date) (bool, error) {
	n, err := db.CountNoticesWithPrefix(ctx, s.DB.Pool, userID, date, PartnerClaimPrefix)
	return n < PartnerBudget, err
}

// SendPartnerNudge sends one partner nudge within the person's separate daily budget, claiming
// it in notice_log under a kind that starts with PartnerClaimPrefix. It reports whether the push
// was queued. A nudge held by quiet hours, an off switch or a spent budget claims nothing.
func (s *Service) SendPartnerNudge(ctx context.Context, to db.User, date score.Date, claimKind string, m push.Message) (bool, error) {
	if !strings.HasPrefix(claimKind, PartnerClaimPrefix) {
		return false, fmt.Errorf("partner nudge claim %q lacks the %q prefix", claimKind, PartnerClaimPrefix)
	}
	room, err := s.PartnerRoom(ctx, to.ID, date)
	if err != nil || !room {
		return false, err
	}
	d, err := s.SendClaimed(ctx, Claim{Kind: claimKind, UserID: to.ID, Date: date}, to, m)
	return d == Queued, err
}

// NotifyRewardProgress is the hook for the reward code: call it with the active reward's id,
// name and percent whenever progress may have moved. Each person is told once per reward at
// each of RewardThresholds, within their partner budget, so a call that finds nothing new, a
// spent budget or a quiet moment does nothing and a later call tries again.
func (s *Service) NotifyRewardProgress(ctx context.Context, rewardID int64, name string, percent int) error {
	threshold := RewardMilestone(percent)
	if threshold == 0 || s.Notifier == nil {
		return nil
	}
	users, err := db.ListUsers(ctx, s.DB.Pool)
	if err != nil {
		return err
	}
	now := s.Now()
	var errs []error
	for _, u := range users {
		loc, err := u.Location()
		if err != nil {
			errs = append(errs, err)
			continue
		}
		told, err := s.rewardToldAtOrAbove(ctx, u.ID, rewardID, threshold)
		if err != nil {
			errs = append(errs, err)
			continue
		}
		if told {
			continue
		}
		_, err = s.SendPartnerNudge(ctx, u, score.LocalToday(now, loc), rewardClaimKind(rewardID, threshold),
			push.Message{Kind: EventRewardProgress, Title: "Shared reward", Body: RewardWords(name, threshold)})
		if err != nil {
			errs = append(errs, err)
		}
	}
	return errors.Join(errs...)
}

func rewardClaimKind(rewardID int64, threshold int) string {
	return fmt.Sprintf("%s%d_%d", rewardClaimPrefix, rewardID, threshold)
}

func (s *Service) rewardToldAtOrAbove(ctx context.Context, userID, rewardID int64, threshold int) (bool, error) {
	for _, t := range RewardThresholds {
		if t < threshold {
			continue
		}
		ok, err := db.NoticeEverSent(ctx, s.DB.Pool, userID, rewardClaimKind(rewardID, t))
		if err != nil || ok {
			return ok, err
		}
	}
	return false, nil
}
