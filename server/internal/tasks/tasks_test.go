package tasks

import (
	"testing"

	"github.com/nc1107/new-me/server/internal/score"
)

func TestADeadlineDayIsOnTimeUntilItsLastMinute(t *testing.T) {
	due := score.MustDate("2026-11-03")
	for _, c := range []struct {
		today   string
		overdue bool
	}{{"2026-11-02", false}, {"2026-11-03", false}, {"2026-11-04", true}} {
		if got := Overdue(due, score.MustDate(c.today)); got != c.overdue {
			t.Errorf("today %s: overdue = %v, want %v", c.today, got, c.overdue)
		}
	}
}

func TestDeltaMovesGemsOnlyForFinalTasks(t *testing.T) {
	for status, want := range map[string]int{Done: 40, Missed: -40, Agreed: 0, Proposed: 0, Declined: 0, Withdrawn: 0} {
		if got := Delta(status, 40); got != want {
			t.Errorf("Delta(%s) = %d, want %d", status, got, want)
		}
	}
}

func TestJudgeChargesOnlyAgreedTasksAndDropsStaleProposals(t *testing.T) {
	due := score.MustDate("2026-11-03")
	before, after := score.MustDate("2026-11-03"), score.MustDate("2026-11-04")
	cases := []struct {
		status string
		today  score.Date
		want   Verdict
	}{
		{Agreed, before, Keep},
		{Agreed, after, MarkMissed},
		{Proposed, after, Lapse},
		{Declined, after, Lapse},
		{Proposed, before, Keep},
		{Done, after, Keep},
		{Missed, after, Keep},
		{Withdrawn, after, Keep},
	}
	for _, c := range cases {
		if got := Judge(c.status, due, c.today); got != c.want {
			t.Errorf("Judge(%s, today %s) = %v, want %v", c.status, c.today, got, c.want)
		}
	}
}

func TestOnlyAnAgreedTaskOnTimeCanBeFinished(t *testing.T) {
	due := score.MustDate("2026-11-03")
	if !CanFinish(Agreed, due, due) || CanFinish(Agreed, due, due.AddDays(1)) || CanFinish(Proposed, due, due) ||
		CanFinish(Done, due, due) {
		t.Fatal("finishing needs an agreed task that is not overdue")
	}
	if !CanAnswer(Proposed, due, due) || CanAnswer(Proposed, due, due.AddDays(1)) || CanAnswer(Agreed, due, due) {
		t.Fatal("answering needs a proposal that is not overdue")
	}
}
