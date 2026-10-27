package db_test

import (
	"fmt"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/dbtest"
	"github.com/nc1107/new-me/server/internal/score"
)

func TestNewUsersGetTheDefaultScheduleAndPerKilogramProtein(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	if u.Schedule != score.DefaultSchedule() {
		t.Fatalf("schedule = %+v, want the defaults", u.Schedule)
	}
	if !u.ProteinAuto || u.StreakRulesFrom != nil || !u.Notify.Milestones || !u.Notify.Lookback {
		t.Fatalf("user = %+v", u)
	}

	u.Schedule.Workday = score.DaySchedule{WakeMin: 6*60 + 30, BedMin: 30}
	u.Schedule.Workdays = 0b1100000
	u.Schedule.FirstOffsetMin = 45
	if err := db.UpdateUser(ctx, database.Pool, u); err != nil {
		t.Fatal(err)
	}
	got, err := db.GetUser(ctx, database.Pool, u.ID)
	if err != nil || got.Schedule != u.Schedule {
		t.Fatalf("stored schedule = %+v %v", got.Schedule, err)
	}
	u.Schedule.DayOff.BedMin = u.Schedule.DayOff.WakeMin
	if err := db.UpdateUser(ctx, database.Pool, u); err == nil {
		t.Fatal("the table must refuse equal wake and bed times")
	}
}

func TestProteinSnapshotFollowsLatestWeightUntilATargetIsSet(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	target := func(date score.Date) int {
		if err := db.EnsureSnapshot(ctx, database.Pool, u.ID, date); err != nil {
			t.Fatal(err)
		}
		quests, _ := db.GetDayQuests(ctx, database.Pool, u.ID, date)
		for _, q := range quests {
			if q.Key == db.QuestProtein {
				return q.Target
			}
		}
		t.Fatal("no protein quest")
		return 0
	}
	if got := target("2026-10-27"); got != db.DefaultProteinTarget {
		t.Fatalf("no weight yet: %d, want the default", got)
	}
	// 78 kg x 1.6 = 124.8 g, rounded to 125.
	if _, err := db.UpsertHealthDaily(ctx, database.Pool, u.ID, "2026-10-27", db.MetricWeight, 78, "healthkit", time.Now()); err != nil {
		t.Fatal(err)
	}
	if got := target("2026-10-28"); got != 125 {
		t.Fatalf("with 78 kg: %d, want 125", got)
	}
	if _, err := db.UpsertHealthDaily(ctx, database.Pool, u.ID, "2026-10-28", db.MetricWeight, 80.2, "healthkit", time.Now()); err != nil {
		t.Fatal(err)
	}
	if got := target("2026-10-29"); got != 130 {
		t.Fatalf("with 80.2 kg: %d, want 130 (128.3 rounds to 130)", got)
	}
	if got := target("2026-10-28"); got != 125 {
		t.Fatalf("a snapshot never changes afterwards: %d", got)
	}
	own := 150
	u.ProteinTarget = &own
	if err := db.UpdateUser(ctx, database.Pool, u); err != nil {
		t.Fatal(err)
	}
	if got := target("2026-10-30"); got != 150 {
		t.Fatalf("a chosen target wins: %d", got)
	}
	// Someone who joined before the per-kilogram default keeps the flat default.
	if _, err := database.Pool.Exec(ctx, `UPDATE users SET protein_auto = false, protein_target = NULL WHERE id = $1`, u.ID); err != nil {
		t.Fatal(err)
	}
	if got := target("2026-10-31"); got != db.DefaultProteinTarget {
		t.Fatalf("existing people keep the flat default: %d", got)
	}
}

func TestOtherActivityIsStoredWithItsNameAndIntensity(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	log, created, err := db.InsertActivityLog(ctx, database.Pool, db.NewActivityLog{UserID: u.ID, LocalDate: day,
		Type: db.ActivityOtherMinutes, Quantity: 40, ClientOpID: fmt.Sprintf(opID, 1), Name: "Horse riding", Intensity: "easy"})
	if err != nil || !created || log.Name != "Horse riding" || log.Intensity != "easy" {
		t.Fatalf("log = %+v %v %v", log, created, err)
	}
	for _, intensity := range []string{"moderate", "hard"} {
		if _, _, err := db.InsertActivityLog(ctx, database.Pool, db.NewActivityLog{UserID: u.ID, LocalDate: day,
			Type: db.ActivityOtherMinutes, Quantity: 30, ClientOpID: fmt.Sprintf(opID, 10+len(intensity)), Name: "Row", Intensity: intensity}); err != nil {
			t.Fatal(err)
		}
	}
	in, err := db.LoadDayInputs(ctx, database.Pool, u.ID, day)
	if err != nil {
		t.Fatal(err)
	}
	if in.OtherFullMinutes != 60 || in.OtherEasyMinutes != 40 || in.ManualExerciseMinutes() != 80 {
		t.Fatalf("inputs = %+v, want 60 full + 40 easy -> 80 minutes", in)
	}

	bad := []db.NewActivityLog{
		{Type: db.ActivityOtherMinutes, Quantity: 10, Name: "", Intensity: "easy"},
		{Type: db.ActivityOtherMinutes, Quantity: 10, Name: "Walk"},
		{Type: db.ActivityOtherMinutes, Quantity: 10, Name: "Walk", Intensity: "brutal"},
		{Type: db.ActivityPushups, Quantity: 10, Name: "Walk", Intensity: "easy"},
		{Type: db.ActivityOtherMinutes, Quantity: 1441, Name: "Walk", Intensity: "easy"},
	}
	for i, n := range bad {
		n.UserID, n.LocalDate, n.ClientOpID = u.ID, day, fmt.Sprintf(opID, 100+i)
		if _, _, err := db.InsertActivityLog(ctx, database.Pool, n); err == nil {
			t.Errorf("case %d: the table accepted %+v", i, n)
		}
	}
}

func TestSettleDayIsOnceOnlyAndRepairNeedsASettledMiss(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	row := db.DayScoreRow{UserID: u.ID, LocalDate: day, Detail: []byte(`[]`)}
	if _, err := db.UpsertDayScore(ctx, database.Pool, row, false); err != nil {
		t.Fatal(err)
	}
	if err := db.SettleDay(ctx, database.Pool, u.ID, day, "freeze", false); err != nil {
		t.Fatal(err)
	}
	if r, _ := db.GetDayScore(ctx, database.Pool, u.ID, day); r.Settled {
		t.Fatal("an unfinalized day cannot be settled")
	}
	if _, err := db.UpsertDayScore(ctx, database.Pool, row, true); err != nil {
		t.Fatal(err)
	}
	if ok, _ := db.RepairDay(ctx, database.Pool, u.ID, day); ok {
		t.Fatal("repairing a day that is not settled")
	}
	if err := db.SettleDay(ctx, database.Pool, u.ID, day, "freeze", false); err != nil {
		t.Fatal(err)
	}
	if err := db.SettleDay(ctx, database.Pool, u.ID, day, "", true); err != nil {
		t.Fatal(err)
	}
	r, _ := db.GetDayScore(ctx, database.Pool, u.ID, day)
	if !r.Settled || r.FrozenReason != "freeze" || r.Away {
		t.Fatalf("the first settle wins: %+v", r)
	}
	if ok, _ := db.RepairDay(ctx, database.Pool, u.ID, day); ok {
		t.Fatal("a frozen day cannot be repaired")
	}
	// A rescore keeps the recorded outcome.
	if _, err := db.UpsertDayScore(ctx, database.Pool, row, true); err != nil {
		t.Fatal(err)
	}
	if r, _ := db.GetDayScore(ctx, database.Pool, u.ID, day); r.FrozenReason != "freeze" {
		t.Fatalf("rescore changed the outcome: %+v", r)
	}
}

func TestAwaySpansAndCovers(t *testing.T) {
	database := dbtest.Fresh(t)
	nick := join(t, database, "Nick", "green", true)
	nadia := join(t, database, "Nadia", "sky", false)
	span, err := db.CreateAway(ctx, database.Pool, nick.ID, "2026-10-28", "2026-10-30", "trip")
	if err != nil || !span.Contains("2026-10-29") || span.Contains("2026-10-31") {
		t.Fatalf("span = %+v %v", span, err)
	}
	if overlap, _ := db.OverlappingAway(ctx, database.Pool, nick.ID, "2026-10-30", "2026-11-02"); !overlap {
		t.Fatal("touching spans overlap")
	}
	if overlap, _ := db.OverlappingAway(ctx, database.Pool, nick.ID, "2026-10-31", "2026-11-02"); overlap {
		t.Fatal("the day after is free")
	}
	if overlap, _ := db.OverlappingAway(ctx, database.Pool, nadia.ID, "2026-10-28", "2026-10-30"); overlap {
		t.Fatal("spans are per person")
	}
	if _, err := db.CreateAway(ctx, database.Pool, nick.ID, "2026-11-01", "2026-11-15", ""); err == nil {
		t.Fatal("15 days must be refused by the table")
	}
	if _, err := db.CreateAway(ctx, database.Pool, nick.ID, "2026-11-01", "2026-11-14", ""); err != nil {
		t.Fatalf("14 days: %v", err)
	}
	if _, err := db.DeleteAway(ctx, database.Pool, nadia.ID, span.ID); err != db.ErrNotFound {
		t.Fatalf("deleting someone else's span: %v", err)
	}
	if _, err := db.DeleteAway(ctx, database.Pool, nick.ID, span.ID); err != nil {
		t.Fatal(err)
	}

	if created, err := db.CreateCover(ctx, database.Pool, nadia.ID, nick.ID, day); err != nil || !created {
		t.Fatalf("cover = %v %v", created, err)
	}
	if created, _ := db.CreateCover(ctx, database.Pool, nadia.ID, nick.ID, day); created {
		t.Fatal("a day is covered once")
	}
	covered, spent, _ := db.CoversFor(ctx, database.Pool, nadia.ID)
	if len(covered) != 1 || len(spent) != 0 || covered[0].ByUser != nick.ID {
		t.Fatalf("covers for nadia = %v %v", covered, spent)
	}
	covered, spent, _ = db.CoversFor(ctx, database.Pool, nick.ID)
	if len(covered) != 0 || len(spent) != 1 {
		t.Fatalf("covers for nick = %v %v", covered, spent)
	}
}

func TestMilestonesAreRecordedOnce(t *testing.T) {
	database := dbtest.Fresh(t)
	nick := join(t, database, "Nick", "green", true)
	m, created, err := db.RecordMilestone(ctx, database.Pool, &nick.ID, db.MilestoneStreak, 7, day)
	if err != nil || !created || m.ID == 0 || m.UserID == nil {
		t.Fatalf("first = %+v %v %v", m, created, err)
	}
	if _, created, _ := db.RecordMilestone(ctx, database.Pool, &nick.ID, db.MilestoneStreak, 7, day.AddDays(3)); created {
		t.Fatal("recorded twice")
	}
	if _, created, _ := db.RecordMilestone(ctx, database.Pool, nil, db.MilestoneSharedStreak, 7, day); !created {
		t.Fatal("a shared milestone is separate from a personal one")
	}
	if _, created, _ := db.RecordMilestone(ctx, database.Pool, nil, db.MilestoneSharedStreak, 7, day); created {
		t.Fatal("shared recorded twice")
	}
	if _, _, err := db.RecordMilestone(ctx, database.Pool, &nick.ID, db.MilestoneSharedStreak, 7, day); err == nil {
		t.Fatal("a shared kind needs no user")
	}
	have, err := db.MilestoneKinds(ctx, database.Pool, &nick.ID)
	if err != nil || !have["streak:7"] || have["shared_streak:7"] {
		t.Fatalf("kinds = %v %v", have, err)
	}
	mine, _ := db.ListMilestones(ctx, database.Pool, nick.ID)
	if len(mine) != 2 {
		t.Fatalf("list = %v, want the personal and the shared one", mine)
	}
	if recent, _ := db.MilestonesSince(ctx, database.Pool, nick.ID, day.AddDays(1)); len(recent) != 0 {
		t.Fatalf("since = %v", recent)
	}
}

func TestFirstsAreFoundInStoredData(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	if d, err := db.FirstDayOver(ctx, database.Pool, u.ID, db.MetricSteps, 10000); err != nil || d != "" {
		t.Fatalf("first 10k with no data = %q %v", d, err)
	}
	for i, steps := range []float64{9999, 10000, 12000} {
		if _, err := db.UpsertHealthDaily(ctx, database.Pool, u.ID, day.AddDays(i), db.MetricSteps, steps, "healthkit", time.Now()); err != nil {
			t.Fatal(err)
		}
	}
	if d, _ := db.FirstDayOver(ctx, database.Pool, u.ID, db.MetricSteps, 10000); d != day.AddDays(1) {
		t.Fatalf("first 10k day = %q", d)
	}

	complete := []byte(`[{"key":"steps","complete":true},{"key":"pushups","complete":true}]`)
	partial := []byte(`[{"key":"steps","complete":true},{"key":"pushups","complete":false}]`)
	store := func(date score.Date, counted bool, detail []byte) {
		base := 0
		if counted {
			base = 100
		}
		if _, err := db.UpsertDayScore(ctx, database.Pool, db.DayScoreRow{UserID: u.ID, LocalDate: date, BasePoints: base,
			MaxBase: 100, Percent: base, Counted: counted, Detail: detail}, true); err != nil {
			t.Fatal(err)
		}
	}
	monday := score.MustDate("2026-11-02")
	store(monday.AddDays(-7), true, partial)
	if d, _ := db.FirstAllQuestsDay(ctx, database.Pool, u.ID); d != "" {
		t.Fatalf("a partial day is not every quest: %q", d)
	}
	for i := 0; i < 7; i++ {
		detail := partial
		if i == 3 {
			detail = complete
		}
		store(monday.AddDays(i), true, detail)
	}
	if d, _ := db.FirstAllQuestsDay(ctx, database.Pool, u.ID); d != monday.AddDays(3) {
		t.Fatalf("first all-quests day = %q", d)
	}
	if d, _ := db.FirstFullWeek(ctx, database.Pool, u.ID); d != monday.AddDays(6) {
		t.Fatalf("first full week ends %q, want %s", d, monday.AddDays(6))
	}
	store(monday.AddDays(2), false, partial)
	if d, _ := db.FirstFullWeek(ctx, database.Pool, u.ID); d != "" {
		t.Fatalf("a week with a missed day is not full: %q", d)
	}
}

func TestChallengeSharesAreStoredPerPerson(t *testing.T) {
	database := dbtest.Fresh(t)
	nick := join(t, database, "Nick", "green", true)
	week := score.MustDate("2026-11-02")
	ch, err := db.InsertChallenge(ctx, database.Pool, db.Challenge{WeekStart: week, Kind: "steps", Title: "x", Target: 1})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.InsertChallengeShare(ctx, database.Pool, ch.ID, nick.ID, 60000); err != nil {
		t.Fatal(err)
	}
	if err := db.InsertChallengeShare(ctx, database.Pool, ch.ID, nick.ID, 1); err != nil {
		t.Fatal(err)
	}
	shares, _ := db.ChallengeShares(ctx, database.Pool, ch.ID)
	if len(shares) != 1 || shares[nick.ID] != 60000 {
		t.Fatalf("shares = %v, the first share stays", shares)
	}
	if err := db.SetChallengeTarget(ctx, database.Pool, ch.ID, 60000, "Walk 60,000 steps together"); err != nil {
		t.Fatal(err)
	}
	got, _ := db.GetChallenge(ctx, database.Pool, week)
	if got.Target != 60000 || got.Title != "Walk 60,000 steps together" {
		t.Fatalf("challenge = %+v", got)
	}
	if _, err := db.CompleteChallenge(ctx, database.Pool, ch.ID); err != nil {
		t.Fatal(err)
	}
	if err := db.SetChallengeTarget(ctx, database.Pool, ch.ID, 1, "changed"); err != nil {
		t.Fatal(err)
	}
	if got, _ := db.GetChallenge(ctx, database.Pool, week); got.Target != 60000 {
		t.Fatalf("a completed challenge is frozen: %+v", got)
	}
}
