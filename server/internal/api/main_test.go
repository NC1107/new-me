package api

import (
	"os"
	"testing"

	"github.com/nc1107/new-me/server/internal/dbtest"
)

func TestMain(m *testing.M) {
	dbtest.Require()
	os.Exit(m.Run())
}
