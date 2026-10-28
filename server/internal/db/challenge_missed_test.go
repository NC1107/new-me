package db_test

import (
	"testing"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/dbtest"
	"github.com/nc1107/new-me/server/internal/score"
)

func TestCloseMissedChallengesOnlyLooksBackTwoWeeks(t *testing.T) {
	database := dbtest.Fresh(t)
	for _, week := range []string{"2026-10-05", "2026-10-12", "2026-10-19", "2026-10-26", "2026-11-02"} {
		if _, err := database.Pool.Exec(ctx,
			`INSERT INTO challenges (week_start, kind, title, target) VALUES ($1::date, 'workouts', 't', 3)`, week); err != nil {
			t.Fatal(err)
		}
	}
	n, err := db.CloseMissedChallenges(ctx, database.Pool, score.MustDate("2026-11-02"))
	if err != nil || n != 2 {
		t.Fatalf("closed %d (err %v), want the two weeks before the current one", n, err)
	}
	var missed []string
	rows, err := database.Pool.Query(ctx, `SELECT week_start::text FROM challenges WHERE missed_at IS NOT NULL ORDER BY week_start`)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	for rows.Next() {
		var w string
		if err := rows.Scan(&w); err != nil {
			t.Fatal(err)
		}
		missed = append(missed, w)
	}
	if len(missed) != 2 || missed[0] != "2026-10-19" || missed[1] != "2026-10-26" {
		t.Fatalf("missed = %v", missed)
	}
}
