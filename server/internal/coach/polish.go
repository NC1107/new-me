package coach

import (
	"context"
	"errors"
	"fmt"
	"log"
	"regexp"
	"strings"
	"time"
	"unicode"

	"github.com/nc1107/new-me/server/internal/anthropic"
	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/readiness"
	"github.com/nc1107/new-me/server/internal/score"
)

const (
	polishTimeout = 8 * time.Second
	maxPolishLen  = 600
)

const polishSystem = `You reword a daily plan for a personal habit app. You are given facts about one person's day.
Write 2 to 4 short, friendly sentences addressed to the person as "you".
Use only the facts given. Do not add numbers, times, advice, medical claims or any other fact that is not in the list.
Plain text only: no lists, no headings, no emoji.`

// Polisher words the plan summary with Claude, at most once per person and day, and falls back
// to the deterministic summary whenever the key is missing, the call fails or the text adds a
// number the facts did not contain.
type Polisher struct {
	DB     *db.DB
	Client *anthropic.Client
}

// Summary returns the polished text for the day when one exists and still matches the plan's
// done and open quests, claiming and making the day's single call if nobody has yet.
func (p *Polisher) Summary(ctx context.Context, user db.User, date score.Date, day Day) string {
	if p == nil || p.Client == nil {
		return day.Plan.Summary
	}
	key := factsKey(day)
	row, err := db.GetPlanPolish(ctx, p.DB.Pool, user.ID, date)
	switch {
	case err == nil:
		if row.Text != nil && row.FactsKey == key {
			return *row.Text
		}
		return day.Plan.Summary
	case !errors.Is(err, db.ErrNotFound):
		log.Printf("[NEWME] plan polish read for user %d: %v", user.ID, err)
		return day.Plan.Summary
	}
	claimed, err := db.ClaimPlanPolish(ctx, p.DB.Pool, user.ID, date, key)
	if err != nil || !claimed {
		return day.Plan.Summary
	}
	callCtx, cancel := context.WithTimeout(ctx, polishTimeout)
	defer cancel()
	facts := factsText(day)
	text, err := p.Client.Text(callCtx, anthropic.Request{
		System: polishSystem, MaxTokens: 300, User: []anthropic.Block{{Text: facts}}})
	if err != nil {
		log.Printf("[NEWME] plan polish for user %d: %v", user.ID, err)
		return day.Plan.Summary
	}
	if !acceptable(text, facts) {
		log.Printf("[NEWME] plan polish for user %d rejected: adds facts or is malformed", user.ID)
		return day.Plan.Summary
	}
	if err := db.SavePlanPolish(ctx, p.DB.Pool, user.ID, date, text); err != nil {
		log.Printf("[NEWME] plan polish save for user %d: %v", user.ID, err)
	}
	return text
}

// factsKey fingerprints which quests are done and open, so wording written for one state is not
// shown once the state has moved on.
func factsKey(day Day) string {
	var done, open []string
	for _, q := range day.Quests {
		if q.Done {
			done = append(done, q.Key)
		} else {
			open = append(open, q.Key)
		}
	}
	return "done=" + strings.Join(done, ",") + ";open=" + strings.Join(open, ",")
}

func factsText(day Day) string {
	var sb strings.Builder
	if r := day.Readiness; r != nil {
		fmt.Fprintf(&sb, "Readiness today: %s.\n", readinessWords(r.Level))
		for _, reason := range r.Reasons {
			if reason.Kind != readiness.KindBasis {
				fmt.Fprintf(&sb, "- %s\n", reason.Text)
			}
		}
	}
	sb.WriteString("Plan:\n")
	for _, it := range day.Plan.Items {
		fmt.Fprintf(&sb, "- %s\n", it.Text)
	}
	fmt.Fprintf(&sb, "Summary: %s\n", day.Plan.Summary)
	return sb.String()
}

// ReadinessTitle is the short headline of a level, for the morning push and the card.
func ReadinessTitle(level string) string {
	switch level {
	case readiness.LevelReady:
		return "You're ready today"
	case readiness.LevelEasy:
		return "Take it easy today"
	}
	return "Today's plan"
}

func readinessWords(level string) string {
	switch level {
	case readiness.LevelReady:
		return "ready"
	case readiness.LevelEasy:
		return "take it easy"
	}
	return "normal"
}

var digitRun = regexp.MustCompile(`\d+`)

// acceptable guards the wording: plain, short, and without any number the facts lack.
func acceptable(text, facts string) bool {
	if text == "" || len([]rune(text)) > maxPolishLen || strings.ContainsFunc(text, func(r rune) bool {
		return unicode.IsControl(r) && r != '\n'
	}) {
		return false
	}
	known := map[string]bool{}
	for _, n := range digitRun.FindAllString(facts, -1) {
		known[n] = true
	}
	for _, n := range digitRun.FindAllString(text, -1) {
		if !known[n] {
			return false
		}
	}
	return true
}
