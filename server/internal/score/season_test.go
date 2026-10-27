package score

import "testing"

func TestSeasonFor(t *testing.T) {
	end := MustDate("2026-12-31")
	seasons := []Season{
		{ID: 1, Name: "Season 0", StartsOn: "2026-10-26", EndsOn: &end},
		{ID: 2, Name: "Season 1", StartsOn: "2027-01-01"},
	}
	tests := []struct {
		date Date
		want int64
		ok   bool
	}{
		{"2026-10-25", 0, false},
		{"2026-10-26", 1, true},
		{"2026-12-31", 1, true},
		{"2027-01-01", 2, true},
		{"2031-06-01", 2, true},
	}
	for _, tc := range tests {
		got, ok := SeasonFor(tc.date, seasons)
		if ok != tc.ok || got.ID != tc.want {
			t.Fatalf("SeasonFor(%s) = %d %v, want %d %v", tc.date, got.ID, ok, tc.want, tc.ok)
		}
	}
}

func TestWeekRangeIsClippedToTheSeason(t *testing.T) {
	end := MustDate("2026-12-31")
	s0 := Season{StartsOn: "2026-10-28", EndsOn: &end}
	s1 := Season{StartsOn: "2027-01-01"}
	tests := []struct {
		name         string
		season       Season
		date         Date
		wantFrom, to Date
	}{
		{"full week", s1, "2027-01-13", "2027-01-11", "2027-01-17"},
		{"first season week starts at the season", s0, "2026-10-29", "2026-10-28", "2026-11-01"},
		{"last season week ends at the season", s0, "2026-12-30", "2026-12-28", "2026-12-31"},
		{"week of the new year in season 1", s1, "2027-01-02", "2027-01-01", "2027-01-03"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			from, to := tc.season.WeekRange(tc.date)
			if from != tc.wantFrom || to != tc.to {
				t.Fatalf("got %s..%s, want %s..%s", from, to, tc.wantFrom, tc.to)
			}
		})
	}
}
