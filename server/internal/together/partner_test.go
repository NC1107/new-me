package together

import (
	"strings"
	"testing"
)

func TestWordsOKEnforcesTheWordingRules(t *testing.T) {
	cases := []struct {
		text string
		want bool
	}{
		{"You hold 2 freezes. One could keep Sam's streak going.", true},
		{"", false},
		{strings.Repeat("a", MaxWordsLen), true},
		{strings.Repeat("a", MaxWordsLen+1), false},
		{"Nice work \U0001F525", false},
		{"Nice work ✨", false},
		{"Nice work — keep going", false},
		{"Two\nlines", false},
		{"Plain text with an apostrophe's and 12,000 steps.", true},
	}
	for _, tc := range cases {
		if got := WordsOK(tc.text); got != tc.want {
			t.Errorf("WordsOK(%q) = %v, want %v", tc.text, got, tc.want)
		}
	}
}

func TestFitFallsBackWhenTheTextBreaksTheRules(t *testing.T) {
	if got := Fit(strings.Repeat("x", 120), "short"); got != "short" {
		t.Errorf("fit = %q", got)
	}
	if got := Fit("fine", "short"); got != "fine" {
		t.Errorf("fit = %q", got)
	}
}

func TestRewardMilestoneIsTheHighestThresholdReached(t *testing.T) {
	cases := map[int]int{0: 0, 49: 0, 50: 50, 89: 50, 90: 90, 99: 90, 100: 100, 140: 100}
	for percent, want := range cases {
		if got := RewardMilestone(percent); got != want {
			t.Errorf("milestone(%d) = %d, want %d", percent, got, want)
		}
	}
}

func TestRewardWordsCarryTheNameAndThePercent(t *testing.T) {
	cases := []struct {
		name      string
		threshold int
		want      string
	}{
		{"Trip to Rome", 50, "Trip to Rome is 50% of the way there."},
		{"Trip to Rome", 90, "Trip to Rome is 90% of the way there."},
		{"Trip to Rome", 100, "Trip to Rome is ready to enjoy."},
		{strings.Repeat("N", 80), 50, "Your reward is 50% of the way there."},
		{strings.Repeat("N", 80), 100, "Your reward is ready to enjoy."},
	}
	for _, tc := range cases {
		got := RewardWords(tc.name, tc.threshold)
		if got != tc.want {
			t.Errorf("RewardWords(%q, %d) = %q, want %q", tc.name, tc.threshold, got, tc.want)
		}
		if !WordsOK(got) {
			t.Errorf("%q breaks the wording rules", got)
		}
	}
}

func TestRewardClaimKindsAreCountedAgainstThePartnerBudget(t *testing.T) {
	if got := rewardClaimKind(7, 90); !strings.HasPrefix(got, PartnerClaimPrefix) {
		t.Fatalf("claim %q must start with %q", got, PartnerClaimPrefix)
	}
	for _, kind := range []string{EventPartnerCover, EventPartnerCheer, EventPartnerChallenge} {
		if !strings.HasPrefix(kind, PartnerClaimPrefix) {
			t.Errorf("%s must start with %q so its claim counts against the budget", kind, PartnerClaimPrefix)
		}
	}
}
