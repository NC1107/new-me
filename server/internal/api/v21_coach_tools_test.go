package api

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/db"
)

// toolCall is one tool_use block the scripted model emits.
type toolCall struct {
	name  string
	input obj
}

// scripted answers the first request of a chat with the calls and the follow-up carrying their
// results with a closing sentence, the way the Messages API does.
func scripted(calls ...toolCall) func(map[string]any) any {
	return func(req map[string]any) any {
		messages, _ := req["messages"].([]any)
		if len(messages) > 0 {
			if blocks, ok := messages[len(messages)-1].(map[string]any)["content"].([]any); ok && len(blocks) > 0 {
				if blocks[0].(map[string]any)["type"] == "tool_result" {
					return obj{"id": "msg_2", "type": "message", "role": "assistant", "stop_reason": "end_turn",
						"content": []obj{{"type": "text", "text": "Waiting on your tap."}}}
				}
			}
		}
		content := []obj{{"type": "text", "text": "Here is what I would change."}}
		for i, c := range calls {
			content = append(content, obj{"type": "tool_use", "id": fmt.Sprintf("toolu_%d", i), "name": c.name, "input": c.input})
		}
		return obj{"id": "msg_1", "type": "message", "role": "assistant", "stop_reason": "tool_use", "content": content}
	}
}

// toolResults returns the tool_result blocks of the last request.
func toolResults(t *testing.T, fake *fakeClaude) []map[string]any {
	t.Helper()
	req := fake.requests[len(fake.requests)-1]
	messages := req["messages"].([]any)
	var out []map[string]any
	for _, b := range messages[len(messages)-1].(map[string]any)["content"].([]any) {
		out = append(out, b.(map[string]any))
	}
	return out
}

func say(text string) obj { return oneQuestion(text) }

func coachTarget(t *testing.T, h *harness, p person, key string) int {
	t.Helper()
	templates, err := db.GetQuestTemplates(context.Background(), h.db.Pool, p.ID)
	if err != nil {
		t.Fatal(err)
	}
	for _, q := range templates {
		if q.Key == key {
			return q.Target
		}
	}
	t.Fatalf("no template %s", key)
	return 0
}

func coachHarness(t *testing.T) (*harness, *fakeClaude, person, person) {
	t.Helper()
	fake, srv := newFakeClaude(t)
	h := newHarness(t, withCoachClient(srv))
	nick, nadia := h.pair()
	return h, fake, nick, nadia
}

func proposalOf(r *response, i int) (id int, status string) {
	r.t.Helper()
	path := fmt.Sprintf("actions.%d.proposal.", i)
	return r.num(path + "id"), r.str(path + "status")
}

func TestCoachToolsAreOffWithoutAKey(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.post("/api/coach/proposals/1/apply", nick.Token, nil).expect(http.StatusNotFound).code("coach_disabled")
	h.get("/api/coach/facts", nick.Token).expect(http.StatusNotFound).code("coach_disabled")
}

func TestAStatedStepsGoalBecomesACardAndAppliesAndUndoes(t *testing.T) {
	h, fake, nick, nadia := coachHarness(t)
	before := coachTarget(t, h, nick, "steps")
	nadiaBefore := coachTarget(t, h, nadia, "steps")
	fake.reply = scripted(toolCall{coachQuestTool, obj{"quest": "steps", "value": 9500, "stated_text": "steps goal to 9,500"}})

	got := h.post("/api/coach/chat", nick.Token, say("Please raise my steps goal to 9,500")).expect(http.StatusOK)
	if got.str("reply") != "Waiting on your tap." {
		t.Fatalf("reply = %s", got.Body)
	}
	id, status := proposalOf(got, 0)
	if status != "pending" || got.str("actions.0.type") != "proposal" || got.str("actions.0.proposal.source") != "stated" {
		t.Fatalf("actions = %s", got.Body)
	}
	if line := got.str("actions.0.proposal.changes.0.to"); line != "9,500 steps" {
		t.Fatalf("to = %q", line)
	}
	if coachTarget(t, h, nick, "steps") != before {
		t.Fatal("a proposal changed the target before Apply")
	}

	path := fmt.Sprintf("/api/coach/proposals/%d", id)
	applied := h.post(path+"/apply", nick.Token, nil).expect(http.StatusOK)
	if applied.str("status") != "applied" || !applied.flag("canUndo") {
		t.Fatalf("applied = %s", applied.Body)
	}
	if coachTarget(t, h, nick, "steps") != 9500 {
		t.Fatalf("steps = %d", coachTarget(t, h, nick, "steps"))
	}
	h.post(path+"/apply", nick.Token, nil).expect(http.StatusOK)

	undone := h.post(path+"/undo", nick.Token, nil).expect(http.StatusOK)
	if undone.str("status") != "undone" || coachTarget(t, h, nick, "steps") != before {
		t.Fatalf("undone = %s, steps %d", undone.Body, coachTarget(t, h, nick, "steps"))
	}
	h.post(path+"/undo", nick.Token, nil).expect(http.StatusOK)
	h.post(path+"/apply", nick.Token, nil).expect(http.StatusConflict).code("proposal_state")
	if coachTarget(t, h, nadia, "steps") != nadiaBefore {
		t.Fatal("the partner's target changed")
	}
}

const (
	coachQuestTool    = "propose_quest_target"
	coachFoodTool     = "propose_food_target"
	coachTrainingTool = "propose_training_profile"
	coachGoalTool     = "propose_weight_goal"
	coachBodyTool     = "propose_body_info"
	coachRemember     = "remember_fact"
	coachForget       = "forget_fact"
)

func TestAnInventedTargetIsRefusedAndNothingIsStored(t *testing.T) {
	h, fake, nick, _ := coachHarness(t)
	for name, call := range map[string]toolCall{
		"no quote":         {coachQuestTool, obj{"quest": "steps", "value": 12345}},
		"quote not theirs": {coachQuestTool, obj{"quest": "steps", "value": 12345, "stated_text": "12,345 steps"}},
		"wrong number":     {coachQuestTool, obj{"quest": "steps", "value": 9000, "stated_text": "steps goal to 10,000"}},
		"out of range":     {coachQuestTool, obj{"quest": "sleep", "value": 30, "stated_text": "steps goal to 10,000"}},
		"calories":         {coachFoodTool, obj{"target": "calories", "value": 1800, "stated_text": ""}},
	} {
		t.Run(name, func(t *testing.T) {
			fake.reply = scripted(call)
			got := h.post("/api/coach/chat", nick.Token, say("Please raise my steps goal to 10,000")).expect(http.StatusOK)
			if got.length("actions") != 0 {
				t.Fatalf("a proposal was stored: %s", got.Body)
			}
			results := toolResults(t, fake)
			if results[0]["is_error"] != true {
				t.Fatalf("tool result = %v", results[0])
			}
		})
	}
	if coachTarget(t, h, nick, "steps") == 12345 {
		t.Fatal("target changed")
	}
}

func TestAComputedFigureNeedsNoQuote(t *testing.T) {
	h, fake, nick, _ := coachHarness(t)
	targets := h.get("/api/targets", nick.Token).expect(http.StatusOK)
	var water map[string]any
	for _, tg := range targets.at("targets").([]any) {
		if m := tg.(map[string]any); m["key"] == "water" {
			water = m
		}
	}
	current := coachTarget(t, h, nick, "water")
	candidates := []int{int(water["value"].(float64))}
	for _, a := range water["alternatives"].([]any) {
		candidates = append(candidates, int(a.(map[string]any)["value"].(float64)))
	}
	pick := 0
	for _, c := range candidates {
		if c != current {
			pick = c
			break
		}
	}
	if pick == 0 {
		t.Skip("every published water figure equals the current target")
	}
	fake.reply = scripted(toolCall{coachQuestTool, obj{"quest": "water", "value": pick}})
	got := h.post("/api/coach/chat", nick.Token, say("Should I drink more water?")).expect(http.StatusOK)
	if src := got.str("actions.0.proposal.source"); src != "computed" && src != "guideline" {
		t.Fatalf("source = %q: %s", src, got.Body)
	}
}

func TestFoodTargetFromTheWordsOfThePersonAppliesAndUndoClearsIt(t *testing.T) {
	h, fake, nick, _ := coachHarness(t)
	fake.reply = scripted(toolCall{coachFoodTool, obj{"target": "calories", "value": 2100, "stated_text": "2100 calories"}})
	got := h.post("/api/coach/chat", nick.Token, say("My doctor said about 2100 calories a day")).expect(http.StatusOK)
	id, _ := proposalOf(got, 0)
	path := fmt.Sprintf("/api/coach/proposals/%d", id)

	h.post(path+"/apply", nick.Token, nil).expect(http.StatusOK)
	if h.get("/api/me", nick.Token).num("targets.kcal") != 2100 {
		t.Fatal("calorie target not applied")
	}
	h.post(path+"/undo", nick.Token, nil).expect(http.StatusOK)
	if !h.get("/api/me", nick.Token).isNull("targets.kcal") {
		t.Fatal("undo did not clear the calorie target")
	}
}

func TestTrainingProfileChangeKeepsTheRestOfTheProfile(t *testing.T) {
	h, fake, nick, _ := coachHarness(t)
	h.put("/api/training/profile", nick.Token, beginnerProfile).expect(http.StatusOK)
	fake.reply = scripted(toolCall{coachTrainingTool, obj{"days_per_week": 3, "session_minutes": 45, "stated_text": "three days a week for 45 minutes"}})
	got := h.post("/api/coach/chat", nick.Token, say("I can do three days a week for 45 minutes")).expect(http.StatusOK)
	id, _ := proposalOf(got, 0)
	path := fmt.Sprintf("/api/coach/proposals/%d", id)

	h.post(path+"/apply", nick.Token, nil).expect(http.StatusOK)
	profile := h.get("/api/training/profile", nick.Token).expect(http.StatusOK)
	if profile.num("profile.daysPerWeek") != 3 || profile.num("profile.sessionMinutes") != 45 || profile.str("profile.focus") != "first set of 10 pull-ups" {
		t.Fatalf("profile = %s", profile.Body)
	}
	h.post(path+"/undo", nick.Token, nil).expect(http.StatusOK)
	profile = h.get("/api/training/profile", nick.Token).expect(http.StatusOK)
	if profile.num("profile.daysPerWeek") != 2 || profile.num("profile.sessionMinutes") != 40 {
		t.Fatalf("profile after undo = %s", profile.Body)
	}
}

func TestWeightGoalAndBodyInfoNeedTheirWords(t *testing.T) {
	h, fake, nick, _ := coachHarness(t)
	fake.reply = scripted(
		toolCall{coachGoalTool, obj{"kind": "lose", "pace_kg_per_week": 0.5, "stated_text": "lose half a kilo a week"}},
		toolCall{coachBodyTool, obj{"height_cm": 178, "stated_text": "I am 178 cm"}})
	got := h.post("/api/coach/chat", nick.Token, say("I want to lose half a kilo a week. I am 178 cm")).expect(http.StatusOK)
	if got.length("actions") != 2 {
		t.Fatalf("actions = %s", got.Body)
	}
	goal, _ := proposalOf(got, 0)
	body, _ := proposalOf(got, 1)
	h.post(fmt.Sprintf("/api/coach/proposals/%d/apply", goal), nick.Token, nil).expect(http.StatusOK)
	h.post(fmt.Sprintf("/api/coach/proposals/%d/apply", body), nick.Token, nil).expect(http.StatusOK)
	me := h.get("/api/me", nick.Token)
	if me.str("user.goal.kind") != "lose" || me.num("user.heightCm") != 178 {
		t.Fatalf("me = %s", me.Body)
	}
	h.post(fmt.Sprintf("/api/coach/proposals/%d/undo", goal), nick.Token, nil).expect(http.StatusOK)
	if h.get("/api/me", nick.Token).str("user.goal.kind") != "maintain" {
		t.Fatal("goal not restored")
	}
}

func TestTheCoachCannotTouchThePartner(t *testing.T) {
	h, fake, nick, nadia := coachHarness(t)
	nadiaBefore := coachTarget(t, h, nadia, "steps")
	fake.reply = scripted(toolCall{coachQuestTool, obj{"quest": "steps", "value": 10000, "stated_text": "10,000", "user_id": nadia.ID, "user": "Nadia"}})
	got := h.post("/api/coach/chat", nick.Token, say("Set Nadia's steps goal to 10,000")).expect(http.StatusOK)
	id, _ := proposalOf(got, 0)
	path := fmt.Sprintf("/api/coach/proposals/%d", id)

	h.get(path, nadia.Token).expect(http.StatusNotFound)
	h.post(path+"/apply", nadia.Token, nil).expect(http.StatusNotFound)
	h.post(path+"/dismiss", nadia.Token, nil).expect(http.StatusNotFound)
	h.post(path+"/undo", nadia.Token, nil).expect(http.StatusNotFound)
	if coachTarget(t, h, nadia, "steps") != nadiaBefore {
		t.Fatal("the partner's target changed")
	}
	h.post(path+"/apply", nick.Token, nil).expect(http.StatusOK)
	if coachTarget(t, h, nadia, "steps") != nadiaBefore || coachTarget(t, h, nick, "steps") != 10000 {
		t.Fatal("the change landed on the wrong person")
	}
}

func TestProposalsExpireAndCanBeDismissed(t *testing.T) {
	h, fake, nick, _ := coachHarness(t)
	fake.reply = scripted(toolCall{coachQuestTool, obj{"quest": "steps", "value": 10000, "stated_text": "10,000"}})
	got := h.post("/api/coach/chat", nick.Token, say("steps 10,000 please")).expect(http.StatusOK)
	id, _ := proposalOf(got, 0)
	path := fmt.Sprintf("/api/coach/proposals/%d", id)

	h.clock.Set(h.clock.Now().Add(25 * time.Hour))
	if h.get(path, nick.Token).str("status") != "expired" {
		t.Fatal("expected expired")
	}
	h.post(path+"/apply", nick.Token, nil).expect(http.StatusGone).code("proposal_expired")

	h.clock.Set(h.clock.Now().Add(-25 * time.Hour))
	h.post(path+"/dismiss", nick.Token, nil).expect(http.StatusOK)
	h.post(path+"/dismiss", nick.Token, nil).expect(http.StatusOK)
	h.post(path+"/apply", nick.Token, nil).expect(http.StatusConflict)
}

func TestApplyRevalidatesAtApplyTime(t *testing.T) {
	h, fake, nick, _ := coachHarness(t)
	h.put("/api/training/profile", nick.Token, beginnerProfile).expect(http.StatusOK)
	fake.reply = scripted(toolCall{coachTrainingTool, obj{"days_per_week": 4, "stated_text": "four days"}})
	got := h.post("/api/coach/chat", nick.Token, say("four days a week")).expect(http.StatusOK)
	id, _ := proposalOf(got, 0)

	h.delete("/api/training/plan", nick.Token)
	if _, err := h.db.Pool.Exec(context.Background(), `UPDATE coach_proposals SET after_state = jsonb_set(after_state, '{state,training,days}', '9')`); err != nil {
		t.Fatal(err)
	}
	h.post(fmt.Sprintf("/api/coach/proposals/%d/apply", id), nick.Token, nil).expect(http.StatusUnprocessableEntity)
	if h.get(fmt.Sprintf("/api/coach/proposals/%d", id), nick.Token).str("status") != "pending" {
		t.Fatal("a refused apply must leave the card pending")
	}
}

func TestRememberAndForgetFactsStayPrivate(t *testing.T) {
	h, fake, nick, nadia := coachHarness(t)
	fake.reply = scripted(toolCall{coachRemember, obj{"category": "injury", "text": "Sore left knee, avoids jumping"}})
	got := h.post("/api/coach/chat", nick.Token, say("My left knee is sore so I avoid jumping")).expect(http.StatusOK)
	if got.str("actions.0.type") != "fact_saved" || got.str("actions.0.fact.category") != "injury" {
		t.Fatalf("actions = %s", got.Body)
	}
	factID := got.num("actions.0.fact.id")

	facts := h.get("/api/coach/facts", nick.Token).expect(http.StatusOK)
	if facts.length("facts") != 1 || facts.str("facts.0.text") != "Sore left knee, avoids jumping" {
		t.Fatalf("facts = %s", facts.Body)
	}
	if h.get("/api/coach/facts", nadia.Token).length("facts") != 0 {
		t.Fatal("the partner can see Nick's facts")
	}
	h.delete(fmt.Sprintf("/api/coach/facts/%d", factID), nadia.Token).expect(http.StatusNotFound)

	fake.reply = scripted()
	h.post("/api/coach/chat", nick.Token, say("hello")).expect(http.StatusOK)
	if !strings.Contains(systemOf(t, fake.requests[len(fake.requests)-1]), "Sore left knee") {
		t.Fatal("the coach was not given Nick's fact")
	}
	h.post("/api/coach/chat", nadia.Token, say("hello")).expect(http.StatusOK)
	if strings.Contains(systemOf(t, fake.requests[len(fake.requests)-1]), "knee") {
		t.Fatal("the coach was given Nick's fact while talking to Nadia")
	}

	fake.reply = scripted(toolCall{coachForget, obj{"id": factID}})
	gone := h.post("/api/coach/chat", nick.Token, say("forget the knee thing")).expect(http.StatusOK)
	if gone.str("actions.0.type") != "fact_removed" || h.get("/api/coach/facts", nick.Token).length("facts") != 0 {
		t.Fatalf("forget failed: %s", gone.Body)
	}
}

func TestForgetRefusesAnotherPersonsFactAndFactsAreCapped(t *testing.T) {
	h, fake, nick, nadia := coachHarness(t)
	fake.reply = scripted(toolCall{coachRemember, obj{"category": "diet", "text": "No dairy"}})
	got := h.post("/api/coach/chat", nadia.Token, say("I avoid dairy")).expect(http.StatusOK)
	nadiaFact := got.num("actions.0.fact.id")

	fake.reply = scripted(toolCall{coachForget, obj{"id": nadiaFact}})
	h.post("/api/coach/chat", nick.Token, say("forget it")).expect(http.StatusOK)
	if toolResults(t, fake)[0]["is_error"] != true {
		t.Fatal("forgetting the partner's fact must be an error")
	}
	if h.get("/api/coach/facts", nadia.Token).length("facts") != 1 {
		t.Fatal("the partner's fact was removed")
	}

	for i := 0; i < 2; i++ {
		if _, err := db.AddCoachFact(context.Background(), h.db.Pool, nick.ID, "other", "Prefers mornings"); err != nil {
			t.Fatal(err)
		}
	}
	if h.get("/api/coach/facts", nick.Token).length("facts") != 1 {
		t.Fatal("saying the same thing twice must not add a second fact")
	}
	for i := 1; i < db.MaxCoachFacts; i++ {
		if _, err := db.AddCoachFact(context.Background(), h.db.Pool, nick.ID, "other", fmt.Sprintf("fact %d", i)); err != nil {
			t.Fatal(err)
		}
	}
	fake.reply = scripted(toolCall{coachRemember, obj{"category": "other", "text": "one too many"}})
	h.post("/api/coach/chat", nick.Token, say("remember one too many")).expect(http.StatusOK)
	if toolResults(t, fake)[0]["is_error"] != true {
		t.Fatal("the cap was not enforced")
	}
}

func TestTheSystemPromptSaysGemsAndOffersTools(t *testing.T) {
	h, fake, nick, _ := coachHarness(t)
	h.post("/api/coach/chat", nick.Token, say("hi")).expect(http.StatusOK)
	req := fake.requests[0]
	if req["tools"] == nil || !strings.Contains(systemOf(t, req), "Say gems, never points") {
		t.Fatalf("request = %v", req)
	}
}
