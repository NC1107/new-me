package coach

import (
	"strings"
	"testing"
)

func TestPolishPromptAsksForOneShortSentenceThatDoesNotRepeatTheList(t *testing.T) {
	for _, want := range []string{"exactly one short, plain sentence", "never repeat or summarise the list", "No exclamation marks"} {
		if !strings.Contains(polishSystem, want) {
			t.Errorf("polishSystem lacks %q", want)
		}
	}
}

func TestAcceptableKeepsThePlanWordingShort(t *testing.T) {
	facts := "Plan:\n- Steps: 4,491 to go (about 45 min)\n"
	if !acceptable("Nothing counted yet, so steps are the easy start.", facts) {
		t.Error("a short sentence over the given facts was rejected")
	}
	long := strings.Repeat("A walk would help you a lot today. ", 8)
	if acceptable(long, facts) {
		t.Error("a paragraph past the length cap was accepted")
	}
}
