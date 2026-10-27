package semver

import "testing"

func TestParse(t *testing.T) {
	cases := map[string]Version{
		"1.2.3":       {1, 2, 3},
		"v1.2":        {1, 2, 0},
		"7":           {7, 0, 0},
		"0.1.0+4":     {0, 1, 0},
		"2.0.0-rc.1":  {2, 0, 0},
		" 10.20.30  ": {10, 20, 30},
	}
	for in, want := range cases {
		got, err := Parse(in)
		if err != nil || got != want {
			t.Fatalf("Parse(%q) = %v, %v; want %v", in, got, err, want)
		}
	}
	for _, in := range []string{"", "dev", "1.2.3.4", "1.x", "-1.0.0", "1..2"} {
		if _, err := Parse(in); err == nil {
			t.Fatalf("Parse(%q) should fail", in)
		}
	}
}

func TestLess(t *testing.T) {
	if !(Version{0, 9, 9}).Less(Version{1, 0, 0}) || !(Version{1, 2, 3}).Less(Version{1, 2, 4}) {
		t.Fatal("older versions must sort first")
	}
	if (Version{1, 2, 3}).Less(Version{1, 2, 3}) || (Version{2, 0, 0}).Less(Version{1, 9, 9}) {
		t.Fatal("equal or newer versions are not less")
	}
}
