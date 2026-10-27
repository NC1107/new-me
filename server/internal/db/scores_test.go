package db_test

import (
	"errors"
	"testing"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/dbtest"
	"github.com/nc1107/new-me/server/internal/score"
)

func row(userID int64, date score.Date, base, bonus, max int) db.DayScoreRow {
	d := score.ScoreDay([]score.QuestResult{{Key: "x", Points: max, Actual: base, Target: max}})
	return db.DayScoreRow{UserID: userID, LocalDate: date, BasePoints: base, BonusPoints: bonus,
		MaxBase: max, Percent: d.Percent, Counted: d.Counted, Detail: []byte(`[]`)}
}

func TestDayScoreUpsertKeepsFinalization(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)

	got, err := db.UpsertDayScore(ctx, database.Pool, row(u.ID, day, 50, 0, 100), false)
	if err != nil || got.FinalizedAt != nil || got.Counted {
		t.Fatalf("first upsert = %+v %v", got, err)
	}
	got, err = db.UpsertDayScore(ctx, database.Pool, row(u.ID, day, 80, 20, 100), true)
	if err != nil || got.FinalizedAt == nil || !got.Counted || got.Points() != 100 {
		t.Fatalf("finalizing upsert = %+v %v", got, err)
	}
	stamp := *got.FinalizedAt
	got, err = db.UpsertDayScore(ctx, database.Pool, row(u.ID, day, 60, 0, 100), false)
	if err != nil || got.FinalizedAt == nil || !got.FinalizedAt.Equal(stamp) || got.BasePoints != 60 {
		t.Fatalf("recompute inside the window = %+v %v; it must stay finalized", got, err)
	}
	if _, err := db.GetDayScore(ctx, database.Pool, u.ID, day.AddDays(1)); !errors.Is(err, db.ErrNotFound) {
		t.Fatalf("missing day err = %v", err)
	}
}

func TestDayScoreRejectsInconsistentCountedFlag(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	bad := row(u.ID, day, 50, 0, 100)
	bad.Counted = true
	if _, err := db.UpsertDayScore(ctx, database.Pool, bad, false); err == nil {
		t.Fatal("a row claiming counted below 70% must be rejected")
	}
}

func TestRangeReadsAndSums(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	other := join(t, database, "Nadia", "sky", false)
	for i, base := range []int{100, 70, 30} {
		if _, err := db.UpsertDayScore(ctx, database.Pool, row(u.ID, day.AddDays(i), base, base/5, 100), false); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := db.UpsertDayScore(ctx, database.Pool, row(other.ID, day, 100, 20, 100), false); err != nil {
		t.Fatal(err)
	}

	rows, err := db.ListDayScores(ctx, database.Pool, u.ID, day, day.AddDays(1))
	if err != nil || len(rows) != 2 || rows[0].LocalDate != day || rows[1].LocalDate != day.AddDays(1) {
		t.Fatalf("range = %+v %v", rows, err)
	}
	total, err := db.SumPoints(ctx, database.Pool, u.ID, day, day.AddDays(2))
	if err != nil || total != (100+20)+(70+14)+(30+6) {
		t.Fatalf("sum = %d %v", total, err)
	}
	if empty, _ := db.SumPoints(ctx, database.Pool, u.ID, day.AddDays(10), day.AddDays(12)); empty != 0 {
		t.Fatalf("empty range sum = %d", empty)
	}
}

func TestUnfinalizedDatesIncludesGapsAndSkipsFinalized(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	if _, err := db.UpsertDayScore(ctx, database.Pool, row(u.ID, day, 100, 20, 100), true); err != nil {
		t.Fatal(err)
	}
	if _, err := db.UpsertDayScore(ctx, database.Pool, row(u.ID, day.AddDays(1), 10, 0, 100), false); err != nil {
		t.Fatal(err)
	}

	got, err := db.UnfinalizedDates(ctx, database.Pool, u.ID, day.AddDays(-1), day.AddDays(3))
	if err != nil {
		t.Fatal(err)
	}
	want := []score.Date{day.AddDays(-1), day.AddDays(1), day.AddDays(2), day.AddDays(3)}
	if len(got) != len(want) {
		t.Fatalf("dates = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("dates = %v, want %v", got, want)
		}
	}
	if none, err := db.UnfinalizedDates(ctx, database.Pool, u.ID, day.AddDays(5), day.AddDays(4)); err != nil || len(none) != 0 {
		t.Fatalf("inverted range = %v %v", none, err)
	}
}
