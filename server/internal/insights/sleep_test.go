package insights

import (
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/score"
)

var tz = func() *time.Location {
	loc, err := time.LoadLocation("America/New_York")
	if err != nil {
		panic(err)
	}
	return loc
}()

// night builds the night ending on date, going to bed at bedHour:bedMin the evening or early
// morning before and sleeping for asleep minutes.
func night(date score.Date, bed time.Time, asleep int) Night {
	return Night{
		Date: date, BedAt: bed, WakeAt: bed.Add(time.Duration(asleep+20) * time.Minute),
		AsleepMin: asleep, DeepMin: 60, REMMin: 90, CoreMin: asleep - 150, AwakeMin: 20,
	}
}

func at(day score.Date, h, m int) time.Time {
	t := day.Time()
	return time.Date(t.Year(), t.Month(), t.Day(), h, m, 0, 0, tz)
}

func TestSleepAveragesCountOnlyNightsWithData(t *testing.T) {
	nights := []Night{
		night("2026-11-02", at("2026-11-01", 23, 0), 420),
		night("2026-11-01", at("2026-10-31", 23, 0), 360),
		{Date: "2026-10-31", BedAt: at("2026-10-30", 23, 0), WakeAt: at("2026-10-31", 6, 0)},
		night("2026-10-05", at("2026-10-04", 23, 0), 480),
	}
	got := ComputeSleep(SleepInput{Nights: nights, Today: today, TargetMin: 420, Loc: tz})
	if *got.Avg7Min != 390 || got.Avg30Min != 420 || got.TargetMin != 420 {
		t.Fatalf("averages = %+v", got)
	}
	if len(got.Nights) != 2 || got.Nights[0].Date != "2026-11-01" || got.Nights[1].Date != "2026-11-02" {
		t.Fatalf("14-night list = %+v", got.Nights)
	}
	if got.LastNight == nil || got.LastNight.Date != "2026-11-02" || got.LastNight.AsleepMin != 420 {
		t.Fatalf("last night = %+v", got.LastNight)
	}
}

func TestSleepWindowsAreInclusiveOfTodayAndBounded(t *testing.T) {
	var nights []Night
	for i := 0; i < 20; i++ {
		d := today.AddDays(-i)
		nights = append(nights, night(d, at(d.AddDays(-1), 23, 0), 400+i))
	}
	got := ComputeSleep(SleepInput{Nights: nights, Today: today, TargetMin: 420, Loc: tz})
	if len(got.Nights) != 14 || got.Nights[13].Date != today || got.Nights[0].Date != today.AddDays(-13) {
		t.Fatalf("14-night list = %+v", got.Nights)
	}
	// Last 7 nights are 400..406.
	if *got.Avg7Min != 403 {
		t.Fatalf("avg7 = %d, want 403", *got.Avg7Min)
	}
	// Last 30 covers all 20 nights: mean of 400..419.
	if got.Avg30Min != 410 {
		t.Fatalf("avg30 = %d, want 410 (409.5 rounded)", got.Avg30Min)
	}
}

func TestSleepBedtimeAcrossMidnight(t *testing.T) {
	tests := []struct {
		name   string
		beds   [][2]int
		avg    string
		spread int
	}{
		{"same evening time", [][2]int{{23, 0}, {23, 0}, {23, 0}}, "23:00", 0},
		{"straddling midnight averages to midnight", [][2]int{{23, 0}, {1, 0}}, "00:00", 60},
		{"late evening and after midnight", [][2]int{{23, 30}, {0, 30}, {23, 30}, {0, 30}}, "00:00", 30},
		{"a single night has no spread", [][2]int{{22, 45}}, "22:45", 0},
		{"early evening", [][2]int{{21, 0}, {22, 0}}, "21:30", 30},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var nights []Night
			for i, b := range tt.beds {
				date := today.AddDays(-i)
				bed := at(date, b[0], b[1])
				if b[0] >= 12 {
					bed = at(date.AddDays(-1), b[0], b[1])
				}
				nights = append(nights, night(date, bed, 400))
			}
			got := ComputeSleep(SleepInput{Nights: nights, Today: today, TargetMin: 420, Loc: tz})
			if got.AvgBedtime == nil || *got.AvgBedtime != tt.avg || got.BedtimeSpreadMin != tt.spread {
				t.Fatalf("avg bedtime %v spread %d, want %s and %d", deref(got.AvgBedtime), got.BedtimeSpreadMin, tt.avg, tt.spread)
			}
		})
	}
}

func deref(s *string) string {
	if s == nil {
		return "<nil>"
	}
	return *s
}

func TestSleepAverageWakeAndZone(t *testing.T) {
	// The same instants read differently in another zone, so the person's wall clock decides.
	nights := []Night{
		{Date: "2026-11-02", BedAt: time.Date(2026, 11, 2, 4, 0, 0, 0, time.UTC), WakeAt: time.Date(2026, 11, 2, 11, 30, 0, 0, time.UTC), AsleepMin: 400},
		{Date: "2026-11-01", BedAt: time.Date(2026, 11, 1, 3, 0, 0, 0, time.UTC), WakeAt: time.Date(2026, 11, 1, 10, 30, 0, 0, time.UTC), AsleepMin: 400},
	}
	got := ComputeSleep(SleepInput{Nights: nights, Today: today, TargetMin: 420, Loc: tz})
	// Both nights start at 23:00 on the wall clock, one before and one after the clocks went
	// back on Nov 1, and the wakes are 05:30 and 06:30 local.
	if got.AvgBedtime == nil || *got.AvgBedtime != "23:00" || *got.AvgWake != "06:00" {
		t.Fatalf("bed %v wake %v", deref(got.AvgBedtime), deref(got.AvgWake))
	}
	utc := ComputeSleep(SleepInput{Nights: nights, Today: today, TargetMin: 420, Loc: time.UTC})
	if *utc.AvgBedtime != "03:30" || *utc.AvgWake != "11:00" {
		t.Fatalf("utc bed %s wake %s", *utc.AvgBedtime, *utc.AvgWake)
	}
}

func TestSleepWakeAcrossMidnightIsCircular(t *testing.T) {
	// A night shift: waking at 23:30 and 00:30.
	nights := []Night{
		{Date: "2026-11-02", BedAt: at("2026-11-02", 15, 0), WakeAt: at("2026-11-02", 23, 30), AsleepMin: 450},
		{Date: "2026-11-01", BedAt: at("2026-11-01", 16, 0), WakeAt: at("2026-11-02", 0, 30), AsleepMin: 450},
	}
	got := ComputeSleep(SleepInput{Nights: nights, Today: today, TargetMin: 420, Loc: tz})
	if *got.AvgWake != "00:00" {
		t.Fatalf("avg wake = %s, want 00:00", *got.AvgWake)
	}
}

func TestSleepStages7AreAveragedOverTheLastWeek(t *testing.T) {
	nights := []Night{
		{Date: "2026-11-02", BedAt: at("2026-11-01", 23, 0), WakeAt: at("2026-11-02", 7, 0), AsleepMin: 420, DeepMin: 60, REMMin: 100, CoreMin: 260, AwakeMin: 30},
		{Date: "2026-11-01", BedAt: at("2026-10-31", 23, 0), WakeAt: at("2026-11-01", 7, 0), AsleepMin: 400, DeepMin: 80, REMMin: 80, CoreMin: 240, AwakeMin: 41},
		// Outside the last 7 nights.
		{Date: "2026-10-20", BedAt: at("2026-10-19", 23, 0), WakeAt: at("2026-10-20", 7, 0), AsleepMin: 400, DeepMin: 400},
	}
	got := ComputeSleep(SleepInput{Nights: nights, Today: today, TargetMin: 420, Loc: tz})
	want := Stages{DeepMin: 70, REMMin: 90, CoreMin: 250, AwakeMin: 36}
	if got.Stages7 == nil || *got.Stages7 != want {
		t.Fatalf("stages7 = %+v, want %+v", got.Stages7, want)
	}
}

func TestSleepWithNoNights(t *testing.T) {
	got := ComputeSleep(SleepInput{Today: today, TargetMin: 420, Loc: tz})
	if got.AvgBedtime != nil || got.AvgWake != nil || got.Stages7 != nil || got.LastNight != nil ||
		got.Avg7Min != nil || got.BedtimeSpreadMin != 0 || got.Nights == nil || len(got.Nights) != 0 || got.TargetMin != 420 {
		t.Fatalf("empty = %+v", got)
	}
}

func TestSleepLastNightOnlyFromTheWindowAndUnsortedInput(t *testing.T) {
	nights := []Night{
		night("2026-11-02", at("2026-11-01", 23, 0), 420),
		night("2026-10-25", at("2026-10-24", 23, 0), 300),
		night("2026-10-30", at("2026-10-29", 23, 0), 380),
	}
	got := ComputeSleep(SleepInput{Nights: nights, Today: today, TargetMin: 420, Loc: tz})
	if got.LastNight.Date != "2026-11-02" || got.Nights[0].Date != "2026-10-25" {
		t.Fatalf("got %+v", got)
	}
	stale := []Night{night("2026-10-10", at("2026-10-09", 23, 0), 300)}
	old := ComputeSleep(SleepInput{Nights: stale, Today: today, TargetMin: 420, Loc: tz})
	if old.LastNight != nil {
		t.Fatalf("a night outside the 14 day window is not last night: %+v", old.LastNight)
	}
}
