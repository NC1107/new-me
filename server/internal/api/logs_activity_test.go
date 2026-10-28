package api

import (
	"testing"

	"github.com/nc1107/new-me/server/internal/db"
)

func TestStoredActivityResolvesEveryWireTypeFromOneTable(t *testing.T) {
	cases := []struct {
		typ, unit, want string
		ok              bool
	}{
		{"pushups", "", db.ActivityPushups, true},
		{"reading", "minutes", db.ActivityReadingMinutes, true},
		{"reading", "pages", db.ActivityReadingPages, true},
		{"reading", "", "", false},
		{"yoga", "", db.ActivityYogaMinutes, true},
		{"water", "ml", db.ActivityWaterML, true},
		{"water", "", db.ActivityWaterML, true},
		{"water", "l", "", false},
		{"produce", "", db.ActivityProduce, true},
		{"breathing", "minutes", db.ActivityBreathing, true},
		{"other", "", db.ActivityOtherMinutes, true},
		{db.ActivityWaterML, "", db.ActivityWaterML, true},
		{"swimming", "", "", false},
	}
	for _, c := range cases {
		got, ok := storedActivity(c.typ, c.unit)
		if ok != c.ok || (ok && got != c.want) {
			t.Errorf("storedActivity(%q, %q) = %q %v, want %q %v", c.typ, c.unit, got, ok, c.want, c.ok)
		}
	}
}
