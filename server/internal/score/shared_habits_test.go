package score

import "testing"

func TestSharedDue(t *testing.T) {
	d := MustDate
	last := func(s string) *Date { v := d(s); return &v }
	// 2026-11-04 is a Wednesday.
	monWedFri := SharedSchedule{Kind: SharedWeekdays, Weekdays: 0b0010101}
	tests := []struct {
		name     string
		sched    SharedSchedule
		startOn  Date
		lastDone *Date
		today    Date
		state    string
		dueOn    Date
		days     int
	}{
		{"daily never done is due today", SharedSchedule{Kind: SharedDaily}, d("2026-11-01"), nil, d("2026-11-04"),
			SharedDueToday, d("2026-11-04"), 0},
		{"daily done today is next due tomorrow", SharedSchedule{Kind: SharedDaily}, d("2026-11-01"), last("2026-11-04"),
			d("2026-11-04"), SharedUpcoming, d("2026-11-05"), 1},
		{"daily missed days is still just due today", SharedSchedule{Kind: SharedDaily}, d("2026-11-01"), last("2026-11-01"),
			d("2026-11-04"), SharedDueToday, d("2026-11-04"), 0},
		{"daily created tomorrow in the creator's zone is upcoming", SharedSchedule{Kind: SharedDaily}, d("2026-11-05"), nil,
			d("2026-11-04"), SharedUpcoming, d("2026-11-05"), 1},
		{"weekly never done is due from its start", SharedSchedule{Kind: SharedWeekly}, d("2026-11-04"), nil, d("2026-11-04"),
			SharedDueToday, d("2026-11-04"), 0},
		{"weekly done today is due in a week", SharedSchedule{Kind: SharedWeekly}, d("2026-10-01"), last("2026-11-04"),
			d("2026-11-04"), SharedUpcoming, d("2026-11-11"), 7},
		{"weekly done nine days ago is two days overdue", SharedSchedule{Kind: SharedWeekly}, d("2026-10-01"),
			last("2026-10-26"), d("2026-11-04"), SharedOverdue, d("2026-11-02"), -2},
		{"every three days upcoming", SharedSchedule{Kind: SharedEveryN, EveryDays: 3}, d("2026-10-01"), last("2026-11-03"),
			d("2026-11-04"), SharedUpcoming, d("2026-11-06"), 2},
		{"every three days due today", SharedSchedule{Kind: SharedEveryN, EveryDays: 3}, d("2026-10-01"), last("2026-11-01"),
			d("2026-11-04"), SharedDueToday, d("2026-11-04"), 0},
		{"weekdays never done waits for the first scheduled day", monWedFri, d("2026-11-03"), nil, d("2026-11-03"),
			SharedUpcoming, d("2026-11-04"), 1},
		{"weekdays done on a scheduled day moves to the next one", monWedFri, d("2026-10-01"), last("2026-11-04"),
			d("2026-11-04"), SharedUpcoming, d("2026-11-06"), 2},
		{"weekdays missed Monday is overdue on Wednesday", monWedFri, d("2026-10-01"), last("2026-10-30"), d("2026-11-04"),
			SharedOverdue, d("2026-11-02"), -2},
		{"weekdays wraps over the weekend", monWedFri, d("2026-10-01"), last("2026-11-06"), d("2026-11-07"),
			SharedUpcoming, d("2026-11-09"), 2},
	}
	for _, tc := range tests {
		got := SharedDue(tc.sched, tc.startOn, tc.lastDone, tc.today)
		if got.State != tc.state || got.DueOn != tc.dueOn || got.Days != tc.days {
			t.Errorf("%s: got %+v, want state %s due %s days %d", tc.name, got, tc.state, tc.dueOn, tc.days)
		}
	}
}

func TestValidSharedSchedule(t *testing.T) {
	good := []SharedSchedule{{Kind: SharedDaily}, {Kind: SharedWeekly}, {Kind: SharedWeekdays, Weekdays: 1},
		{Kind: SharedEveryN, EveryDays: 2}, {Kind: SharedEveryN, EveryDays: 365}}
	bad := []SharedSchedule{{}, {Kind: "monthly"}, {Kind: SharedWeekdays}, {Kind: SharedWeekdays, Weekdays: 128},
		{Kind: SharedEveryN}, {Kind: SharedEveryN, EveryDays: 1}, {Kind: SharedEveryN, EveryDays: 366}}
	for _, s := range good {
		if !ValidSharedSchedule(s) {
			t.Errorf("%+v should be valid", s)
		}
	}
	for _, s := range bad {
		if ValidSharedSchedule(s) {
			t.Errorf("%+v should be invalid", s)
		}
	}
}
