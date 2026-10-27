package auth

import (
	"regexp"
	"testing"
)

func TestInviteCodeShapeAndUniqueness(t *testing.T) {
	shape := regexp.MustCompile(`^[0-9A-HJKMNP-TV-Z]{4}(-[0-9A-HJKMNP-TV-Z]{4}){3}$`)
	seen := map[string]bool{}
	for range 200 {
		code, err := NewInviteCode()
		if err != nil {
			t.Fatal(err)
		}
		if !shape.MatchString(code) {
			t.Fatalf("code %q has the wrong shape", code)
		}
		if seen[code] {
			t.Fatalf("code %q repeated", code)
		}
		seen[code] = true
	}
}

func TestNormalizeAcceptsHumanInput(t *testing.T) {
	want := NormalizeInviteCode("ABCD-EFGH-JKMN-PQRS")
	if want == "" {
		t.Fatal("a canonical code must normalize")
	}
	for _, in := range []string{"abcd efgh jkmn pqrs", "abcdefghjkmnpqrs", " ABCD-EFGH-JKMN-PQRS "} {
		if got := NormalizeInviteCode(in); got != want {
			t.Fatalf("Normalize(%q) = %q, want %q", in, got, want)
		}
	}
	if NormalizeInviteCode("0000-0000-0000-1111") != NormalizeInviteCode("OOOO-OOOO-OOOO-IIII") ||
		NormalizeInviteCode("0000-0000-0000-1111") != NormalizeInviteCode("OOOO-OOOO-OOOO-LLLL") {
		t.Fatal("O reads as 0, and I and L read as 1")
	}
}

func TestNormalizeRejectsMalformedCodes(t *testing.T) {
	for _, in := range []string{"", "ABCD", "ABCD-EFGH-JKMN-PQRSX", "ABCD-EFGH-JKMN-PQR!", "ABCD-EFGH-JKMN-PQRU"} {
		if got := NormalizeInviteCode(in); got != "" {
			t.Fatalf("Normalize(%q) = %q, want empty", in, got)
		}
	}
}

func TestHashInviteCodeIgnoresFormatting(t *testing.T) {
	if HashInviteCode("abcd-efgh-jkmn-pqrs") != HashInviteCode("ABCDEFGHJKMNPQRS") {
		t.Fatal("formatting must not change the hash")
	}
	if HashInviteCode("nonsense") == HashInviteCode("ABCDEFGHJKMNPQRS") {
		t.Fatal("a malformed code must not collide with a real one")
	}
}
