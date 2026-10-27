package estimate

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"math"
	"strings"
	"testing"
)

func b64(b []byte) string { return base64.StdEncoding.EncodeToString(b) }

func TestParseClampsToTheMealLogBounds(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want Estimate
	}{
		{"clean", `{"name":"Burrito bowl","kcal":742.4,"protein":38.26,"carbs":71,"fat":28,"fiber":11,"confidence":"high","notes":"Assumes a large bowl."}`,
			Estimate{Name: "Burrito bowl", Kcal: 742, Protein: 38.3, Carbs: 71, Fat: 28, Fiber: 11, Confidence: "high", Notes: "Assumes a large bowl."}},
		{"too big", `{"name":"x","kcal":99999,"protein":99999,"carbs":-4,"fat":1,"fiber":1,"confidence":"medium","notes":""}`,
			Estimate{Name: "x", Kcal: 10000, Protein: 5000, Confidence: "medium", Fat: 1, Fiber: 1}},
		{"zero kcal floors at one", `{"name":"water","kcal":0,"confidence":"high"}`,
			Estimate{Name: "water", Kcal: 1, Confidence: "high"}},
		{"unknown confidence and blank name", `{"name":"  ","kcal":300,"confidence":"certain"}`,
			Estimate{Name: "Meal", Kcal: 300, Confidence: "low"}},
		{"control characters and length", `{"name":"` + strings.Repeat("ab\\n", 60) + `","kcal":100,"confidence":"LOW","notes":"` + strings.Repeat("n", 300) + `"}`,
			Estimate{}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := Parse(json.RawMessage(tc.in))
			if err != nil {
				t.Fatal(err)
			}
			if tc.name == "control characters and length" {
				if len([]rune(got.Name)) > MaxNameRunes || strings.ContainsAny(got.Name, "\n\r") ||
					len([]rune(got.Notes)) != MaxNoteRunes || got.Confidence != "low" {
					t.Fatalf("got %+v", got)
				}
				return
			}
			if got != tc.want {
				t.Fatalf("got %+v, want %+v", got, tc.want)
			}
		})
	}
}

func TestParseRejectsAnswersWithoutEnergy(t *testing.T) {
	for _, in := range []string{`{}`, `{"name":"x"}`, `{"kcal":"lots"}`, `[]`, `not json`} {
		if _, err := Parse(json.RawMessage(in)); !errors.Is(err, ErrUnusable) {
			t.Errorf("%s: err = %v, want ErrUnusable", in, err)
		}
	}
	if g := grams(ptr(math.NaN())); g != 0 {
		t.Errorf("NaN grams = %v", g)
	}
}

func ptr(v float64) *float64 { return &v }

func TestValidateImage(t *testing.T) {
	jpeg := append([]byte{0xFF, 0xD8, 0xFF, 0xE0}, make([]byte, 100)...)
	png := append([]byte("\x89PNG\r\n\x1a\x0a"), make([]byte, 100)...)
	big := append([]byte{0xFF, 0xD8, 0xFF}, make([]byte, MaxImageBytes)...)
	cases := []struct {
		name, media, data string
		want              error
	}{
		{"jpeg", "image/jpeg", b64(jpeg), nil},
		{"png", "image/png", b64(png), nil},
		{"declared png but jpeg", "image/png", b64(jpeg), ErrBadImage},
		{"gif", "image/gif", b64(jpeg), ErrBadImage},
		{"not base64", "image/jpeg", "%%%", ErrBadImage},
		{"empty", "image/jpeg", "", ErrBadImage},
		{"decoded over 5 MB", "image/jpeg", b64(big), ErrImageTooLarge},
		{"absurdly long", "image/jpeg", strings.Repeat("A", 8<<20), ErrImageTooLarge},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := ValidateImage(tc.media, tc.data); !errors.Is(err, tc.want) {
				t.Fatalf("err = %v, want %v", err, tc.want)
			}
		})
	}
	exactly := append([]byte{0xFF, 0xD8, 0xFF}, make([]byte, MaxImageBytes-3)...)
	if _, err := ValidateImage("image/jpeg", b64(exactly)); err != nil {
		t.Fatalf("5 MB exactly must pass: %v", err)
	}
}
