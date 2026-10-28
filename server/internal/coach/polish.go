package coach

import (
	"context"
	"errors"
	"fmt"
	"log"
	"regexp"
	"strings"
	"sync"
	"time"
	"unicode"

	"github.com/nc1107/new-me/server/internal/anthropic"
	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/readiness"
	"github.com/nc1107/new-me/server/internal/score"
)

const (
	polishTimeout = 8 * time.Second
	varyTimeout   = 5 * time.Second
	maxPolishLen  = 600
)

const varySystem = `You reword one short push notification for a personal habit app, so it does not read the same every time.
Keep every number exactly as given. Do not add numbers, names, advice, blame or any other fact.
One plain sentence or two, no emoji, no dashes, under 90 characters. Reply with the text only.`

// Vary rewords a short partner nudge through the same guard as the plan summary: the new text
// must add no number the original lacks, must be a single line and must pass fits, the caller's
// wording rules. Without a key, on any failure and on any rejection the original is returned.
func (p *Polisher) Vary(ctx context.Context, text string, fits func(string) bool) string {
	if p == nil || p.Client == nil {
		return text
	}
	callCtx, cancel := context.WithTimeout(ctx, varyTimeout)
	defer cancel()
	out, err := p.Client.Text(callCtx, anthropic.Request{
		System: varySystem, MaxTokens: 80, User: []anthropic.Block{{Text: text}}})
	if err != nil {
		log.Printf("[NEWME] nudge wording: %v", err)
		return text
	}
	out = strings.TrimSpace(out)
	if strings.ContainsRune(out, '\n') || !acceptable(out, text) || !fits(out) {
		log.Printf("[NEWME] nudge wording rejected: adds facts or breaks the wording rules")
		return text
	}
	return out
}

const polishSystem = `You reword a daily plan for a personal habit app. You are given facts about one person's day.
Write 2 to 4 short, friendly sentences addressed to the person as "you".
Use only the facts given. Do not add numbers, times, advice, medical claims or any other fact that is not in the list.
Plain text only: no lists, no headings, no emoji.`

// polishRetryAfter is how long a failed call keeps the day from being tried again, so a
// provider outage costs one attempt per window and not one per request.
const polishRetryAfter = 10 * time.Minute

// Polisher words the plan summary with Claude, at most one successful call per person and day,
// and falls back to the deterministic summary whenever the key is missing, the call fails or the
// text adds a number the facts did not contain. Reads never wait for Claude: Today shows what is
// stored and asks for the call to happen in the background.
type Polisher struct {
	DB     *db.DB
	Client *anthropic.Client
	// Now is the clock for the retry window; nil means the wall clock.
	Now func() time.Time

	mu       sync.Mutex
	inflight map[string]bool
	failedAt map[string]time.Time
	wg       sync.WaitGroup
}

func (p *Polisher) now() time.Time {
	if p.Now != nil {
		return p.Now()
	}
	return time.Now()
}

// Cached returns the polished text for the day when one exists and still matches the plan's
// done and open quests, and otherwise the deterministic summary. It never calls Claude. The
// second result is true when the day already has a row, so no call is worth asking for.
func (p *Polisher) Cached(ctx context.Context, user db.User, date score.Date, day Day) (string, bool) {
	if p == nil || p.Client == nil {
		return day.Plan.Summary, true
	}
	row, err := db.GetPlanPolish(ctx, p.DB.Pool, user.ID, date)
	switch {
	case err == nil:
		if row.Text != nil && row.FactsKey == factsKey(day) {
			return *row.Text, true
		}
		return day.Plan.Summary, true
	case !errors.Is(err, db.ErrNotFound):
		log.Printf("[NEWME] plan polish read for user %d: %v", user.ID, err)
		return day.Plan.Summary, true
	}
	return day.Plan.Summary, false
}

// Summary returns the polished text, making the day's call now when nobody has yet. It is for
// callers that are already off the request path, such as the scheduler's morning push.
func (p *Polisher) Summary(ctx context.Context, user db.User, date score.Date, day Day) string {
	if text, settled := p.Cached(ctx, user, date, day); settled {
		return text
	}
	if text, ok := p.polish(ctx, user, date, day); ok {
		return text
	}
	return day.Plan.Summary
}

// PolishInBackground makes the day's call on its own goroutine and timeout, so the request that
// noticed the missing wording does not wait for it. A recent failure or a call already running
// for the same day makes it do nothing.
func (p *Polisher) PolishInBackground(user db.User, date score.Date, day Day) {
	if p == nil || p.Client == nil {
		return
	}
	key := fmt.Sprintf("%d|%s|%s", user.ID, date, factsKey(day))
	p.mu.Lock()
	if p.inflight[key] || p.now().Sub(p.failedAt[key]) < polishRetryAfter {
		p.mu.Unlock()
		return
	}
	if p.inflight == nil {
		p.inflight = map[string]bool{}
	}
	p.inflight[key] = true
	p.wg.Add(1)
	p.mu.Unlock()

	go func() {
		defer p.wg.Done()
		defer func() {
			p.mu.Lock()
			delete(p.inflight, key)
			p.mu.Unlock()
		}()
		ctx, cancel := context.WithTimeout(context.Background(), polishTimeout+releaseTimeout)
		defer cancel()
		if _, ok := p.polish(ctx, user, date, day); !ok {
			p.mu.Lock()
			if p.failedAt == nil {
				p.failedAt = map[string]time.Time{}
			}
			p.failedAt[key] = p.now()
			p.mu.Unlock()
		}
	}()
}

// Wait blocks until every background call has finished, for tests and shutdown.
func (p *Polisher) Wait() {
	if p != nil {
		p.wg.Wait()
	}
}

// releaseTimeout bounds giving a claim back after a failed or abandoned call.
const releaseTimeout = 5 * time.Second

// polish claims the day, makes the call and stores the wording. When it produces none the claim
// is released, so the day is not stuck without wording until tomorrow.
func (p *Polisher) polish(ctx context.Context, user db.User, date score.Date, day Day) (string, bool) {
	key := factsKey(day)
	claimed, err := db.ClaimPlanPolish(ctx, p.DB.Pool, user.ID, date, key)
	if err != nil || !claimed {
		return "", false
	}
	saved := false
	defer func() {
		if saved {
			return
		}
		relCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), releaseTimeout)
		defer cancel()
		if err := db.ReleasePlanPolish(relCtx, p.DB.Pool, user.ID, date, key); err != nil {
			log.Printf("[NEWME] plan polish release for user %d: %v", user.ID, err)
		}
	}()
	callCtx, cancel := context.WithTimeout(ctx, polishTimeout)
	defer cancel()
	facts := factsText(day)
	text, err := p.Client.Text(callCtx, anthropic.Request{
		System: polishSystem, MaxTokens: 300, User: []anthropic.Block{{Text: facts}}})
	if err != nil {
		log.Printf("[NEWME] plan polish for user %d: %v", user.ID, err)
		return "", false
	}
	if !acceptable(text, facts) {
		log.Printf("[NEWME] plan polish for user %d rejected: adds facts or is malformed", user.ID)
		return "", false
	}
	if err := db.SavePlanPolish(ctx, p.DB.Pool, user.ID, date, text); err != nil {
		log.Printf("[NEWME] plan polish save for user %d: %v", user.ID, err)
		return "", false
	}
	saved = true
	return text, true
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
