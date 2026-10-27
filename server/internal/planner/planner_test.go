package planner

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"

	"github.com/nc1107/new-me/server/internal/anthropic"
	"github.com/nc1107/new-me/server/internal/training"
)

type obj = map[string]any

// fakeClaude answers each submit_plan call with the next queued plan and records prompts.
type fakeClaude struct {
	mu      sync.Mutex
	replies []any
	prompts []string
}

func newFake(t *testing.T, replies ...any) (*fakeClaude, *Planner) {
	t.Helper()
	f := &fakeClaude{replies: replies}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req obj
		_ = json.NewDecoder(r.Body).Decode(&req)
		f.mu.Lock()
		defer f.mu.Unlock()
		msgs := req["messages"].([]any)
		content := msgs[0].(obj)["content"].([]any)
		f.prompts = append(f.prompts, content[0].(obj)["text"].(string))
		if len(f.replies) == 0 {
			http.Error(w, "no reply queued", http.StatusInternalServerError)
			return
		}
		reply := f.replies[0]
		f.replies = f.replies[1:]
		_ = json.NewEncoder(w).Encode(obj{"content": []obj{{"type": "tool_use", "name": "submit_plan", "input": reply}}})
	}))
	t.Cleanup(srv.Close)
	return f, &Planner{Client: anthropic.New("k", srv.URL)}
}

var catalog = []Exercise{
	{Key: "push_up", Name: "Push-up", PrimaryMuscles: []string{"chest"}},
	{Key: "pull_up", Name: "Pull-up", PrimaryMuscles: []string{"back"}, Equipment: []string{"pullup_bar"}},
	{Key: "pike", Name: "Pike push-up", PrimaryMuscles: []string{"shoulders"}},
	{Key: "split_squat", Name: "Split squat", PrimaryMuscles: []string{"quads", "glutes"}},
}

var input = Input{
	Profile: training.Profile{DaysPerWeek: 2, SessionMinutes: 40, Experience: training.ExperienceNew,
		Equipment: []string{"pullup_bar"}},
	Focus:   "first set of 10 pull-ups",
	Catalog: catalog,
}

func dayJSON(label string, weekday, sets int) obj {
	ex := func(key string) obj {
		return obj{"exercise": key, "sets": sets, "min": 5, "max": 8, "rir": 2, "restSec": 90}
	}
	return obj{"label": label, "weekday": weekday,
		"exercises": []obj{ex("push_up"), ex("pull_up"), ex("pike"), ex("split_squat")}}
}

func planJSON(sets int) obj {
	return obj{"weeks": 4, "notes": "Two full-body days.", "days": []obj{dayJSON("A", 1, sets), dayJSON("B", 4, sets)}}
}

func TestGenerateReturnsAValidPlan(t *testing.T) {
	f, p := newFake(t, planJSON(2))
	plan, err := p.Generate(context.Background(), input)
	if err != nil {
		t.Fatal(err)
	}
	if plan.Weeks != 4 || len(plan.Days) != 2 || plan.Days[0].Exercises[1].Exercise != "pull_up" || plan.Notes == "" {
		t.Fatalf("plan = %+v", plan)
	}
	if len(f.prompts) != 1 {
		t.Fatalf("expected one call, got %d", len(f.prompts))
	}
	for _, want := range []string{"first set of 10 pull-ups", "Exactly 2 training days", "WHO 2020", "between 4 and 12", "pull_up: Pull-up"} {
		if !strings.Contains(f.prompts[0], want) {
			t.Errorf("prompt is missing %q", want)
		}
	}
}

func TestGenerateRepairsOnce(t *testing.T) {
	f, p := newFake(t, planJSON(1), planJSON(2))
	plan, err := p.Generate(context.Background(), input)
	if err != nil {
		t.Fatal(err)
	}
	if plan.Days[0].Exercises[0].Sets != 2 {
		t.Fatalf("expected the repaired plan, got %+v", plan)
	}
	if len(f.prompts) != 2 || !strings.Contains(f.prompts[1], "broke these rules") || !strings.Contains(f.prompts[1], "2 short of the 4 minimum") ||
		!strings.Contains(f.prompts[1], "Your previous plan:") ||
		!strings.Contains(f.prompts[1], "counted by the server: back 2, chest 2, glutes 2, quads 2, shoulders 2.") || !strings.Contains(f.prompts[1], `"Exercise":"pull_up","Sets":1`) {
		t.Fatalf("the repair prompt should list the violations: %v", f.prompts)
	}
}

func TestGenerateTopsUpAPlanShortOnlyOfWeeklySets(t *testing.T) {
	_, p := newFake(t, planJSON(1), planJSON(1), planJSON(1))
	plan, err := p.Generate(context.Background(), input)
	if err != nil {
		t.Fatal(err)
	}
	for _, d := range plan.Days {
		for _, e := range d.Exercises {
			if e.Sets != 2 {
				t.Fatalf("every group was 2 short, so each exercise gains one set a day: %+v", plan)
			}
		}
	}
}

func TestGenerateRejectsAfterTheRepairRounds(t *testing.T) {
	bad := planJSON(1)
	bad["weeks"] = 9
	f, p := newFake(t, bad, bad, bad)
	_, err := p.Generate(context.Background(), input)
	if len(f.prompts) != 1+RepairRounds {
		t.Fatalf("expected %d calls, got %d", 1+RepairRounds, len(f.prompts))
	}
	var invalid *InvalidPlan
	if !errors.As(err, &invalid) || !errors.Is(err, ErrInvalid) || len(invalid.Violations) == 0 {
		t.Fatalf("err = %v", err)
	}
}

func TestChangePromptCarriesTheCurrentPlanAndRequest(t *testing.T) {
	f, p := newFake(t, planJSON(2))
	current := training.Plan{Weeks: 4}
	in := input
	in.Current, in.Change = &current, "swap pull-ups, my elbow hurts"
	if _, err := p.Generate(context.Background(), in); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(f.prompts[0], "Requested change: swap pull-ups, my elbow hurts") ||
		!strings.Contains(f.prompts[0], "Current plan:") {
		t.Fatalf("prompt = %s", f.prompts[0])
	}
}
