package db_test

import (
	"testing"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/dbtest"
	"github.com/nc1107/new-me/server/internal/score"
)

func dayQuest(t *testing.T, database *db.DB, userID int64, day score.Date, key string) (db.DayQuest, bool) {
	t.Helper()
	if err := db.EnsureSnapshot(ctx, database.Pool, userID, day); err != nil {
		t.Fatal(err)
	}
	quests, err := db.GetDayQuests(ctx, database.Pool, userID, day)
	if err != nil {
		t.Fatal(err)
	}
	for _, q := range quests {
		if q.Key == key {
			return q, true
		}
	}
	return db.DayQuest{}, false
}

func TestCalorieRangeSnapshotsAroundTheTarget(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	kcal, male := 2450, "male"
	u.KcalTarget, u.Sex = &kcal, &male
	if err := db.UpdateUser(ctx, database.Pool, u); err != nil {
		t.Fatal(err)
	}
	q, ok := dayQuest(t, database, u.ID, score.MustDate("2026-11-10"), db.QuestCalories)
	if !ok || q.Target != 2200 || q.TargetAlt == nil || *q.TargetAlt != 2700 || q.Unit != "kcal" {
		t.Fatalf("calories = %+v (found %v), want 2,200 to 2,700 kcal: 2,450 plus or minus 10%%, to 50", q, ok)
	}
}

func TestCalorieRangeNeverStartsBelowTheLeastDailyEnergy(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Ana", "violet", false)
	kcal, female := 1300, "female"
	u.KcalTarget, u.Sex = &kcal, &female
	if err := db.UpdateUser(ctx, database.Pool, u); err != nil {
		t.Fatal(err)
	}
	q, _ := dayQuest(t, database, u.ID, score.MustDate("2026-11-10"), db.QuestCalories)
	if q.Target != 1200 || *q.TargetAlt != 1450 {
		t.Fatalf("range = %d to %d, want 1,200 (not 1,150) to 1,450", q.Target, *q.TargetAlt)
	}
}

func TestCalorieRangeWaitsForACalorieTarget(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	if _, ok := dayQuest(t, database, u.ID, score.MustDate("2026-11-10"), db.QuestCalories); ok {
		t.Fatal("with no calorie target there is no range to score, so the goal stays out of the day")
	}
}
