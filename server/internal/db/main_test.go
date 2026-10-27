package db_test

import (
	"context"
	"os"
	"testing"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/dbtest"
	"github.com/nc1107/new-me/server/internal/score"
)

func TestMain(m *testing.M) {
	dbtest.Require()
	os.Exit(m.Run())
}

var ctx = context.Background()

// join creates a user the way a join request would, in its own transaction.
func join(t *testing.T, database *db.DB, name, color string, admin bool) db.User {
	t.Helper()
	var u db.User
	err := database.WithTx(ctx, func(tx pgx.Tx) error {
		var err error
		u, err = db.CreateUser(ctx, tx, db.NewUser{
			Name: name, Color: color, Timezone: "America/New_York", IsAdmin: admin,
			JoinedOn: score.MustDate("2026-10-26"),
		}, 2)
		return err
	})
	if err != nil {
		t.Fatalf("create %s: %v", name, err)
	}
	return u
}

const opID = "11111111-1111-4111-8111-%012d"
