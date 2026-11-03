package coach

import (
	"context"
	"encoding/json"
	"strings"

	"github.com/nc1107/new-me/server/internal/anthropic"
)

// Tool names the coach may call. Each maps to one write path the settings pages already use.
const (
	ToolQuestTarget    = "propose_quest_target"
	ToolFoodTarget     = "propose_food_target"
	ToolTrainingPlan   = "propose_training_profile"
	ToolWeightGoal     = "propose_weight_goal"
	ToolBodyInfo       = "propose_body_info"
	ToolWeeklyGoal     = "propose_weekly_suggestion"
	ToolRememberFact   = "remember_fact"
	ToolForgetFact     = "forget_fact"
	maxToolRounds      = 3
	maxCallsPerMessage = 6
)

const toolsSystem = `Tools:
- You can propose changes to this person's own targets and goals, and remember facts they tell you. Never act for the other person in the app.
- A proposal does nothing until the person taps Apply on a card. After proposing, say what you proposed in one sentence and that it is waiting for them. Never say a target is changed.
- A target number must be one the person said in their own words, or one listed in DATA (the computed value or one of its alternatives). Pass what they said in stated_text, copied exactly from their message. Never calculate a new target yourself and never round one. If neither applies, ask them what number they want, or explain what DATA is missing.
- Propose at most one change per target. Use the tool that matches what they asked; do not propose changes they did not ask for or agree to.
- remember_fact is only for something the person told you about themselves (an injury, a schedule, a preference, equipment they own, a dietary need). Write it as a short plain statement in their words, without adding detail. Do not save moods, numbers already in DATA, or anything about the other person. When they ask you to forget something, use forget_fact with the id from SAVED FACTS.
- Quest target units: steps are steps, exercise, sleep, breathing, reading and yoga are minutes, water is millilitres, produce is servings, pushups is reps, meals_logged is meals.
- Say gems, never points.`

// ToolResult is what a tool call answers to the model.
type ToolResult struct {
	Text    string
	IsError bool
}

// ToolRunner executes the tool calls of one chat message for one person.
type ToolRunner interface {
	Run(ctx context.Context, name string, input json.RawMessage) ToolResult
}

func objectSchema(required []string, props map[string]any) map[string]any {
	return map[string]any{"type": "object", "properties": props, "required": required}
}

var (
	statedText = map[string]any{"type": "string",
		"description": "The words from the person's own message that give this number, copied exactly. Leave empty when the number is the computed value or an alternative listed in DATA."}
	intValue = func(desc string) map[string]any { return map[string]any{"type": "integer", "description": desc} }
)

// Tools lists the tools offered to the model.
func Tools() []anthropic.Tool {
	return []anthropic.Tool{
		{Name: ToolQuestTarget, Description: "Propose a new daily target for one quest of the person asking. Shows a card they must Apply.",
			Schema: objectSchema([]string{"quest", "value"}, map[string]any{
				"quest": map[string]any{"type": "string", "enum": []string{"steps", "exercise", "sleep", "water", "produce", "breathing", "reading", "pushups", "meals_logged", "yoga"}},
				"value": intValue("The new target in the quest's unit."), "stated_text": statedText})},
		{Name: ToolFoodTarget, Description: "Propose a new daily calorie, protein, fat or carbohydrate target for the person asking. Shows a card they must Apply.",
			Schema: objectSchema([]string{"target", "value"}, map[string]any{
				"target": map[string]any{"type": "string", "enum": []string{"calories", "protein", "fat", "carbs"}},
				"value":  intValue("kcal for calories, grams for the others."), "stated_text": statedText})},
		{Name: ToolTrainingPlan, Description: "Propose a change to how many days a week they train or how long a session is. Shows a card they must Apply.",
			Schema: objectSchema([]string{"stated_text"}, map[string]any{
				"days_per_week":   intValue("2 to 6."),
				"session_minutes": intValue("20 to 90."), "stated_text": statedText})},
		{Name: ToolWeightGoal, Description: "Propose a weight goal: lose, maintain or gain, with a pace in kilograms a week for lose and gain. Shows a card they must Apply.",
			Schema: objectSchema([]string{"kind"}, map[string]any{
				"kind":             map[string]any{"type": "string", "enum": []string{"lose", "maintain", "gain"}},
				"pace_kg_per_week": map[string]any{"type": "number", "description": "Kilograms a week; omit for maintain."},
				"stated_text":      statedText})},
		{Name: ToolBodyInfo, Description: "Propose a correction to their height, birth year or units, only when they told you the new value. Shows a card they must Apply.",
			Schema: objectSchema([]string{"stated_text"}, map[string]any{
				"height_cm":   map[string]any{"type": "number"},
				"birth_year":  intValue("Four digit year."),
				"units":       map[string]any{"type": "string", "enum": []string{"metric", "imperial"}},
				"stated_text": statedText})},
		{Name: ToolWeeklyGoal, Description: "Propose accepting one of this week's suggested target changes listed under WEEKLY SUGGESTIONS in DATA. Shows a card they must Apply.",
			Schema: objectSchema([]string{"key"}, map[string]any{"key": map[string]any{"type": "string"}})},
		{Name: ToolRememberFact, Description: "Save a short fact the person just told you about themselves so you remember it later. Saved at once and shown in Me under What the coach knows.",
			Schema: objectSchema([]string{"category", "text"}, map[string]any{
				"category": map[string]any{"type": "string", "enum": []string{"injury", "schedule", "preference", "equipment", "diet", "other"}},
				"text":     map[string]any{"type": "string", "description": "At most 200 characters, in the person's words."}})},
		{Name: ToolForgetFact, Description: "Delete a saved fact the person asked you to forget.",
			Schema: objectSchema([]string{"id"}, map[string]any{"id": intValue("The id shown in SAVED FACTS.")})},
	}
}

// ReplyWithTools answers like Reply but lets the model call tools, running them through runner
// and feeding the results back, for at most maxToolRounds model calls.
func (c *Chatter) ReplyWithTools(ctx context.Context, facts ChatFacts, turns []ChatTurn, runner ToolRunner) (string, error) {
	wire := make([]anthropic.Turn, len(turns))
	messages := make([]anthropic.Message, len(turns))
	for i, t := range turns {
		text := strings.TrimSpace(t.Text)
		wire[i] = anthropic.Turn{Role: t.Role, Text: text}
		messages[i] = anthropic.Message{Role: t.Role, Content: []anthropic.Content{{Type: "text", Text: text}}}
	}
	callCtx, cancel := context.WithTimeout(ctx, chatTimeout)
	defer cancel()
	req := anthropic.Request{
		System:    chatSystem + "\n" + toolsSystem + "\n\n" + RenderFacts(facts),
		Turns:     wire,
		MaxTokens: chatMaxTokens,
		Tools:     Tools(),
	}
	made := 0
	var last string
	for round := 0; round < maxToolRounds; round++ {
		reply, err := c.Client.Converse(callCtx, req)
		if err != nil {
			return "", err
		}
		if reply.Text != "" {
			last = reply.Text
		}
		if len(reply.Calls) == 0 {
			break
		}
		results := make([]anthropic.Content, len(reply.Calls))
		for i, call := range reply.Calls {
			made++
			res := ToolResult{Text: "Too many tool calls in one message.", IsError: true}
			if made <= maxCallsPerMessage {
				res = runner.Run(callCtx, call.Name, call.Input)
			}
			results[i] = anthropic.Content{Type: "tool_result", ToolUseID: call.ID, Result: res.Text, IsError: res.IsError}
		}
		messages = append(messages,
			anthropic.Message{Role: "assistant", Content: reply.Blocks},
			anthropic.Message{Role: "user", Content: results})
		req.Turns = nil
		req.Messages = messages
	}
	if last == "" {
		return "Done.", nil
	}
	return last, nil
}
