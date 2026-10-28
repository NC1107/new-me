package together

import (
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/score"
)

func TestQuietFollowsTheScheduleInThePersonsOwnZone(t *testing.T) {
	loc, err := time.LoadLocation("America/New_York")
	if err != nil {
		t.Fatal(err)
	}
	// Wake 07:00 plus the default 10 minute offset, bed 23:00.
	schedule := score.DefaultSchedule()
	at := func(h, m int) time.Time { return time.Date(2026, 11, 4, h, m, 0, 0, loc).UTC() }
	cases := []struct {
		name string
		now  time.Time
		want bool
	}{
		{"before the first notification", at(7, 9), true},
		{"at the first notification", at(7, 10), false},
		{"midday", at(12, 0), false},
		{"last minute before bed", at(22, 59), false},
		{"at bedtime", at(23, 0), true},
		{"small hours", at(2, 30), true},
	}
	for _, tc := range cases {
		if got := Quiet(schedule, loc, nil, tc.now); got != tc.want {
			t.Errorf("%s: quiet = %v, want %v", tc.name, got, tc.want)
		}
	}
}

func TestQuietUsesTheDayOffScheduleOnDaysOff(t *testing.T) {
	loc := time.UTC
	schedule := score.DefaultSchedule()
	schedule.DayOff = score.DaySchedule{WakeMin: 9 * 60, BedMin: 23 * 60}
	saturday := time.Date(2026, 11, 7, 8, 0, 0, 0, loc)
	wednesday := time.Date(2026, 11, 4, 8, 0, 0, 0, loc)
	if !Quiet(schedule, loc, nil, saturday) {
		t.Error("08:00 on a day off should be quiet")
	}
	if Quiet(schedule, loc, nil, wednesday) {
		t.Error("08:00 on a workday should not be quiet")
	}
}

func TestQuietOnAwayDays(t *testing.T) {
	loc := time.UTC
	schedule := score.DefaultSchedule()
	noon := time.Date(2026, 11, 4, 12, 0, 0, 0, loc)
	away := []db.AwaySpan{{From: score.MustDate("2026-11-04"), To: score.MustDate("2026-11-06")}}
	if !Quiet(schedule, loc, away, noon) {
		t.Error("an away day is quiet all day")
	}
	later := []db.AwaySpan{{From: score.MustDate("2026-11-05"), To: score.MustDate("2026-11-06")}}
	if Quiet(schedule, loc, later, noon) {
		t.Error("an away span that starts tomorrow does not silence today")
	}
}

func TestQuietWithABedtimeAfterMidnightEndsTheWindowAtMidnight(t *testing.T) {
	loc := time.UTC
	schedule := score.DefaultSchedule()
	schedule.Workday = score.DaySchedule{WakeMin: 10 * 60, BedMin: 60}
	if Quiet(schedule, loc, nil, time.Date(2026, 11, 4, 23, 30, 0, 0, loc)) {
		t.Error("23:30 is before a 01:00 bedtime's midnight cut-off")
	}
	if !Quiet(schedule, loc, nil, time.Date(2026, 11, 4, 0, 30, 0, 0, loc)) {
		t.Error("00:30 belongs to the quiet hours before wake")
	}
}

func TestHeldAppliesToEveryKindExceptSafetyOnes(t *testing.T) {
	night := time.Date(2026, 11, 4, 3, 0, 0, 0, time.UTC)
	svc := &Service{Now: func() time.Time { return night }}
	user := db.User{ID: 1, Timezone: "UTC", Schedule: score.DefaultSchedule()}
	for _, kind := range []string{EventPartnerDone, EventCheer, EventChallenge, EventReward, EventCover,
		EventHabitProposal, EventMilestone, EventPartnerCover, EventRewardProgress, EventBehindPaceAfternoon} {
		if !svc.Held(user, kind) {
			t.Errorf("%s should wait for the morning", kind)
		}
	}
	safetyKinds["test_safety"] = true
	defer delete(safetyKinds, "test_safety")
	if svc.Held(user, "test_safety") {
		t.Error("a safety kind ignores quiet hours")
	}
	svc.Now = func() time.Time { return night.Add(9 * time.Hour) }
	if svc.Held(user, EventCheer) {
		t.Error("noon is not quiet")
	}
}
