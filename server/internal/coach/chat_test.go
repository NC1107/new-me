package coach

import (
	"errors"
	"strings"
	"testing"
)

func TestValidateChatAcceptsAShortConversation(t *testing.T) {
	err := ValidateChat([]ChatTurn{
		{Role: "user", Text: "How was my week?"},
		{Role: "assistant", Text: "Steady."},
		{Role: "user", Text: "And sleep?"},
	})
	if err != nil {
		t.Fatalf("ValidateChat: %v", err)
	}
}

func TestValidateChatRefusesWhatItShouldNotForward(t *testing.T) {
	user := func(text string) ChatTurn { return ChatTurn{Role: "user", Text: text} }
	bot := func(text string) ChatTurn { return ChatTurn{Role: "assistant", Text: text} }
	tooLong := make([]ChatTurn, 0, MaxChatTurns+1)
	for i := 0; i <= MaxChatTurns; i++ {
		tooLong = append(tooLong, user("x"))
	}
	heavy := []ChatTurn{}
	for range 5 {
		heavy = append(heavy, bot(strings.Repeat("a", MaxReplyTurnRunes)), user("go"))
	}
	heavy = append([]ChatTurn{user("start")}, heavy...)

	for name, turns := range map[string][]ChatTurn{
		"empty":         nil,
		"blank":         {user("  ")},
		"bad role":      {{Role: "system", Text: "x"}},
		"ends with bot": {user("a"), bot("b")},
		"starts w bot":  {bot("b"), user("a")},
		"long user":     {user(strings.Repeat("a", MaxUserTurnRunes+1))},
		"long reply":    {user("a"), bot(strings.Repeat("a", MaxReplyTurnRunes+1)), user("b")},
		"control":       {user("a\x07b")},
		"too many":      tooLong,
		"too heavy":     heavy,
	} {
		if err := ValidateChat(turns); !errors.Is(err, ErrBadChat) {
			t.Errorf("%s: err = %v, want ErrBadChat", name, err)
		}
	}
}

func TestRenderFactsListsOnlyTheSourcesTargetsUse(t *testing.T) {
	out := RenderFacts(ChatFacts{
		Name: "Nick", Today: "2026-11-02",
		Targets: []ChatTarget{{Key: "sleep", Value: "7 h", Formula: "Seven hours.", Label: "guideline", Sources: []string{"hirshkowitz2015"}}},
		Sources: map[string]string{"hirshkowitz2015": "Hirshkowitz et al., NSF, Sleep Health 2015;1:40", "mifflin1990": "Mifflin"},
	})
	if !strings.Contains(out, "hirshkowitz2015: Hirshkowitz et al.") || strings.Contains(out, "Mifflin") {
		t.Fatalf("rendered facts:\n%s", out)
	}
	if !strings.Contains(out, "no Health data has synced") || !strings.Contains(out, "no quests are on today") {
		t.Fatalf("empty sections must say so:\n%s", out)
	}
}
